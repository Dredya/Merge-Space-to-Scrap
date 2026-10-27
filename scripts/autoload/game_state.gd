extends Node
## Authoritative game state for Scrap to Space.
##
## Owns credits, the merge board, production, orders, ship components,
## destinations and expeditions. Views listen to the signals below and render;
## they never mutate gameplay data directly.

const Catalog = preload("res://scripts/data/game_catalog.gd")
const MergeRules = preload("res://scripts/logic/merge_rules.gd")
const EconomyRules = preload("res://scripts/logic/economy_rules.gd")
const ExpeditionRules = preload("res://scripts/logic/expedition_rules.gd")

signal credits_changed(credits: int)
signal board_changed
signal production_changed
signal selection_changed
signal generators_changed
signal orders_changed
signal ship_changed
signal planets_changed
signal expedition_changed
signal ad_changed
signal tutorial_changed
signal settings_changed
signal notice(text: String, kind: String)
signal state_loaded
signal state_reset

var credits: int = 0
var board: Array = []
var board_rows: int = Catalog.BOARD_START_ROWS
var expansions_bought: int = 0
var generators: Dictionary = {}
var orders: Array = []
var parts: Dictionary = {}
var unlocked_planets: Array = []
var expedition: Dictionary = {}
var next_expedition_unix: float = 0.0
var settings: Dictionary = {"music": 0.55, "sfx": 0.8, "haptics": true, "auto_deliver": false}
var tutorial: Dictionary = {"step": 0, "done": false}
var stats: Dictionary = {
	"merges": 0,
	"items_sold": 0,
	"credits_earned": 0,
	"orders_completed": 0,
	"expeditions": 0,
	"best_tier": 1,
}
var boost_until: float = 0.0
var next_rewarded_ad_unix: float = 0.0
var _ad_paused_remaining: float = -1.0
var selected_index: int = -1

var _rng := RandomNumberGenerator.new()
var _save_cooldown: float = 0.0
var _suppress_save: bool = false
var _pending_notice: String = ""
var _auto_deliver_cooldown: float = 0.0
var _scrap_spawn_timer: float = 10.0
var _scrap_spawn_interval: float = 10.0
var _auto_collect_blocked: bool = false
var rebirth_level: int = 0
var lifetime_credits_earned: int = 0


func _ready() -> void:
	_rng.randomize()
	_load_or_start()
	set_process(true)


func _process(delta: float) -> void:
	_auto_collect()
	_tick_scrap_spawn(delta)
	if _tick_production(delta):
		production_changed.emit()

	if _save_cooldown > 0.0:
		_save_cooldown -= delta
		if _save_cooldown <= 0.0:
			save_now()

	if bool(settings.get("auto_deliver", false)) and not _suppress_save:
		_auto_deliver_cooldown -= delta
		if _auto_deliver_cooldown <= 0.0:
			_auto_deliver_cooldown = 0.5
			auto_deliver_ready_orders()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if next_rewarded_ad_unix > 0.0:
			_ad_paused_remaining = maxf(0.0, next_rewarded_ad_unix - Time.get_unix_time_from_system())
		save_now()
	elif what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if _ad_paused_remaining >= 0.0:
			next_rewarded_ad_unix = Time.get_unix_time_from_system() + _ad_paused_remaining
			_ad_paused_remaining = -1.0
			ad_changed.emit()


# --- Lifecycle --------------------------------------------------------------
func _load_or_start() -> void:
	var saver := _save_manager()
	if saver == null:
		new_game()
		return

	var data: Dictionary = saver.load_save()
	if data.is_empty():
		var load_error: String = saver.last_error
		new_game()
		if load_error != "":
			notice.emit(load_error, "warn")
		return

	apply_save_dict(data)


func new_game() -> void:
	_suppress_save = true
	credits = int(round(float(Catalog.STARTING_CREDITS) * (1.0 + 0.5 * float(rebirth_level))))
	board_rows = clampi(Catalog.BOARD_START_ROWS + rebirth_level, Catalog.BOARD_START_ROWS, Catalog.MAX_BOARD_ROWS)
	expansions_bought = board_rows - Catalog.BOARD_START_ROWS
	selected_index = -1
	boost_until = 0.0
	_scrap_spawn_timer = _scrap_spawn_interval
	expedition = {}
	next_expedition_unix = 0.0
	next_rewarded_ad_unix = 0.0
	orders = []

	generators = {}
	for definition in Catalog.GENERATOR_DEFS:
		var generator_id: String = str(definition["id"])
		# The collector starts with a little scrap ready so the very first
		# COLLECT tap (the first tutorial step) does something immediately.
		generators[generator_id] = {
			"level": 1 if generator_id == "collector" else 0,
			"progress": 0.0,
			"pending": 2 if generator_id == "collector" else 0,
		}

	parts = {}
	for definition in Catalog.SHIP_PART_DEFS:
		parts[str(definition["id"])] = 1

	tutorial = {"step": 0, "done": false}
	stats = {
		"merges": 0,
		"items_sold": 0,
		"credits_earned": 0,
		"orders_completed": 0,
		"expeditions": 0,
		"best_tier": 1,
	}

	_resize_board()
	_seed_starter_board()
	unlocked_planets = compute_unlocked_planets()

	for _i in Catalog.ORDER_SLOTS:
		orders.append(_generate_order())

	_suppress_save = false
	_apply_audio_settings()
	_emit_all()
	state_reset.emit()
	queue_save()


func reset_progress() -> void:
	var saver := _save_manager()
	if saver != null:
		saver.delete_save()
	var kept_settings: Dictionary = settings.duplicate(true)
	new_game()
	settings = kept_settings
	_apply_audio_settings()
	settings_changed.emit()
	save_now(true)


# --- Persistence ------------------------------------------------------------
func to_save_dict() -> Dictionary:
	return {
		"version": Catalog.SAVE_VERSION,
		"credits": credits,
		"board": board.duplicate(),
		"board_rows": board_rows,
		"expansions_bought": expansions_bought,
		"generators": generators.duplicate(true),
		"orders": orders.duplicate(true),
		"parts": parts.duplicate(true),
		"unlocked_planets": unlocked_planets.duplicate(),
		"expedition": expedition.duplicate(true),
		"next_expedition_unix": next_expedition_unix,
		"settings": settings.duplicate(true),
		"tutorial": tutorial.duplicate(true),
		"stats": stats.duplicate(true),
		"boost_until": boost_until,
		"next_rewarded_ad_unix": next_rewarded_ad_unix,
		"rebirth_level": rebirth_level,
		"lifetime_credits_earned": lifetime_credits_earned,
		"saved_at": Time.get_unix_time_from_system(),
	}


func apply_save_dict(data: Dictionary) -> void:
	_suppress_save = true

	credits = maxi(int(data.get("credits", Catalog.STARTING_CREDITS)), 0)
	board_rows = clampi(
		int(data.get("board_rows", Catalog.BOARD_START_ROWS)),
		Catalog.BOARD_START_ROWS,
		Catalog.MAX_BOARD_ROWS
	)
	expansions_bought = clampi(
		int(data.get("expansions_bought", board_rows - Catalog.BOARD_START_ROWS)),
		0,
		Catalog.BOARD_EXPANSIONS.size()
	)

	var saved_board: Array = data.get("board", []) if data.get("board", []) is Array else []
	board = []
	var total_slots: int = board_rows * Catalog.BOARD_COLUMNS
	for index in total_slots:
		var raw: Variant = saved_board[index] if index < saved_board.size() else null
		if raw is String and Catalog.has_item(raw):
			board.append(raw)
		else:
			board.append(null)

	var saved_generators: Dictionary = data.get("generators", {}) if data.get("generators", {}) is Dictionary else {}
	generators = {}
	for definition in Catalog.GENERATOR_DEFS:
		var generator_id: String = str(definition["id"])
		var saved: Dictionary = saved_generators.get(generator_id, {}) if saved_generators.get(generator_id, {}) is Dictionary else {}
		var default_level: int = 1 if generator_id == "collector" else 0
		var level: int = clampi(int(saved.get("level", default_level)), 0, Catalog.MAX_GENERATOR_LEVEL)
		var reference_level: int = maxi(level, 1)
		var interval: float = EconomyRules.generator_interval(definition, reference_level) / rebirth_production_multiplier()
		var capacity: int = EconomyRules.generator_capacity(definition, reference_level)
		generators[generator_id] = {
			"level": level,
			"progress": clampf(float(saved.get("progress", 0.0)), 0.0, maxf(interval, 0.001)),
			"pending": clampi(int(saved.get("pending", 0)), 0, capacity),
		}

	var saved_parts: Dictionary = data.get("parts", {}) if data.get("parts", {}) is Dictionary else {}
	parts = {}
	for definition in Catalog.SHIP_PART_DEFS:
		var part_id: String = str(definition["id"])
		parts[part_id] = clampi(int(saved_parts.get(part_id, 1)), 1, Catalog.PART_MAX_LEVEL)

	orders = []
	var saved_orders: Array = data.get("orders", []) if data.get("orders", []) is Array else []
	for index in Catalog.ORDER_SLOTS:
		var order: Dictionary = {}
		if index < saved_orders.size() and saved_orders[index] is Dictionary:
			order = _sanitize_order(saved_orders[index])
		if order.is_empty():
			order = _generate_order()
		orders.append(order)

	var saved_tutorial: Dictionary = data.get("tutorial", {}) if data.get("tutorial", {}) is Dictionary else {}
	tutorial = {
		"step": clampi(int(saved_tutorial.get("step", 0)), 0, Catalog.TUTORIAL_STEPS.size()),
		"done": bool(saved_tutorial.get("done", false)),
	}

	var saved_stats: Dictionary = data.get("stats", {}) if data.get("stats", {}) is Dictionary else {}
	for key in stats.keys():
		stats[key] = maxi(int(saved_stats.get(key, stats[key])), 0)
	stats["best_tier"] = clampi(int(stats["best_tier"]), 1, 8)

	var saved_settings: Dictionary = data.get("settings", {}) if data.get("settings", {}) is Dictionary else {}
	settings = {
		"music": clampf(float(saved_settings.get("music", 0.55)), 0.0, 1.0),
		"sfx": clampf(float(saved_settings.get("sfx", 0.8)), 0.0, 1.0),
		"haptics": bool(saved_settings.get("haptics", true)),
		"auto_deliver": bool(saved_settings.get("auto_deliver", false)),
	}

	expedition = {}
	var saved_expedition: Variant = data.get("expedition", {})
	if saved_expedition is Dictionary and not (saved_expedition as Dictionary).is_empty():
		var planet: Dictionary = Catalog.planet(str(saved_expedition.get("planet_id", "")))
		if not planet.is_empty():
			expedition = {
				"planet_id": str(planet["id"]),
				"planet_name": str(planet["name"]),
				"start_unix": float(saved_expedition.get("start_unix", 0.0)),
				"end_unix": float(saved_expedition.get("end_unix", 0.0)),
				"rewards": _sanitize_rewards(saved_expedition.get("rewards", {})),
			}

	boost_until = clampf(
		float(data.get("boost_until", 0.0)),
		0.0,
		Time.get_unix_time_from_system() + Catalog.PRODUCTION_BOOST_SECONDS
	)
	next_rewarded_ad_unix = maxf(0.0, float(data.get("next_rewarded_ad_unix", 0.0)))
	next_expedition_unix = maxf(0.0, float(data.get("next_expedition_unix", 0.0)))
	rebirth_level = clampi(int(data.get("rebirth_level", 0)), 0, Catalog.rebirth_count())
	lifetime_credits_earned = maxi(int(data.get("lifetime_credits_earned", 0)), 0)

	unlocked_planets = compute_unlocked_planets()

	var saved_at: float = float(data.get("saved_at", Time.get_unix_time_from_system()))
	var elapsed: float = clampf(Time.get_unix_time_from_system() - saved_at, 0.0, Catalog.OFFLINE_CAP_SECONDS)
	var produced: int = 0
	if elapsed >= 1.0:
		produced = _apply_offline(elapsed)

	_suppress_save = false
	_apply_audio_settings()
	_emit_all()
	state_loaded.emit()

	if produced > 0:
		notice.emit("Welcome back! Your machines salvaged %d item(s) while you were away." % produced, "good")
	elif elapsed >= 60.0:
		notice.emit("Welcome back, captain.", "info")


func save_now(force: bool = false) -> bool:
	var saver := _save_manager()
	if saver == null:
		return false
	if not force and not saver.autosave_enabled:
		return false
	_save_cooldown = 0.0
	var ok: bool = saver.write_save(to_save_dict())
	if not ok and saver.last_error != "":
		notice.emit(saver.last_error, "warn")
	return ok


func queue_save() -> void:
	if _suppress_save:
		return
	var saver := _save_manager()
	if saver == null or not saver.autosave_enabled:
		return
	_save_cooldown = 0.5


# --- Production -------------------------------------------------------------
func get_production_multiplier() -> float:
	if Time.get_unix_time_from_system() < boost_until:
		return Catalog.PRODUCTION_BOOST_MULTIPLIER
	return 1.0


func boost_seconds_remaining() -> float:
	return maxf(0.0, boost_until - Time.get_unix_time_from_system())


func ad_available() -> bool:
	return ad_seconds_remaining() <= 0.0


func ad_seconds_remaining() -> float:
	return maxf(0.0, next_rewarded_ad_unix - Time.get_unix_time_from_system())


func consume_ad_cooldown() -> void:
	next_rewarded_ad_unix = Time.get_unix_time_from_system() + 300.0
	ad_changed.emit()
	queue_save()


func apply_production_boost(seconds: float = Catalog.PRODUCTION_BOOST_SECONDS) -> void:
	boost_until = maxf(boost_until, Time.get_unix_time_from_system()) + seconds
	production_changed.emit()
	notice.emit("Salvage overdrive active for %d min." % int(seconds / 60.0), "good")
	queue_save()


func get_production_snapshot() -> Array:
	var multiplier: float = get_production_multiplier()
	var snapshot: Array = []
	for definition in Catalog.GENERATOR_DEFS:
		var generator_id: String = str(definition["id"])
		var state: Dictionary = generators.get(generator_id, {"level": 0, "progress": 0.0, "pending": 0})
		var level: int = int(state.get("level", 0))
		snapshot.append({
			"id": generator_id,
			"name": str(definition["name"]),
			"short": str(definition["short"]),
			"item": str(definition["item"]),
			"level": level,
			"pending": int(state.get("pending", 0)),
			"capacity": EconomyRules.generator_capacity(definition, maxi(level, 1)),
			"interval": EconomyRules.generator_interval(definition, maxi(level, 1)) / rebirth_production_multiplier(),
			"rate": EconomyRules.generator_rate_per_minute(definition, level, multiplier),
			"unlocked": level > 0,
		})
	return snapshot


func _tick_scrap_spawn(delta: float) -> void:
	var saver := _save_manager()
	if saver == null or not saver.autosave_enabled:
		return
	if free_slot_count() <= 0:
		_scrap_spawn_timer = _scrap_spawn_interval
		return
	# After a merge frees a slot, do not let the random scrap timer instantly
	# refill it; wait until the player has made real room.
	if _auto_collect_blocked and free_slot_count() < 2:
		_scrap_spawn_timer = _scrap_spawn_interval
		return
	_scrap_spawn_timer -= delta
	if _scrap_spawn_timer <= 0.0:
		_spawn_random_scrap()
		_scrap_spawn_timer = _scrap_spawn_interval


func _spawn_random_scrap() -> void:
	var families: Array = ["circuit"]
	if int((generators.get("sorter", {}) as Dictionary).get("level", 0)) >= 1:
		families.append("alloy")
	if int((generators.get("arm", {}) as Dictionary).get("level", 0)) >= 1:
		families.append("quantum")
	var family_id: String = str(families[_rng.randi_range(0, families.size() - 1)])
	var tier_ids: Array = Catalog.tier_ids(family_id)
	if tier_ids.is_empty():
		return
	var item_id: String = str(tier_ids[0])
	if _spawn_item(item_id):
		board_changed.emit()
		queue_save()


func scrap_spawn_seconds_remaining() -> float:
	return maxf(0.0, _scrap_spawn_timer)


func _auto_collect() -> void:
	var saver := _save_manager()
	if saver == null or not saver.autosave_enabled:
		return
	# After a merge frees a slot, keep that slot free until the player has made
	# real room (2+ free slots) or explicitly collects.
	if _auto_collect_blocked:
		if free_slot_count() >= 2:
			_auto_collect_blocked = false
		else:
			return
	var collected: int = 0
	for definition in Catalog.GENERATOR_DEFS:
		var generator_id: String = str(definition["id"])
		var state: Dictionary = generators.get(generator_id, {})
		if state.is_empty():
			continue
		var pending: int = int(state.get("pending", 0))
		if pending <= 0:
			continue
		var item_id: String = str(definition["item"])
		var spawned: int = 0
		for _i in pending:
			if free_slot_count() <= 0:
				break
			if _spawn_item(item_id):
				spawned += 1
		state["pending"] = pending - spawned
		collected += spawned
	if collected > 0:
		board_changed.emit()
		production_changed.emit()
		queue_save()


func collect_production() -> Dictionary:
	_auto_collect_blocked = false
	var collected: int = 0
	var blocked: int = 0
	for definition in Catalog.GENERATOR_DEFS:
		var generator_id: String = str(definition["id"])
		var state: Dictionary = generators.get(generator_id, {})
		if state.is_empty():
			continue
		var pending: int = int(state.get("pending", 0))
		if pending <= 0:
			continue
		var free_slots: int = free_slot_count()
		var spawned: int = 0
		for _i in mini(pending, free_slots):
			if _spawn_item(str(definition["item"])):
				spawned += 1
		state["pending"] = pending - spawned
		collected += spawned
		blocked += pending - spawned

	if collected > 0:
		advance_tutorial("collect")
		board_changed.emit()
		production_changed.emit()
		queue_save()
	elif blocked > 0:
		notice.emit("Board is full - sell or merge something first.", "warn")

	return {"collected": collected, "blocked": blocked}


func _tick_production(delta: float) -> bool:
	var multiplier: float = get_production_multiplier()
	var changed: bool = false
	for definition in Catalog.GENERATOR_DEFS:
		var generator_id: String = str(definition["id"])
		var state: Dictionary = generators.get(generator_id, {})
		if state.is_empty():
			continue
		var level: int = int(state.get("level", 0))
		if level <= 0:
			continue
		if free_slot_count() <= 0:
			state["progress"] = 0.0
			continue
		var interval: float = EconomyRules.generator_interval(definition, level) / rebirth_production_multiplier()
		var capacity: int = EconomyRules.generator_capacity(definition, level)
		var pending: int = int(state.get("pending", 0))
		if pending >= capacity:
			if float(state.get("progress", 0.0)) != 0.0:
				state["progress"] = 0.0
			continue
		var progress: float = float(state.get("progress", 0.0)) + delta * multiplier
		while progress >= interval and pending < capacity:
			progress -= interval
			pending += 1
			changed = true
		if pending >= capacity:
			progress = 0.0
		state["progress"] = progress
		state["pending"] = pending
	return changed


func _apply_offline(elapsed_seconds: float) -> int:
	var produced: int = 0
	for definition in Catalog.GENERATOR_DEFS:
		var generator_id: String = str(definition["id"])
		var state: Dictionary = generators.get(generator_id, {})
		if state.is_empty():
			continue
		var level: int = int(state.get("level", 0))
		if level <= 0:
			continue
		var interval: float = EconomyRules.generator_interval(definition, level) / rebirth_production_multiplier()
		var capacity: int = EconomyRules.generator_capacity(definition, level)
		var total: float = float(state.get("progress", 0.0)) + elapsed_seconds
		var cycles: int = int(floor(total / interval))
		var pending: int = int(state.get("pending", 0))
		var room: int = maxi(capacity - pending, 0)
		var gain: int = mini(cycles, room)
		state["pending"] = pending + gain
		state["progress"] = total - float(cycles) * interval
		if int(state["pending"]) >= capacity:
			state["progress"] = 0.0
		produced += gain
	return produced


# --- Merge board ------------------------------------------------------------
func board_size() -> int:
	return board.size()


func item_at(index: int) -> Variant:
	if index < 0 or index >= board.size():
		return null
	return board[index]


func selected_item() -> Variant:
	return item_at(selected_index)


func select_item(index: int) -> void:
	if index < 0 or index >= board.size():
		return
	selected_index = index if board[index] != null else -1
	board_changed.emit()


func clear_selection() -> void:
	if selected_index == -1:
		return
	selected_index = -1
	board_changed.emit()


func free_slot_count() -> int:
	var count: int = 0
	for cell in board:
		if cell == null:
			count += 1
	return count


func item_count(item_id: String) -> int:
	var count: int = 0
	for cell in board:
		if cell == item_id:
			count += 1
	return count


## Applies a drag from one slot to another. Returns
## {ok, action: "move"|"merge", index, merged_into, message}.
func attempt_drop(from_index: int, to_index: int) -> Dictionary:
	if from_index < 0 or from_index >= board.size() or to_index < 0 or to_index >= board.size():
		return {"ok": false, "message": "Invalid slot."}
	if from_index == to_index:
		return {"ok": false, "message": ""}

	var source: Variant = board[from_index]
	if source == null:
		return {"ok": false, "message": ""}

	var destination: Variant = board[to_index]
	if destination == null:
		board[to_index] = source
		board[from_index] = null
		selected_index = -1
		board_changed.emit()
		queue_save()
		return {"ok": true, "action": "move", "index": to_index}

	if not MergeRules.can_merge(str(source), str(destination)):
		return {"ok": false, "message": MergeRules.failure_reason(str(source), str(destination))}

	var merged_into: String = MergeRules.merge_target(str(source), str(destination))
	board[to_index] = merged_into
	board[from_index] = null
	selected_index = -1
	stats["merges"] = int(stats["merges"]) + 1
	stats["best_tier"] = maxi(int(stats["best_tier"]), Catalog.item_tier(merged_into))
	advance_tutorial("merge")
	# Keep the slot freed by this merge free instead of letting auto-collection
	# instantly refill it.
	_auto_collect_blocked = true
	board_changed.emit()
	queue_save()
	return {"ok": true, "action": "merge", "index": to_index, "merged_into": merged_into}


func sell_selected() -> Dictionary:
	if selected_index < 0 or selected_index >= board.size():
		return {"ok": false, "message": "Select an item first."}
	var item_id: Variant = board[selected_index]
	if item_id == null:
		return {"ok": false, "message": "Select an item first."}

	var value: int = int(round(float(Catalog.sell_value(str(item_id))) * rebirth_sell_multiplier()))
	board[selected_index] = null
	selected_index = -1
	_add_credits(value)
	stats["items_sold"] = int(stats["items_sold"]) + 1
	advance_tutorial("sell")
	board_changed.emit()
	queue_save()
	return {"ok": true, "credits": value}


func sell_item_at(index: int) -> Dictionary:
	selected_index = index
	return sell_selected()


func _spawn_item(item_id: String) -> bool:
	for index in board.size():
		if board[index] == null:
			board[index] = item_id
			return true
	return false


func rebirth_production_multiplier() -> float:
	return 1.0 + 0.08 * float(rebirth_level)


func rebirth_sell_multiplier() -> float:
	return 1.0 + 0.10 * float(rebirth_level)


func rebirth_expedition_multiplier() -> float:
	return 1.0 + 0.10 * float(rebirth_level)


func can_rebirth() -> bool:
	if rebirth_level >= Catalog.rebirth_count():
		return false
	var definition: Dictionary = Catalog.next_rebirth_def(rebirth_level)
	if definition.is_empty():
		return false
	return int(stats.get("credits_earned", 0)) >= int(definition.get("credits_required", 0))


func rebirth() -> Dictionary:
	if not can_rebirth():
		var definition: Dictionary = Catalog.next_rebirth_def(rebirth_level)
		return {"ok": false, "message": "Need %d more credits earned." % maxi(int(definition.get("credits_required", 0)) - int(stats.get("credits_earned", 0)), 0)}
	var definition: Dictionary = Catalog.next_rebirth_def(rebirth_level)
	rebirth_level += 1
	# Reset the run while preserving permanent rebirth progress.
	var kept_settings: Dictionary = settings.duplicate(true)
	var kept_rebirth: int = rebirth_level
	var kept_lifetime: int = lifetime_credits_earned
	new_game()
	rebirth_level = kept_rebirth
	lifetime_credits_earned = kept_lifetime
	settings = kept_settings
	_apply_audio_settings()
	settings_changed.emit()
	push_notice("Rebirth %d complete. Bonuses applied." % rebirth_level, "good")
	queue_save()
	return {"ok": true, "level": rebirth_level, "name": str(definition.get("name", ""))}


func _add_credits(amount: int) -> void:
	if amount == 0:
		return
	credits = maxi(credits + amount, 0)
	if amount > 0:
		stats["credits_earned"] = int(stats["credits_earned"]) + amount
		lifetime_credits_earned += amount
	credits_changed.emit(credits)


func add_items(items: Dictionary) -> Dictionary:
	var added: int = 0
	var overflow_value: int = 0
	for item_id in items:
		var quantity: int = int(items[item_id])
		for _i in quantity:
			if _spawn_item(str(item_id)):
				added += 1
			else:
				overflow_value += int(ceil(float(Catalog.sell_value(str(item_id)) * 0.5) * rebirth_sell_multiplier()))
	if overflow_value > 0:
		_add_credits(overflow_value)
	if added > 0:
		board_changed.emit()
	return {"added": added, "overflow_credits": overflow_value}


func _has_items(items: Dictionary) -> bool:
	for item_id in items:
		if item_count(str(item_id)) < int(items[item_id]):
			return false
	return true


func _consume_items(items: Dictionary) -> bool:
	if not _has_items(items):
		return false
	for item_id in items:
		var remaining: int = int(items[item_id])
		for index in board.size():
			if remaining <= 0:
				break
			if board[index] == str(item_id):
				board[index] = null
				remaining -= 1
	return true


func _resize_board() -> void:
	var total: int = board_rows * Catalog.BOARD_COLUMNS
	while board.size() < total:
		board.append(null)
	if board.size() > total:
		board.resize(total)
	selected_index = -1


func _seed_starter_board() -> void:
	var starters: Array = [["broken_circuit", 8], ["repaired_circuit", 2]]
	var index: int = 0
	for entry in starters:
		for _i in int(entry[1]):
			if index < board.size():
				board[index] = str(entry[0])
				index += 1


# --- Generators & board expansion -------------------------------------------
func generator_levels() -> Dictionary:
	var levels: Dictionary = {}
	for generator_id in generators.keys():
		levels[generator_id] = int((generators[generator_id] as Dictionary).get("level", 0))
	return levels


func next_generator_cost(generator_id: String) -> int:
	var definition: Dictionary = Catalog.generator_def(generator_id)
	var state: Dictionary = generators.get(generator_id, {})
	return EconomyRules.generator_upgrade_cost(definition, int(state.get("level", 0)))


func upgrade_generator(generator_id: String) -> Dictionary:
	var definition: Dictionary = Catalog.generator_def(generator_id)
	if definition.is_empty():
		return {"ok": false, "message": "Unknown machine."}

	var state: Dictionary = generators.get(generator_id, {})
	var level: int = int(state.get("level", 0))
	if level >= Catalog.MAX_GENERATOR_LEVEL:
		return {"ok": false, "message": "Already at maximum level."}
	if not EconomyRules.generator_requirements_met(definition, generator_levels()):
		return {"ok": false, "message": "Requires %s." % EconomyRules.generator_requirement_text(definition)}

	var ship_requires: Dictionary = definition.get("ship_requires", {})
	for part_id in ship_requires:
		if part_level(str(part_id)) < int(ship_requires[part_id]):
			var part_name: String = str(Catalog.ship_part_def(str(part_id)).get("name", part_id))
			return {"ok": false, "message": "Requires %s Lv %d." % [part_name, int(ship_requires[part_id])]}

	var cost: int = EconomyRules.generator_upgrade_cost(definition, level)
	if credits < cost:
		return {"ok": false, "message": "Need %d more credits." % (cost - credits)}

	_add_credits(-cost)
	state["level"] = level + 1
	if level == 0:
		notice.emit("%s installed." % str(definition["name"]), "good")
	advance_tutorial("upgrade")
	generators_changed.emit()
	production_changed.emit()
	queue_save()
	return {"ok": true, "cost": cost, "level": level + 1}


func next_expansion_cost() -> int:
	return EconomyRules.expansion_cost(expansions_bought)


func can_expand() -> bool:
	return expansions_bought < Catalog.BOARD_EXPANSIONS.size()


func buy_expansion() -> Dictionary:
	if not can_expand():
		return {"ok": false, "message": "Board is fully expanded."}
	var cost: int = EconomyRules.expansion_cost(expansions_bought)
	if credits < cost:
		return {"ok": false, "message": "Need %d more credits." % (cost - credits)}
	_add_credits(-cost)
	expansions_bought += 1
	board_rows = EconomyRules.expansion_rows(expansions_bought - 1)
	_resize_board()
	notice.emit("Board expanded to %d slots." % board.size(), "good")
	board_changed.emit()
	generators_changed.emit()
	queue_save()
	return {"ok": true, "cost": cost, "slots": board.size()}


# --- Orders -----------------------------------------------------------------
func _generate_order() -> Dictionary:
	var families: Array = ["circuit"]
	if int((generators.get("sorter", {}) as Dictionary).get("level", 0)) >= 1:
		families.append("alloy")
	if int((generators.get("arm", {}) as Dictionary).get("level", 0)) >= 1:
		families.append("quantum")

	var family_id: String = str(families[_rng.randi_range(0, families.size() - 1)])
	var tier_ids: Array = Catalog.tier_ids(family_id)
	if tier_ids.is_empty():
		return {}

	# Pick an order tier. Higher tiers need more progress to be fair.
	var order_tier: int = _rng.randi_range(1, 3)
	var max_tier_index: int = tier_ids.size()
	var min_item_tier: int = 1
	var max_item_tier: int = mini(2, max_tier_index)
	if order_tier == 2:
		min_item_tier = mini(2, max_tier_index)
		max_item_tier = mini(3, max_tier_index)
	elif order_tier == 3:
		min_item_tier = mini(3, max_tier_index)
		max_item_tier = max_tier_index
	if min_item_tier > max_item_tier:
		min_item_tier = 1
		max_item_tier = mini(2, max_tier_index)

	var item_tier: int = _rng.randi_range(min_item_tier, max_item_tier)
	var item_id: String = str(tier_ids[item_tier - 1])

	var quantity: int = 1
	if order_tier >= 2:
		quantity = _rng.randi_range(1, 2)
	if order_tier >= 3:
		quantity = 2

	var reward_mult: float = 1.0
	if order_tier == 2:
		reward_mult = 1.2
	elif order_tier == 3:
		reward_mult = 1.5

	var reward: int = int(round(float(Catalog.sell_value(item_id)) * float(quantity) * 1.9 * reward_mult))
	reward = maxi(int(round(float(reward) / 5.0)) * 5, 5)

	return {
		"id": "%d_%d" % [Time.get_ticks_usec(), _rng.randi_range(0, 99999)],
		"item_id": item_id,
		"qty": quantity,
		"reward": reward,
		"tier": order_tier,
	}


func _sanitize_order(raw: Dictionary) -> Dictionary:
	var item_id: String = str(raw.get("item_id", ""))
	if not Catalog.has_item(item_id):
		return {}
	return {
		"id": str(raw.get("id", "%d" % Time.get_ticks_usec())),
		"item_id": item_id,
		"qty": clampi(int(raw.get("qty", 1)), 1, 5),
		"reward": maxi(int(raw.get("reward", 5)), 5),
		"tier": clampi(int(raw.get("tier", 1)), 1, 3),
	}


func order_progress(order: Dictionary) -> int:
	return mini(item_count(str(order.get("item_id", ""))), int(order.get("qty", 1)))


func can_deliver_order(order: Dictionary) -> bool:
	return _has_items({str(order.get("item_id", "")): int(order.get("qty", 1))})


func deliver_order(index: int) -> Dictionary:
	if index < 0 or index >= orders.size():
		return {"ok": false, "message": "Unknown order."}
	var order: Dictionary = orders[index]
	if order.is_empty():
		return {"ok": false, "message": "Unknown order."}

	var requirement: Dictionary = {str(order["item_id"]): int(order["qty"])}
	if not _has_items(requirement):
		var missing: int = int(order["qty"]) - item_count(str(order["item_id"]))
		return {"ok": false, "message": "Need %d more %s." % [maxi(missing, 1), str(Catalog.item(str(order["item_id"])).get("name", "item"))]}

	_consume_items(requirement)
	var reward: int = int(order["reward"])
	_add_credits(reward)
	stats["orders_completed"] = int(stats["orders_completed"]) + 1
	orders[index] = _generate_order()
	selected_index = -1
	board_changed.emit()
	orders_changed.emit()
	queue_save()
	return {"ok": true, "reward": reward}


func auto_deliver_ready_orders() -> Dictionary:
	if not bool(settings.get("auto_deliver", false)):
		return {"delivered": 0, "credits": 0}
	var delivered: int = 0
	var total_credits: int = 0
	var changed: bool = true
	var guard: int = 0
	while changed and guard < (Catalog.ORDER_SLOTS * 4 + 4):
		changed = false
		guard += 1
		for index in orders.size():
			var order: Dictionary = orders[index] if index < orders.size() else {}
			if order.is_empty():
				continue
			if not can_deliver_order(order):
				continue
			var result: Dictionary = deliver_order(index)
			if bool(result.get("ok", false)):
				delivered += 1
				total_credits += int(result.get("reward", 0))
				changed = true
				break
	if delivered > 0:
		notice.emit("Auto-delivered %d order(s): +%d cr." % [delivered, total_credits], "good")
	return {"delivered": delivered, "credits": total_credits}


# --- Spaceship --------------------------------------------------------------
func part_level(part_id: String) -> int:
	return int(parts.get(part_id, 1))


func next_part_upgrade(part_id: String) -> Dictionary:
	var definition: Dictionary = Catalog.ship_part_def(part_id)
	return EconomyRules.part_upgrade_cost(definition, part_level(part_id))


func part_current_effect(part_id: String) -> String:
	return EconomyRules.part_current_effect(Catalog.ship_part_def(part_id), part_level(part_id))


func can_build_part(part_id: String) -> Dictionary:
	var definition: Dictionary = Catalog.ship_part_def(part_id)
	if definition.is_empty():
		return {"ok": false, "message": "Unknown component."}
	var cost: Dictionary = next_part_upgrade(part_id)
	if cost.is_empty():
		return {"ok": false, "message": "Component is fully upgraded."}
	if credits < int(cost["credits"]):
		return {"ok": false, "message": "Need %d more credits." % (int(cost["credits"]) - credits)}
	if not _has_items(cost["items"]):
		var missing: Array[String] = []
		for item_id in cost["items"]:
			var need: int = int(cost["items"][item_id])
			var have: int = item_count(str(item_id))
			if have < need:
				var item_name: String = str(Catalog.item(str(item_id)).get("name", item_id))
				missing.append("%d x %s" % [need - have, item_name])
		return {"ok": false, "message": "Missing " + ", ".join(missing)}
	return {"ok": true, "cost": cost}


func build_part(part_id: String) -> Dictionary:
	var check: Dictionary = can_build_part(part_id)
	if not bool(check.get("ok", false)):
		return check
	var cost: Dictionary = check["cost"]
	_consume_items(cost["items"])
	_add_credits(-int(cost["credits"]))
	parts[part_id] = part_level(part_id) + 1
	selected_index = -1
	notice.emit("%s upgraded to level %d." % [str(Catalog.ship_part_def(part_id)["name"]), part_level(part_id)], "good")
	advance_tutorial("part")
	_refresh_planet_unlocks(true)
	board_changed.emit()
	ship_changed.emit()
	queue_save()
	return {"ok": true, "level": part_level(part_id), "cost": cost}


func compute_unlocked_planets() -> Array:
	var result: Array = []
	for definition in Catalog.PLANET_DEFS:
		var status: Dictionary = ExpeditionRules.requirements_status(definition, parts)
		if bool(status["ok"]):
			result.append(str(definition["id"]))
	if not (Catalog.STARTER_PLANET in result):
		result.push_front(Catalog.STARTER_PLANET)
	return result


func _refresh_planet_unlocks(announce: bool) -> void:
	var previous: Array = unlocked_planets.duplicate()
	unlocked_planets = compute_unlocked_planets()
	for planet_id in unlocked_planets:
		if not (planet_id in previous):
			var planet: Dictionary = Catalog.planet(str(planet_id))
			if announce and not planet.is_empty() and str(planet_id) != Catalog.STARTER_PLANET:
				notice.emit("New destination unlocked: %s" % str(planet["name"]), "good")
	planets_changed.emit()


# --- Expeditions ------------------------------------------------------------
func expedition_remaining() -> float:
	if expedition.is_empty():
		return 0.0
	return maxf(0.0, float(expedition.get("end_unix", 0.0)) - Time.get_unix_time_from_system())


func expedition_ready() -> bool:
	return not expedition.is_empty() and expedition_remaining() <= 0.0


func can_travel(planet_id: String) -> Dictionary:
	var planet: Dictionary = Catalog.planet(planet_id)
	if planet.is_empty():
		return {"ok": false, "message": "Unknown destination."}
	if not expedition.is_empty():
		return {"ok": false, "message": "Your ship is already away."}
	if Time.get_unix_time_from_system() < next_expedition_unix:
		var remaining: float = next_expedition_unix - Time.get_unix_time_from_system()
		return {"ok": false, "message": "Ship on cooldown: %d:%02d remaining." % [int(remaining) / 60, int(remaining) % 60]}
	var status: Dictionary = ExpeditionRules.requirements_status(planet, parts)
	if not bool(status["ok"]):
		return {"ok": false, "message": "Ship requirements not met.", "missing": status["missing"]}
	return {"ok": true}


func start_expedition(planet_id: String) -> Dictionary:
	var check: Dictionary = can_travel(planet_id)
	if not bool(check.get("ok", false)):
		return check

	var planet: Dictionary = Catalog.planet(planet_id)
	var now: float = Time.get_unix_time_from_system()
	var seed_value: int = int(now * 1000.0) ^ hash(planet_id)
	var rewards: Dictionary = ExpeditionRules.roll_rewards(planet, parts, seed_value)

	expedition = {
		"planet_id": planet_id,
		"planet_name": str(planet["name"]),
		"start_unix": now,
		"end_unix": now + ExpeditionRules.expedition_duration(planet, parts),
		"rewards": rewards,
	}
	advance_tutorial("travel")
	expedition_changed.emit()
	queue_save()
	return {"ok": true, "rewards": rewards, "duration": float(expedition["end_unix"]) - now}


func claim_expedition() -> Dictionary:
	if expedition.is_empty():
		return {"ok": false, "message": "No expedition in progress."}
	if not expedition_ready():
		return {"ok": false, "message": "The ship is still out there."}

	var rewards: Dictionary = _sanitize_rewards(expedition.get("rewards", {}))
	var credits_reward: int = int(rewards.get("credits", 0))
	var items: Dictionary = rewards.get("items", {})
	var planet_name: String = str(expedition.get("planet_name", "Unknown"))

	_add_credits(int(round(float(credits_reward) * rebirth_expedition_multiplier())))
	var delivery: Dictionary = add_items(items)
	stats["expeditions"] = int(stats["expeditions"]) + 1
	expedition = {}
	next_expedition_unix = Time.get_unix_time_from_system() + 600.0
	production_changed.emit()
	expedition_changed.emit()
	queue_save()

	var summary: String = "%s returned %d cr" % [planet_name, credits_reward]
	if int(delivery["added"]) > 0:
		summary += " and %d salvage." % int(delivery["added"])
	if int(delivery["overflow_credits"]) > 0:
		summary += " (Board full: overflow auto-sold.)"

	return {
		"ok": true,
		"credits": credits_reward,
		"items": items,
		"added": int(delivery["added"]),
		"overflow_credits": int(delivery["overflow_credits"]),
		"rare": bool(rewards.get("rare", false)),
		"planet_name": planet_name,
		"summary": summary,
	}


func grant_expedition_bonus(credits_bonus: int) -> void:
	if credits_bonus <= 0:
		return
	_add_credits(credits_bonus)
	queue_save()


func _sanitize_rewards(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {"credits": 0, "items": {}, "rare": false}
	var source: Dictionary = raw
	var items: Dictionary = {}
	var raw_items: Variant = source.get("items", {})
	if raw_items is Dictionary:
		for item_id in raw_items:
			if Catalog.has_item(str(item_id)):
				items[str(item_id)] = maxi(int(raw_items[item_id]), 0)
	return {
		"credits": maxi(int(source.get("credits", 0)), 0),
		"items": items,
		"rare": bool(source.get("rare", false)),
	}


# --- Tutorial ---------------------------------------------------------------
func tutorial_active() -> bool:
	return not bool(tutorial.get("done", false)) and int(tutorial.get("step", 0)) < Catalog.TUTORIAL_STEPS.size()


func tutorial_current() -> Dictionary:
	if not tutorial_active():
		return {}
	return Catalog.TUTORIAL_STEPS[int(tutorial["step"])]


func tutorial_text() -> String:
	var step: Dictionary = tutorial_current()
	return str(step.get("text", ""))


func tutorial_progress_text() -> String:
	if not tutorial_active():
		return ""
	return "%d/%d" % [int(tutorial["step"]) + 1, Catalog.TUTORIAL_STEPS.size()]


func advance_tutorial(event_id: String) -> void:
	if not tutorial_active():
		return
	var step: Dictionary = tutorial_current()
	if str(step.get("id", "")) != event_id:
		return
	tutorial["step"] = int(tutorial["step"]) + 1
	if int(tutorial["step"]) >= Catalog.TUTORIAL_STEPS.size():
		tutorial["done"] = true
		notice.emit("Tutorial complete - the galaxy is yours.", "good")
	tutorial_changed.emit()
	queue_save()


func finish_tutorial() -> void:
	tutorial["done"] = true
	tutorial_changed.emit()
	queue_save()


# --- Settings ---------------------------------------------------------------
func set_music_volume(value: float) -> void:
	settings["music"] = clampf(value, 0.0, 1.0)
	_apply_audio_settings()
	settings_changed.emit()
	queue_save()


func set_sfx_volume(value: float) -> void:
	settings["sfx"] = clampf(value, 0.0, 1.0)
	_apply_audio_settings()
	settings_changed.emit()
	queue_save()


func set_haptics_enabled(value: bool) -> void:
	settings["haptics"] = value
	_apply_audio_settings()
	settings_changed.emit()
	queue_save()


func set_auto_deliver(value: bool) -> void:
	settings["auto_deliver"] = value
	settings_changed.emit()
	queue_save()


func _apply_audio_settings() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("apply_settings"):
		audio.apply_settings(
			float(settings.get("music", 0.55)),
			float(settings.get("sfx", 0.8)),
			bool(settings.get("haptics", true))
		)


# --- Helpers ----------------------------------------------------------------
func push_notice(text: String, kind: String = "info") -> void:
	if text.strip_edges() == "":
		return
	notice.emit(text, kind)


func _save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")


func _emit_all() -> void:
	credits_changed.emit(credits)
	board_changed.emit()
	production_changed.emit()
	generators_changed.emit()
	orders_changed.emit()
	ship_changed.emit()
	planets_changed.emit()
	expedition_changed.emit()
	tutorial_changed.emit()
	settings_changed.emit()
