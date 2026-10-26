extends Node
## Headless test runner for Scrap to Space.
##
## Run with:
##   godot --headless --path . tests/test_runner.tscn -- --test-mode
##
## Exits with code 1 when any assertion fails.

const Catalog = preload("res://scripts/data/game_catalog.gd")
const MergeRules = preload("res://scripts/logic/merge_rules.gd")
const EconomyRules = preload("res://scripts/logic/economy_rules.gd")
const ExpeditionRules = preload("res://scripts/logic/expedition_rules.gd")

const TEST_SAVE := "user://scrap_to_space_test_run.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	SaveManager.autosave_enabled = false
	SaveManager.save_path = TEST_SAVE
	SaveManager.delete_save()
	_cleanup_quarantine_files()

	print("=== Scrap to Space test run ===")

	_test_catalog()
	_test_merge_rules()
	_test_new_game()
	_test_board_operations()
	_test_selling()
	_test_economy_limits()
	_test_board_expansion()
	_test_orders()
	_test_ship_parts()
	_test_destinations()
	_test_expeditions()
	_test_tutorial()
	_test_collect_and_nowhere_to_put_it()
	_test_save_round_trip()
	_test_save_recovery()
	_test_active_expedition_persistence()
	_test_offline_production()
	_test_optional_services()
	await _test_monetization()

	SaveManager.delete_save()
	_cleanup_quarantine_files()

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- Catalog ----------------------------------------------------------------
func _test_catalog() -> void:
	var circuits: Array = Catalog.tier_ids("circuit")
	_check_eq(circuits.size(), 8, "circuit merge chain has 8 tiers")
	_check_eq(str(circuits[0]), "broken_circuit", "circuit chain starts at Broken Circuit")
	_check_eq(str(circuits[7]), "warp_drive", "circuit chain ends at Warp Drive Component")
	_check_eq(str(Catalog.item("broken_circuit")["next_id"]), "repaired_circuit", "tier 1 links to tier 2")
	_check_eq(str(Catalog.item("warp_drive")["next_id"]), "", "top tier has no next item")

	var ids: Dictionary = {}
	var duplicates: int = 0
	for family_id in Catalog.FAMILY_DEFS:
		var family: Dictionary = Catalog.FAMILY_DEFS[family_id]
		var previous_value: int = 0
		var increasing: bool = true
		for item_id in Catalog.tier_ids(family_id):
			if ids.has(item_id):
				duplicates += 1
			ids[item_id] = true
			var value: int = Catalog.sell_value(item_id)
			if value <= previous_value:
				increasing = false
			previous_value = value
		_check(increasing, "%s value increases with every tier" % family["label"])
	_check_eq(duplicates, 0, "item ids are unique across families")
	_check(Catalog.items().size() >= 18, "catalog exposes at least 18 items")


# --- Merge rules ------------------------------------------------------------
func _test_merge_rules() -> void:
	_check(MergeRules.can_merge("broken_circuit", "broken_circuit"), "identical tier 1 items can merge")
	_check(not MergeRules.can_merge("broken_circuit", "repaired_circuit"), "different tiers cannot merge")
	_check(not MergeRules.can_merge("broken_circuit", "rusted_plate"), "different families cannot merge")
	_check(not MergeRules.can_merge("warp_drive", "warp_drive"), "top tier items cannot merge")
	_check_eq(MergeRules.merge_target("electronic_module", "electronic_module"), "processing_unit", "merge target is the next tier")
	_check(str(MergeRules.failure_reason("warp_drive", "warp_drive")).contains("highest"), "max-tier failure explains itself")


func _test_new_game() -> void:
	GameState.new_game()
	_check_eq(GameState.credits, Catalog.STARTING_CREDITS, "new game starts with the configured credits")
	_check_eq(GameState.board_size(), 30, "new game board has 5x6 = 30 slots")
	_check_eq(GameState.generator_levels().get("collector", 0), 1, "collector starts at level 1")
	_check_eq(GameState.generator_levels().get("sorter", 0), 0, "sorter starts unbuilt")
	_check_eq(GameState.item_count("broken_circuit"), 8, "starter board seeds broken circuits")
	_check(GameState.tutorial_active(), "tutorial starts active")
	_check_eq(GameState.unlocked_planets, ["junkyard"], "only the junkyard is unlocked at the start")


# --- Board ------------------------------------------------------------------
func _test_board_operations() -> void:
	GameState.new_game()
	_clear_board()

	# Moving into an empty slot.
	GameState.board[0] = "broken_circuit"
	var move_result: Dictionary = GameState.attempt_drop(0, 5)
	_check(bool(move_result.get("ok", false)), "item moves into an empty slot")
	_check_eq(GameState.board[5], "broken_circuit", "moved item lands in the target slot")
	_check_eq(GameState.board[0], null, "source slot is emptied by a move")
	_check_eq(_count_items(), 1, "moving never duplicates items")

	# Merging two identical items.
	_clear_board()
	GameState.board[0] = "broken_circuit"
	GameState.board[1] = "broken_circuit"
	var merge_result: Dictionary = GameState.attempt_drop(0, 1)
	_check(bool(merge_result.get("ok", false)), "identical items merge")
	_check_eq(str(merge_result.get("action", "")), "merge", "merge result reports a merge")
	_check_eq(GameState.board[1], "repaired_circuit", "merge produces the next tier")
	_check_eq(GameState.board[0], null, "merge consumes both inputs")
	_check_eq(_count_items(), 1, "merge does not duplicate items")

	# Incompatible items stay put.
	_clear_board()
	GameState.board[0] = "broken_circuit"
	GameState.board[1] = "rusted_plate"
	var invalid: Dictionary = GameState.attempt_drop(0, 1)
	_check(not bool(invalid.get("ok", false)), "different items do not merge")
	_check_eq(GameState.board[0], "broken_circuit", "failed merge leaves the source intact")
	_check_eq(GameState.board[1], "rusted_plate", "failed merge leaves the target intact")
	_check_eq(_count_items(), 2, "failed merge loses nothing")

	# Highest tier cannot merge.
	_clear_board()
	GameState.board[0] = "warp_drive"
	GameState.board[1] = "warp_drive"
	var max_tier: Dictionary = GameState.attempt_drop(0, 1)
	_check(not bool(max_tier.get("ok", false)), "maximum tier items cannot merge")
	_check_eq(_count_items(), 2, "max-tier failure keeps both items")

	# Out of bounds and empty source are guarded.
	_check(not bool(GameState.attempt_drop(0, 999).get("ok", false)), "out-of-bounds drops are rejected")
	_clear_board()
	_check(not bool(GameState.attempt_drop(3, 4).get("ok", false)), "dragging an empty slot does nothing")


func _test_selling() -> void:
	GameState.new_game()
	_clear_board()
	GameState.board[2] = "electronic_module"
	var before: int = GameState.credits
	var value: int = Catalog.sell_value("electronic_module")
	var result: Dictionary = GameState.sell_item_at(2)
	_check(bool(result.get("ok", false)), "selling a selected item succeeds")
	_check_eq(GameState.credits, before + value, "selling awards exactly the item sell value")
	_check_eq(GameState.board[2], null, "sold item is removed from the board")

	var empty_result: Dictionary = GameState.sell_selected()
	_check(not bool(empty_result.get("ok", false)), "selling with no selection fails safely")


func _test_economy_limits() -> void:
	GameState.new_game()
	_clear_board()
	GameState.credits = 100

	var cost: int = GameState.next_generator_cost("collector")
	_check_eq(cost, 50, "first collector upgrade costs the configured base price")
	var upgrade: Dictionary = GameState.upgrade_generator("collector")
	_check(bool(upgrade.get("ok", false)), "collector upgrade succeeds when affordable")
	_check_eq(GameState.credits, 50, "upgrade deducts the exact price")
	_check_eq(GameState.part_level("hull"), 1, "unrelated state is untouched")

	var second_cost: int = GameState.next_generator_cost("collector")
	_check_eq(second_cost, 80, "second upgrade cost follows the growth curve")
	var blocked: Dictionary = GameState.upgrade_generator("collector")
	_check(not bool(blocked.get("ok", false)), "upgrade is blocked when credits are short")
	_check_eq(GameState.credits, 50, "blocked upgrade does not spend credits")
	_check_eq(GameState.generator_levels().get("collector", 0), 2, "blocked upgrade does not change level")

	var locked: Dictionary = GameState.upgrade_generator("sorter")
	_check(not bool(locked.get("ok", false)), "sorter requires collector level 3")
	_check(str(locked.get("message", "")).contains("Requires"), "locked upgrade explains the requirement")


func _test_board_expansion() -> void:
	GameState.new_game()
	GameState.credits = 1000
	var result: Dictionary = GameState.buy_expansion()
	_check(bool(result.get("ok", false)), "board expansion can be purchased")
	_check_eq(GameState.board_size(), 35, "first expansion adds a 7th row")
	_check_eq(GameState.board_rows, 7, "board rows track the expansion")
	_check_eq(GameState.credits, 600, "expansion deducts the configured price")

	GameState.credits = 10
	var blocked: Dictionary = GameState.buy_expansion()
	_check(not bool(blocked.get("ok", false)), "expansion is blocked without credits")
	_check_eq(GameState.board_size(), 35, "blocked expansion does not grow the board")


func _test_orders() -> void:
	GameState.new_game()
	_clear_board()
	var order: Dictionary = GameState.orders[0]
	var item_id: String = str(order["item_id"])
	var quantity: int = int(order["qty"])
	for index in quantity:
		GameState.board[index] = item_id

	var missing_now: Dictionary = GameState.deliver_order(0)
	_check(bool(missing_now.get("ok", false)), "order delivers when the items are on the board")
	_check_eq(GameState.item_count(item_id), 0, "delivered items leave the board")
	_check(GameState.credits > Catalog.STARTING_CREDITS, "order pays a credit reward")
	_check(not (GameState.orders[0] as Dictionary).is_empty(), "a fresh order replaces the delivered one")

	var failing: Dictionary = GameState.deliver_order(0)
	_check(not bool(failing.get("ok", false)), "orders cannot be delivered without the items")


func _test_ship_parts() -> void:
	GameState.new_game()
	_clear_board()
	GameState.credits = 10000
	var hull_cost: Dictionary = GameState.next_part_upgrade("hull")
	_check_eq(int(hull_cost.get("credits", 0)), 150, "hull level 2 price matches the catalog")

	var built: Dictionary = GameState.build_part("hull")
	_check(bool(built.get("ok", false)), "hull can be constructed when affordable")
	_check_eq(GameState.part_level("hull"), 2, "hull level increases")
	_check_eq(GameState.credits, 9850, "hull construction deducts credits")

	var next_cost: Dictionary = GameState.next_part_upgrade("hull")
	_check_eq(int((next_cost.get("items", {}) as Dictionary).get("rusted_plate", 0)), 2, "hull level 3 requires alloy plates")
	var missing: Dictionary = GameState.build_part("hull")
	_check(not bool(missing.get("ok", false)), "hull build is blocked without the required components")
	_check(str(missing.get("message", "")).contains("Missing"), "missing-components message is explicit")

	GameState.board[0] = "rusted_plate"
	GameState.board[1] = "rusted_plate"
	var with_items: Dictionary = GameState.build_part("hull")
	_check(bool(with_items.get("ok", false)), "hull build succeeds once the components are on the board")
	_check_eq(GameState.part_level("hull"), 3, "hull reaches level 3")
	_check_eq(GameState.item_count("rusted_plate"), 0, "ship construction consumes the components")

	GameState.parts["hull"] = Catalog.PART_MAX_LEVEL
	_check(not bool(GameState.build_part("hull").get("ok", false)), "max-level components cannot be rebuilt")


func _test_destinations() -> void:
	GameState.new_game()
	var status: Dictionary = ExpeditionRules.requirements_status(Catalog.planet("junkyard"), GameState.parts)
	_check(bool(status.get("ok", false)), "junkyard requirements are met by the starter ship")

	var rustfall: Dictionary = ExpeditionRules.requirements_status(Catalog.planet("rustfall"), GameState.parts)
	_check(not bool(rustfall.get("ok", false)), "rustfall is locked on a fresh ship")
	_check_eq((rustfall["missing"] as Array).size(), 2, "rustfall reports both missing components")

	GameState.parts["engine"] = 2
	GameState.parts["hull"] = 2
	_check("rustfall" in GameState.compute_unlocked_planets(), "engine + hull unlock rustfall")
	_check(not ("neon_moon" in GameState.compute_unlocked_planets()), "neon moon still needs navigation")

	GameState.parts["navigation"] = 3
	GameState.parts["power_core"] = 3
	_check("neon_moon" in GameState.compute_unlocked_planets(), "navigation + power unlock neon moon")


func _test_expeditions() -> void:
	GameState.new_game()
	_clear_board()

	var planet: Dictionary = Catalog.planet("junkyard")
	var first: Dictionary = ExpeditionRules.roll_rewards(planet, GameState.parts, 4242)
	var second: Dictionary = ExpeditionRules.roll_rewards(planet, GameState.parts, 4242)
	_check(first == second, "expedition rewards are deterministic for a seed")
	_check(int(first["credits"]) > 0, "expedition rolls award credits")
	_check(int(first["count"]) >= 1, "expedition rolls award at least one item")

	var started: Dictionary = GameState.start_expedition("junkyard")
	_check(bool(started.get("ok", false)), "expedition can launch from the junkyard")
	_check(not GameState.expedition.is_empty(), "active expedition is recorded")

	var too_early: Dictionary = GameState.claim_expedition()
	_check(not bool(too_early.get("ok", false)), "expedition cannot be claimed before arrival")

	var cannot_restart: Dictionary = GameState.start_expedition("rustfall")
	_check(not bool(cannot_restart.get("ok", false)), "only one expedition can run at a time")

	GameState.expedition["end_unix"] = Time.get_unix_time_from_system() - 1.0
	var credits_before: int = GameState.credits
	var expected_credits: int = int((GameState.expedition["rewards"] as Dictionary).get("credits", 0))
	var claim: Dictionary = GameState.claim_expedition()
	_check(bool(claim.get("ok", false)), "expedition can be claimed after arrival")
	_check(GameState.credits >= credits_before + expected_credits, "claim pays the rolled credits")
	_check(GameState.expedition.is_empty(), "claim clears the active expedition")
	_check_eq(int(GameState.stats["expeditions"]), 1, "expedition counter increments")


func _test_tutorial() -> void:
	GameState.new_game()
	_check_eq(int(GameState.tutorial["step"]), 0, "tutorial starts at step 0")
	GameState.advance_tutorial("merge")
	_check_eq(int(GameState.tutorial["step"]), 0, "out-of-order tutorial events are ignored")
	GameState.advance_tutorial("collect")
	_check_eq(int(GameState.tutorial["step"]), 1, "matching tutorial event advances the step")
	GameState.finish_tutorial()
	_check(not GameState.tutorial_active(), "tutorial can be finished explicitly")


func _test_collect_and_nowhere_to_put_it() -> void:
	GameState.new_game()
	_clear_board()
	GameState.generators["collector"]["pending"] = 3
	var collected: Dictionary = GameState.collect_production()
	_check_eq(int(collected["collected"]), 3, "collect spawns all pending scrap")
	_check_eq(GameState.item_count("broken_circuit"), 3, "collected scrap lands on the board")
	_check_eq(int(GameState.generators["collector"]["pending"]), 0, "collected scrap leaves the buffer")

	# Fill every slot so the board has no room left.
	for index in GameState.board_size():
		GameState.board[index] = "broken_circuit"
	GameState.generators["collector"]["pending"] = 2
	var full: Dictionary = GameState.collect_production()
	_check_eq(int(full["collected"]), 0, "a full board blocks collection")
	_check_eq(int(full["blocked"]), 2, "blocked scrap is reported and kept")
	_check_eq(int(GameState.generators["collector"]["pending"]), 2, "blocked scrap stays buffered")

	# Free space is filled up to the remaining room only.
	GameState.board[GameState.board_size() - 1] = null
	GameState.generators["collector"]["pending"] = 5
	var partial: Dictionary = GameState.collect_production()
	_check_eq(int(partial["collected"]), 1, "collection respects the last free slot")
	_check_eq(int(partial["blocked"]), 4, "unspawned scrap stays in the buffer")


func _test_save_round_trip() -> void:
	GameState.new_game()
	GameState.credits = 4321
	GameState.board_rows = 7
	GameState.expansions_bought = 1
	GameState._resize_board()
	GameState.board[0] = "warp_drive"
	GameState.parts["engine"] = 3
	GameState.stats["merges"] = 17
	GameState.tutorial["step"] = 2

	var written: bool = GameState.save_now(true)
	_check(written, "save writes to disk")
	_check(FileAccess.file_exists(SaveManager.save_path), "save file exists after writing")

	var loaded: Dictionary = SaveManager.load_save()
	_check(not loaded.is_empty(), "saved data loads back")
	_check_eq(int(loaded.get("version", 0)), Catalog.SAVE_VERSION, "save carries the current version")
	_check(float(loaded.get("saved_at", 0.0)) > 0.0, "save records a timestamp")

	GameState.new_game()
	_check_eq(GameState.credits, Catalog.STARTING_CREDITS, "new game clears earlier progress")

	GameState.apply_save_dict(loaded)
	_check_eq(GameState.credits, 4321, "credits survive a save round trip")
	_check_eq(str(GameState.board[0]), "warp_drive", "board contents survive a save round trip")
	_check_eq(GameState.board_size(), 35, "board size survives a save round trip")
	_check_eq(GameState.part_level("engine"), 3, "ship components survive a save round trip")
	_check_eq(int(GameState.stats["merges"]), 17, "statistics survive a save round trip")
	_check_eq(int(GameState.tutorial["step"]), 2, "tutorial progress survives a save round trip")


func _test_save_recovery() -> void:
	SaveManager.delete_save()
	_cleanup_quarantine_files()

	var file: FileAccess = FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	file.store_string("{ this is not valid json")
	file.close()
	var corrupt: Dictionary = SaveManager.load_save()
	_check(corrupt.is_empty(), "corrupt saves are not loaded")
	_check(SaveManager.last_error.contains("could not be read"), "corrupt save reports a recovery message")
	_check(not FileAccess.file_exists(SaveManager.save_path), "corrupt save is moved out of the way")
	_check(_count_quarantine_files() == 1, "corrupt save is preserved for inspection")

	var newer: Dictionary = {"version": 999, "board": [], "parts": {}}
	file = FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(newer))
	file.close()
	var rejected: Dictionary = SaveManager.load_save()
	_check(rejected.is_empty(), "saves from a newer version are rejected")
	_check(_count_quarantine_files() == 2, "newer-version save is preserved rather than deleted")

	# A valid save must still be writable and readable after both failures.
	GameState.new_game()
	GameState.credits = 777
	_check(GameState.save_now(true), "saving still works after rejected saves")
	var reloaded: Dictionary = SaveManager.load_save()
	_check_eq(int(reloaded.get("credits", 0)), 777, "recovered save loads with correct credits")
	SaveManager.delete_save()
	_cleanup_quarantine_files()


func _test_active_expedition_persistence() -> void:
	GameState.new_game()
	_clear_board()
	GameState.parts["engine"] = 1
	var started: Dictionary = GameState.start_expedition("junkyard")
	_check(bool(started.get("ok", false)), "expedition starts before the reload test")

	var planet_id: String = str(GameState.expedition.get("planet_id", ""))
	var end_unix: float = float(GameState.expedition.get("end_unix", 0.0))
	_check(GameState.save_now(true), "expedition state saves while the ship is away")
	var loaded: Dictionary = SaveManager.load_save()

	GameState.new_game()
	_check(GameState.expedition.is_empty(), "starting over clears the active expedition")
	GameState.apply_save_dict(loaded)
	_check_eq(str(GameState.expedition.get("planet_id", "")), planet_id, "active expedition survives a reload")
	_check_eq(float(GameState.expedition.get("end_unix", 0.0)), end_unix, "expedition arrival time survives a reload")

	GameState.expedition["end_unix"] = Time.get_unix_time_from_system() - 1.0
	_check(bool(GameState.claim_expedition().get("ok", false)), "a restored expedition can still be claimed")
	_check(GameState.expedition.is_empty(), "claiming the restored expedition clears it")
	SaveManager.delete_save()


func _test_offline_production() -> void:
	# 30 seconds offline at one item per 12 seconds -> 2 items.
	var data: Dictionary = _offline_save(30.0)
	GameState.apply_save_dict(data)
	_check_eq(int(GameState.generators["collector"]["pending"]), 2, "offline production accrues at the machine rate")

	# Far beyond the cap: pending is clamped to the machine capacity.
	data = _offline_save(100000.0)
	GameState.apply_save_dict(data)
	var capacity: int = EconomyRules.generator_capacity(Catalog.generator_def("collector"), 1)
	_check_eq(int(GameState.generators["collector"]["pending"]), capacity, "offline production respects the capacity cap")
	_check_eq(float(GameState.generators["collector"]["progress"]), 0.0, "capped offline progress does not overflow")

	# Absurd timestamps must not produce negative or runaway values.
	data = _offline_save(-999.0)
	GameState.apply_save_dict(data)
	_check(int(GameState.generators["collector"]["pending"]) >= 0, "future timestamps never remove scrap")
	_check(GameState.credits >= 0, "invalid timestamps cannot produce negative credits")


func _test_optional_services() -> void:
	AudioManager.apply_settings(0.0, 0.0, false)
	AudioManager.play("merge")
	_check(true, "playing audio while muted is safe")
	AudioManager.apply_settings(0.5, 0.5, true)

	var provider := preload("res://scripts/monetization/purchase_provider.gd").new()
	var purchase: Dictionary = provider.purchase("cosmetic_skin", self)
	_check(not bool(purchase.get("ok", false)), "purchases stay disabled without a store integration")
	_check(not provider.is_configured(), "purchase provider reports itself as unconfigured")


func _test_monetization() -> void:
	_check(Monetization.ads_available(), "mock rewarded ads are available")
	_check(Monetization.ads_are_mock(), "default ad provider is flagged as simulated")
	var granted: bool = await Monetization.watch_rewarded_ad("test")
	_check(granted, "mock rewarded ad grants its reward")
	_check(not Monetization.is_busy(), "ad service leaves its busy state")


# --- Helpers ----------------------------------------------------------------
func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS  %s" % message)
	else:
		_failed += 1
		print("FAIL  %s" % message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s [expected %s, got %s]" % [message, str(expected), str(actual)])


func _clear_board() -> void:
	for index in GameState.board.size():
		GameState.board[index] = null


func _count_items() -> int:
	var total: int = 0
	for cell in GameState.board:
		if cell != null:
			total += 1
	return total


func _offline_save(elapsed_seconds: float) -> Dictionary:
	var data: Dictionary = GameState.to_save_dict()
	data["saved_at"] = Time.get_unix_time_from_system() - elapsed_seconds
	data["generators"] = {
		"collector": {"level": 1, "progress": 0.0, "pending": 0},
		"sorter": {"level": 0, "progress": 0.0, "pending": 0},
		"arm": {"level": 0, "progress": 0.0, "pending": 0},
	}
	data["board"] = _empty_board(30)
	return data


func _empty_board(size: int) -> Array:
	var result: Array = []
	for _i in size:
		result.append(null)
	return result


func _count_quarantine_files() -> int:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return 0
	var count: int = 0
	for file_name in dir.get_files():
		if file_name.begins_with(TEST_SAVE.get_file() + ".corrupt-"):
			count += 1
	return count


func _cleanup_quarantine_files() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.begins_with(TEST_SAVE.get_file() + ".corrupt-"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + file_name))
