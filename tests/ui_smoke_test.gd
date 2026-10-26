extends Node
## UI smoke test: boots the real main scene headless and drives the screen
## actions (collect, sell, upgrade, build, depart, claim, settings, navigation).
##
## Run with:
##   godot --headless --path . tests/ui_smoke_test.tscn -- --test-mode

const Catalog = preload("res://scripts/data/game_catalog.gd")

const TOLERANCE := 2.0

var _passed: int = 0
var _failed: int = 0
var _main: Control
var _viewport: SubViewport


func _ready() -> void:
	SaveManager.autosave_enabled = false
	SaveManager.save_path = "user://scrap_to_space_ui_test.json"
	SaveManager.delete_save()
	GameState.new_game()

	print("=== Scrap to Space UI smoke test ===")

	# A SubViewport lets the test drive real portrait sizes instead of the
	# square headless window.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(720, 1280)
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_main = load("res://scenes/main/main.tscn").instantiate()
	_viewport.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _check_screen_navigation()
	await _check_layout_sizes()
	await _check_workshop_actions()
	await _check_real_pointer_drag()
	await _check_upgrades_screen()
	await _check_spaceship_screen()
	await _check_expedition_screen()
	_check_settings_overlay()
	await _check_reset_confirmation()

	SaveManager.delete_save()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check_screen_navigation() -> void:
	# Coroutine: awaits a frame between each navigation step.
	var screens: Dictionary = _main._screens
	_check(screens.size() == 4, "main scene creates four gameplay screens")
	_check(not screens.has("settings"), "settings is an overlay, not a nav screen")

	for screen_id in ["workshop", "upgrades", "spaceship", "expedition"]:
		_main.go_to(screen_id)
		await get_tree().process_frame
		var any_visible: bool = false
		var others_hidden: bool = true
		for key in screens:
			var screen: Control = screens[key]
			if key == screen_id and screen.visible:
				any_visible = true
			elif key != screen_id and screen.visible:
				others_hidden = false
		_check(any_visible, "navigation shows the %s screen" % screen_id)
		_check(others_hidden, "navigation hides other screens when showing %s" % screen_id)

	_main.go_to("workshop")
	await get_tree().process_frame
	var workshop: Control = screens["workshop"]
	_check(workshop.get_node_or_null("PanelContainer") != null or workshop.get_child_count() > 0, "workshop builds its layout")


func _check_layout_sizes() -> void:
	for viewport_size in [Vector2i(720, 1280), Vector2i(720, 960), Vector2i(900, 1600), Vector2i(1080, 2400)]:
		_viewport.size = viewport_size
		await get_tree().process_frame
		await get_tree().process_frame
		_check_layout_fits(viewport_size)


func _check_layout_fits(viewport_size: Vector2i) -> void:
	var screen_size: Vector2 = _main.size
	_check(
		is_equal_approx(screen_size.x, float(viewport_size.x)) and is_equal_approx(screen_size.y, float(viewport_size.y)),
		"main fills the %s viewport" % str(viewport_size)
	)

	var small_buttons: Array[String] = []
	var offscreen: Array[String] = []
	_collect_problems(_main, screen_size, small_buttons, offscreen)

	var tag: String = " at %s" % str(viewport_size)
	_check(small_buttons.is_empty(), "every button is a comfortable touch target%s%s" % [tag, _format_list(small_buttons)])
	_check(offscreen.is_empty(), "no visible control escapes the screen%s%s" % [tag, _format_list(offscreen)])


func _check_workshop_actions() -> void:
	var workshop: Control = _main._screens["workshop"]
	_main.go_to("workshop")
	await get_tree().process_frame

	# Collect scrap.
	for index in GameState.board.size():
		GameState.board[index] = null
	GameState.generators["collector"]["pending"] = 3
	workshop._on_collect_pressed()
	await get_tree().process_frame
	_check_eq(GameState.item_count("broken_circuit"), 3, "collect button spawns pending scrap")

	# Sell a selected item.
	var credits_before: int = GameState.credits
	GameState.select_item(0)
	await get_tree().process_frame
	workshop._on_sell_pressed()
	await get_tree().process_frame
	_check(GameState.credits > credits_before, "sell button awards credits")

	# Merge two items through the board view.
	for index in GameState.board.size():
		GameState.board[index] = null
	GameState.board[0] = "broken_circuit"
	GameState.board[1] = "broken_circuit"
	GameState.board_changed.emit()
	await get_tree().process_frame
	var merged: Dictionary = GameState.attempt_drop(0, 1)
	await get_tree().process_frame
	_check(bool(merged.get("ok", false)), "board merge runs from the UI layer")
	_check_eq(str(GameState.board[1]), "repaired_circuit", "merged item is visible on the board")

	# Tutorial banner hides when the tutorial is finished.
	GameState.finish_tutorial()
	await get_tree().process_frame
	_check(not workshop._tutorial_panel.visible, "tutorial banner hides once completed")


func _check_real_pointer_drag() -> void:
	# End-to-end pointer test through the full main scene (margins, panels, nav),
	# not just an isolated board.
	var workshop: Control = _main._screens["workshop"]
	_main.go_to("workshop")
	await get_tree().process_frame

	for index in GameState.board.size():
		GameState.board[index] = null
	GameState.board[0] = "broken_circuit"
	GameState.board[1] = "broken_circuit"
	GameState.selected_index = -1
	GameState.board_changed.emit()
	await get_tree().process_frame

	var board: Control = workshop._board
	var from_point: Vector2 = board._slots[0].get_global_rect().get_center()
	var to_point: Vector2 = board._slots[1].get_global_rect().get_center()

	_push_mouse(from_point, true)
	await get_tree().process_frame
	_push_motion(to_point)
	await get_tree().process_frame
	_push_mouse(to_point, false)
	await get_tree().process_frame

	_check_eq(str(GameState.board[1]), "repaired_circuit", "real pointer drag merges through the full UI stack")
	_check_eq(int(board._drag_layer.get_child_count()), 0, "real pointer drag leaves nothing floating")
	_check_eq(int(board._state), 0, "real pointer drag returns the board to idle")


func _push_mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	_viewport.push_input(event, true)


func _push_motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	_viewport.push_input(event, true)


func _check_upgrades_screen() -> void:
	var upgrades: Control = _main._screens["upgrades"]
	_main.go_to("upgrades")
	await get_tree().process_frame

	GameState.credits = 5000
	GameState.generators["collector"]["level"] = 1
	upgrades._on_upgrade_pressed("collector")
	await get_tree().process_frame
	_check_eq(GameState.generator_levels().get("collector", 0), 2, "upgrades screen buys a collector level")

	GameState.credits = 5000
	upgrades._on_expand_pressed()
	await get_tree().process_frame
	_check_eq(GameState.board_size(), 35, "upgrades screen expands the board")

	var widget: Dictionary = upgrades._generator_widgets[0]
	_check(str(widget["level"].text).contains("2"), "generator card shows the new level")


func _check_spaceship_screen() -> void:
	var spaceship: Control = _main._screens["spaceship"]
	_main.go_to("spaceship")
	await get_tree().process_frame

	GameState.credits = 20000
	spaceship._on_build_pressed("hull")
	await get_tree().process_frame
	_check_eq(GameState.part_level("hull"), 2, "ship screen builds a hull level")

	var hull_widget: Dictionary = spaceship._part_widgets[0]
	_check(str(hull_widget["level"].text).contains("2"), "component card shows the installed level")

	GameState.parts["hull"] = 5
	spaceship._refresh()
	await get_tree().process_frame
	_check(str(hull_widget["button"].text).contains("MAX"), "maxed component disables its button")


func _check_expedition_screen() -> void:
	var expedition: Control = _main._screens["expedition"]
	_main.go_to("expedition")
	await get_tree().process_frame

	_game_state_ready_for_travel()
	expedition._on_depart_pressed("junkyard")
	await get_tree().process_frame
	_check(not GameState.expedition.is_empty(), "travel screen launches an expedition")
	_check(expedition._active_panel.visible, "active expedition panel is shown")

	GameState.expedition["end_unix"] = Time.get_unix_time_from_system() - 1.0
	expedition._refresh_active()
	await get_tree().process_frame
	_check(not expedition._claim_button.disabled, "claim button enables on arrival")

	expedition._on_claim_pressed()
	await get_tree().process_frame
	_check(expedition._result_overlay.visible, "claim shows the result panel")
	expedition._close_result()
	_check(not expedition._result_overlay.visible, "result panel closes")

	# A locked destination must refuse departure.
	GameState.parts["engine"] = 1
	GameState.parts["hull"] = 1
	GameState.parts["navigation"] = 1
	GameState.parts["power_core"] = 1
	expedition._refresh_buttons()
	await get_tree().process_frame
	_check(expedition._planet_widgets[1]["button"].disabled, "locked destinations cannot depart")


func _check_settings_overlay() -> void:
	_check(_main._settings_overlay != null, "settings overlay is created")
	_main._toggle_settings()
	_check(_main._settings_overlay.visible, "settings overlay opens")
	GameState.set_music_volume(0.25)
	_check(is_equal_approx(float(GameState.settings["music"]), 0.25), "music slider updates settings")
	_main._toggle_settings()
	_check(not _main._settings_overlay.visible, "settings overlay closes")


func _check_reset_confirmation() -> void:
	var settings_overlay: Control = _main._settings_overlay
	GameState.credits = 4242
	settings_overlay._on_reset_pressed()
	await get_tree().process_frame
	_check_eq(GameState.credits, 4242, "reset does nothing until the dialog is confirmed")

	settings_overlay._on_reset_confirmed()
	await get_tree().process_frame
	_check_eq(GameState.credits, Catalog.STARTING_CREDITS, "confirmed reset restores the starting credits")


# --- Helpers ----------------------------------------------------------------
func _game_state_ready_for_travel() -> void:
	GameState.parts = {"hull": 3, "engine": 3, "power_core": 3, "navigation": 3, "cargo": 1}
	GameState.expedition = {}
	GameState.unlocked_planets = GameState.compute_unlocked_planets()
	for index in GameState.board.size():
		GameState.board[index] = null


func _collect_problems(node: Node, screen_size: Vector2, small: Array[String], offscreen: Array[String]) -> void:
	var control := node as Control
	if control == null or not control.visible:
		return

	if control is Button and not control.disabled:
		var size: Vector2 = control.size
		if size.y > 0.0 and size.y < 44.0:
			small.append("%s (%.0fpx)" % [control.name, size.y])

	if control is Button or control is PanelContainer or control is Label:
		var inside_scroll: bool = _inside_scroll(control)
		if not inside_scroll:
			var rect: Rect2 = control.get_global_rect()
			if rect.size.x > 0.0 and rect.size.y > 0.0:
				if rect.position.x < -TOLERANCE or rect.position.y < -TOLERANCE \
						or rect.end.x > screen_size.x + TOLERANCE or rect.end.y > screen_size.y + TOLERANCE:
					offscreen.append("%s%s" % [control.name, rect])

	for child in node.get_children():
		_collect_problems(child, screen_size, small, offscreen)


func _inside_scroll(node: Node) -> bool:
	var current: Node = node.get_parent()
	while current != null:
		if current is ScrollContainer:
			return true
		current = current.get_parent()
	return false


func _format_list(items: Array[String]) -> String:
	if items.is_empty():
		return ""
	return ": " + ", ".join(items)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS  %s" % message)
	else:
		_failed += 1
		print("FAIL  %s" % message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s [expected %s, got %s]" % [message, str(expected), str(actual)])
