extends Node
## Regression tests for merge-board pointer handling.
##
## Events are injected through the viewport with `push_input(..., true)`, which
## routes them through Godot's real GUI input path (hit-testing, mouse/touch
## focus capture, motion and release delivery). No gameplay method is called
## directly, so these tests exercise the same code a finger or mouse would.
##
## Run with:
##   godot --headless --path . tests/board_input_test.tscn -- --test-mode

const Catalog = preload("res://scripts/data/game_catalog.gd")
const BoardScene = preload("res://scenes/workshop/merge_board.tscn")

const MOUSE := -1
const OUTSIDE_BOARD := Vector2(950, 950)

var _board: Control
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	SaveManager.autosave_enabled = false
	SaveManager.save_path = "user://scrap_to_space_board_input_test.json"
	SaveManager.delete_save()
	GameState.new_game()
	GameState.finish_tutorial()

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)

	_board = BoardScene.instantiate()
	host.add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_board.position = Vector2(40, 40)
	_board.size = Vector2(620, 760)
	await get_tree().process_frame
	await get_tree().process_frame

	print("=== Scrap to Space board input tests ===")

	await _test_tap_selects()
	await _test_tap_empty_clears_selection()
	await _test_drag_to_empty_slot()
	await _test_drag_onto_compatible_merges_once()
	await _test_drag_onto_incompatible_returns_item()
	await _test_drag_outside_board_recovers()
	await _test_release_on_origin_returns_item()
	await _test_cancel_mid_drag()
	await _test_focus_loss_cancels()
	await _test_orphaned_gesture_watchdog()
	await _test_quick_taps()
	await _test_consecutive_merges_and_follow_up()
	await _test_duplicate_release_is_ignored()
	await _test_touch_tap_and_drag()
	await _test_touch_merge_and_cancel()
	await _test_second_finger_does_not_hijack()
	await _test_save_reload_after_interaction()

	SaveManager.delete_save()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- Scenarios --------------------------------------------------------------
func _test_tap_selects() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0))
	await _release(_slot_center(0))

	_check_eq(GameState.selected_index, 0, "tap selects the item")
	_check_eq(str(GameState.board[0]), "broken_circuit", "tap leaves the item in its slot")
	_check_eq(_visible_tiles(), 1, "tap keeps exactly one visible tile")
	_assert_clean("tap")


func _test_tap_empty_clears_selection() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0))
	await _release(_slot_center(0))
	_check_eq(GameState.selected_index, 0, "selection is set before the empty tap")

	await _press(_slot_center(7))
	await _release(_slot_center(7))
	_check_eq(GameState.selected_index, -1, "tapping an empty slot clears the selection")
	_check_eq(str(GameState.board[0]), "broken_circuit", "empty tap leaves items untouched")
	_assert_clean("tap empty")


func _test_drag_to_empty_slot() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0))
	await _move(_slot_center(7))
	_check_eq(_board._state, 2, "moving past the threshold enters the dragging state")
	await _release(_slot_center(7))

	_check_eq(str(GameState.board[7]), "broken_circuit", "drag moves the item to the empty slot")
	_check(GameState.board[0] == null, "drag clears the source slot")
	_check_eq(_count_items(), 1, "drag does not duplicate the item")
	_check_eq(_visible_tiles(), 1, "drag leaves exactly one visible tile")
	_assert_clean("drag to empty")


func _test_drag_onto_compatible_merges_once() -> void:
	await _set_board({0: "broken_circuit", 1: "broken_circuit"})
	var merges_before: int = int(GameState.stats["merges"])

	await _press(_slot_center(0))
	await _move(_slot_center(1))
	await _release(_slot_center(1))

	_check_eq(str(GameState.board[1]), "repaired_circuit", "drag onto an identical item merges")
	_check(GameState.board[0] == null, "merge consumes the dragged item")
	_check_eq(int(GameState.stats["merges"]), merges_before + 1, "one gesture performs exactly one merge")
	_check_eq(_count_items(), 1, "merge produces exactly one item")
	_check_eq(_visible_tiles(), 1, "merge leaves exactly one visible tile")
	_assert_clean("merge")


func _test_drag_onto_incompatible_returns_item() -> void:
	await _set_board({0: "broken_circuit", 1: "rusted_plate"})
	await _press(_slot_center(0))
	await _move(_slot_center(1))
	await _release(_slot_center(1))

	_check_eq(str(GameState.board[0]), "broken_circuit", "incompatible drop leaves the source item")
	_check_eq(str(GameState.board[1]), "rusted_plate", "incompatible drop leaves the target item")
	_check_eq(_count_items(), 2, "incompatible drop loses nothing")
	_check_eq(_visible_tiles(), 2, "incompatible drop returns the tile to its slot")
	_assert_clean("incompatible drop")


func _test_drag_outside_board_recovers() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0))
	await _move(OUTSIDE_BOARD)
	await _release(OUTSIDE_BOARD)

	_check_eq(str(GameState.board[0]), "broken_circuit", "dropping outside the board changes nothing")
	_check_eq(_count_items(), 1, "dropping outside the board loses nothing")
	_check_eq(_visible_tiles(), 1, "dropping outside the board returns the tile")
	_assert_clean("drop outside")

	# The board must still accept input afterwards.
	await _press(_slot_center(0))
	await _move(_slot_center(9))
	await _release(_slot_center(9))
	_check_eq(str(GameState.board[9]), "broken_circuit", "board accepts a new drag after an outside drop")
	_assert_clean("drag after outside drop")


func _test_release_on_origin_returns_item() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0))
	await _move(_slot_center(6))
	await _release(_slot_center(0))

	_check_eq(str(GameState.board[0]), "broken_circuit", "releasing back on the origin keeps the item")
	_check_eq(_count_items(), 1, "releasing on the origin loses nothing")
	_check_eq(_visible_tiles(), 1, "releasing on the origin restores the tile")
	_assert_clean("release on origin")


func _test_cancel_mid_drag() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0))
	await _move(_slot_center(8))
	_board._cancel_gesture()
	await get_tree().process_frame

	_check_eq(str(GameState.board[0]), "broken_circuit", "cancelling a drag keeps the item in place")
	_check_eq(_count_items(), 1, "cancelling a drag loses nothing")
	_assert_clean("cancel")


func _test_focus_loss_cancels() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0))
	await _move(_slot_center(8))
	_board._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().process_frame

	_check_eq(str(GameState.board[0]), "broken_circuit", "losing focus mid-drag keeps the item in place")
	_check_eq(_visible_tiles(), 1, "losing focus mid-drag restores the tile")
	_assert_clean("focus loss")


func _test_orphaned_gesture_watchdog() -> void:
	await _set_board({0: "broken_circuit"})
	_board.stuck_timeout_msec = -1
	await _press(_slot_center(0))
	await get_tree().process_frame
	await get_tree().process_frame
	_board.stuck_timeout_msec = 20000

	_check_eq(str(GameState.board[0]), "broken_circuit", "a missed release does not lose the item")
	_check_eq(_visible_tiles(), 1, "a missed release restores the tile")
	_assert_clean("watchdog")


func _test_quick_taps() -> void:
	await _set_board({0: "broken_circuit", 1: "broken_circuit", 2: "rusted_plate"})
	for index in [0, 1, 2]:
		await _press(_slot_center(index))
		await _release(_slot_center(index))

	_check_eq(GameState.selected_index, 2, "rapid taps select the last tapped item")
	_check_eq(_count_items(), 3, "rapid taps never merge items")
	_check_eq(_visible_tiles(), 3, "rapid taps leave every tile visible")
	_assert_clean("quick taps")


func _test_consecutive_merges_and_follow_up() -> void:
	await _set_board({
		0: "broken_circuit",
		1: "broken_circuit",
		2: "broken_circuit",
		3: "broken_circuit",
	})

	await _drag(0, 1)
	await _drag(2, 3)
	_check_eq(str(GameState.board[1]), "repaired_circuit", "first merge in a sequence works")
	_check_eq(str(GameState.board[3]), "repaired_circuit", "second merge in a sequence works")
	_assert_clean("two merges")

	await _drag(1, 3)
	_check_eq(str(GameState.board[3]), "electronic_module", "consecutive merges combine into the next tier")
	_assert_clean("third merge")

	# Interact immediately with the freshly merged item.
	await _drag(3, 4)
	_check_eq(str(GameState.board[4]), "electronic_module", "the merged item can be dragged immediately")
	_assert_clean("post-merge drag")


func _test_duplicate_release_is_ignored() -> void:
	await _set_board({0: "broken_circuit", 1: "broken_circuit"})
	var merges_before: int = int(GameState.stats["merges"])

	await _press(_slot_center(0))
	await _move(_slot_center(1))
	await _release(_slot_center(1))
	await _release(_slot_center(1))

	_check_eq(int(GameState.stats["merges"]), merges_before + 1, "a duplicate release cannot merge twice")
	_check_eq(_count_items(), 1, "a duplicate release does not duplicate the result")
	_assert_clean("duplicate release")


func _test_touch_tap_and_drag() -> void:
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0), 0)
	await _release(_slot_center(0), 0)
	_check_eq(GameState.selected_index, 0, "touch tap selects the item")
	_assert_clean("touch tap")

	await _press(_slot_center(0), 0)
	await _move(_slot_center(6), 0)
	await _release(_slot_center(6), 0)
	_check_eq(str(GameState.board[6]), "broken_circuit", "touch drag moves the item")
	_assert_clean("touch drag")

	# Drag outside the board with a finger.
	await _press(_slot_center(6), 0)
	await _move(OUTSIDE_BOARD, 0)
	await _release(OUTSIDE_BOARD, 0)
	_check_eq(str(GameState.board[6]), "broken_circuit", "touch drop outside the board changes nothing")
	_assert_clean("touch outside")


func _test_touch_merge_and_cancel() -> void:
	await _set_board({0: "broken_circuit", 1: "broken_circuit"})
	var merges_before: int = int(GameState.stats["merges"])
	await _press(_slot_center(0), 0)
	await _move(_slot_center(1), 0)
	await _release(_slot_center(1), 0)
	_check_eq(str(GameState.board[1]), "repaired_circuit", "touch drag onto an identical item merges")
	_check_eq(int(GameState.stats["merges"]), merges_before + 1, "touch merge happens exactly once")
	_assert_clean("touch merge")

	# OS-cancelled touch sequence.
	await _set_board({0: "broken_circuit"})
	await _press(_slot_center(0), 0)
	await _move(_slot_center(5), 0)
	await _cancel_touch(0, _slot_center(5))
	_check_eq(str(GameState.board[0]), "broken_circuit", "a cancelled touch returns the item")
	_assert_clean("touch cancelled")


func _test_second_finger_does_not_hijack() -> void:
	await _set_board({0: "broken_circuit", 1: "broken_circuit", 2: "rusted_plate"})

	await _press(_slot_center(0), 0)
	await _move(_slot_center(1), 0)
	_check_eq(_board._state, 2, "first finger is dragging")

	await _press(_slot_center(2), 1)
	await _release(_slot_center(2), 1)
	_check_eq(_board._state, 2, "a second finger cannot start or end the gesture")

	await _release(_slot_center(1), 0)
	_check_eq(str(GameState.board[1]), "repaired_circuit", "the first finger still completes its merge")
	_check_eq(str(GameState.board[2]), "rusted_plate", "the second finger's item is untouched")
	_assert_clean("multi-touch")


func _test_save_reload_after_interaction() -> void:
	await _set_board({0: "broken_circuit", 1: "broken_circuit", 2: "broken_circuit"})
	await _drag(0, 1)
	await _drag(2, 4)

	var snapshot: Array = GameState.board.duplicate()
	_check(GameState.save_now(true), "board state saves after moving and merging")
	var loaded: Dictionary = SaveManager.load_save()
	GameState.new_game()
	GameState.apply_save_dict(loaded)
	await get_tree().process_frame
	await get_tree().process_frame

	_check_eq(GameState.board, snapshot, "board contents survive a save and reload")
	_check_eq(GameState.selected_index, -1, "reload clears any selection")
	_check_eq(_visible_tiles(), _count_items(), "reloaded board renders every item once")
	_assert_clean("save reload")


# --- Helpers ----------------------------------------------------------------
func _set_board(cells: Dictionary) -> void:
	for index in GameState.board.size():
		GameState.board[index] = null
	for key in cells:
		GameState.board[int(key)] = str(cells[key])
	GameState.selected_index = -1
	GameState.board_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


func _slot_center(index: int) -> Vector2:
	var slot: Panel = _board._slots[index]
	return slot.get_global_rect().get_center()


func _drag(from_index: int, to_index: int) -> void:
	await _press(_slot_center(from_index))
	await _move(_slot_center(to_index))
	await _release(_slot_center(to_index))


func _press(point: Vector2, touch_index: int = MOUSE) -> void:
	if touch_index == MOUSE:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = point
		get_viewport().push_input(event, true)
	else:
		var event := InputEventScreenTouch.new()
		event.index = touch_index
		event.pressed = true
		event.position = point
		get_viewport().push_input(event, true)
	await get_tree().process_frame


func _release(point: Vector2, touch_index: int = MOUSE) -> void:
	if touch_index == MOUSE:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = false
		event.position = point
		get_viewport().push_input(event, true)
	else:
		var event := InputEventScreenTouch.new()
		event.index = touch_index
		event.pressed = false
		event.position = point
		get_viewport().push_input(event, true)
	await get_tree().process_frame


func _move(point: Vector2, touch_index: int = MOUSE) -> void:
	if touch_index == MOUSE:
		var event := InputEventMouseMotion.new()
		event.position = point
		get_viewport().push_input(event, true)
	else:
		var event := InputEventScreenDrag.new()
		event.index = touch_index
		event.position = point
		get_viewport().push_input(event, true)
	await get_tree().process_frame


func _cancel_touch(touch_index: int, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = touch_index
	event.pressed = false
	event.canceled = true
	event.position = point
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _count_items() -> int:
	var total: int = 0
	for cell in GameState.board:
		if cell != null:
			total += 1
	return total


func _visible_tiles() -> int:
	var total: int = 0
	for node in _board._items:
		if node != null and is_instance_valid(node):
			total += 1
	return total


func _assert_clean(label: String) -> void:
	_check_eq(_board._state, 0, "%s: gesture state is idle" % label)
	_check_eq(_board._drag_index, -1, "%s: drag index is cleared" % label)
	_check(_board._drag_item == null, "%s: drag reference is cleared" % label)
	_check_eq(_board._drag_layer.get_child_count(), 0, "%s: no tile is left floating" % label)
	_check_eq(_visible_tiles(), _count_items(), "%s: visible tiles match board data" % label)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS  %s" % message)
	else:
		_failed += 1
		print("FAIL  %s" % message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s [expected %s, got %s]" % [message, str(expected), str(actual)])
