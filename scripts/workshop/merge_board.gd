extends Control
## Interactive merge board.
##
## Pointer handling lives on the board, never on the tiles. Godot sends the
## matching motion and release events back to the control that received the
## press - even when the pointer leaves its rect - so a gesture cannot be
## orphaned by reparenting the dragged tile. Tiles are passive visuals.
##
## State machine: IDLE -> PRESSED (pointer down, might still be a tap) ->
## DRAGGING (movement passed TAP_THRESHOLD). Every exit path funnels through the
## end/cancel helpers, which release the floating tile and rebuild the grid from
## GameState, so the view can never drift away from the board data.

const Catalog = preload("res://scripts/data/game_catalog.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const MergeItemScene = preload("res://scenes/workshop/merge_item.tscn")

const CELL_GAP := 6.0
const BOARD_PADDING := 10.0
const TAP_THRESHOLD := 14.0
const MIN_CELL := 40.0
const MAX_CELL := 132.0
const DEFAULT_STUCK_TIMEOUT_MSEC := 20000

enum GestureState { IDLE, PRESSED, DRAGGING }

@onready var _frame: PanelContainer = $Frame
@onready var _grid: GridContainer = $Frame/Center/Grid
@onready var _drag_layer: Control = $DragLayer

## A gesture that produces no pointer events for this long is treated as
## orphaned (missed release) and cancelled. Overridable for tests.
var stuck_timeout_msec: int = DEFAULT_STUCK_TIMEOUT_MSEC

var _slots: Array[Panel] = []
var _items: Array = []
var _state: int = GestureState.IDLE
var _drag_index: int = -1
var _drag_item: Control = null
var _pointer_id: int = -1
var _press_point := Vector2.ZERO
var _pointer_point := Vector2.ZERO
var _grab_offset := Vector2.ZERO
var _drag_distance: float = 0.0
var _last_event_msec: int = 0
var _pop_index: int = -1


func _ready() -> void:
	_frame.add_theme_stylebox_override("panel", UiKit.frame_style())
	_grid.columns = Catalog.BOARD_COLUMNS
	_grid.add_theme_constant_override("h_separation", int(CELL_GAP))
	_grid.add_theme_constant_override("v_separation", int(CELL_GAP))
	GameState.board_changed.connect(_on_board_changed)
	resized.connect(_on_resized)
	_build_slots()
	_rebuild()
	set_process(true)


func _process(_delta: float) -> void:
	if _state == GestureState.IDLE:
		return
	# Last-resort guard: if a platform swallows the release entirely (focus
	# switch, OS-level touch cancellation), never leave the board stuck.
	if Time.get_ticks_msec() - _last_event_msec > stuck_timeout_msec:
		push_warning("Merge board cancelled an orphaned gesture after %d ms." % stuck_timeout_msec)
		_cancel_gesture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_gesture()
	elif what == NOTIFICATION_EXIT_TREE:
		var item := _drag_item
		var index := _drag_index
		_reset_gesture_fields()
		_release_floating_tile(item, index)


# --- Input ------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if _state == GestureState.IDLE and not _is_pointer_down_event(event):
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		if _state != GestureState.IDLE:
			_update_gesture(_to_global((event as InputEventMouseMotion).position))
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _is_pointer_down_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return button.pressed and button.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		return touch.pressed and not touch.canceled
	return false


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if _state != GestureState.IDLE:
			return
		if _begin_gesture(_to_global(event.position), -1):
			accept_event()
		return
	if _state == GestureState.IDLE:
		return
	_finish_gesture(_to_global(event.position))
	accept_event()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		if _state != GestureState.IDLE:
			return
		if _begin_gesture(_to_global(event.position), event.index):
			accept_event()
		return

	if _state == GestureState.IDLE:
		return
	# A second finger lifting must not resolve the first finger's gesture.
	if _pointer_id >= 0 and event.index != _pointer_id:
		return

	if event.canceled:
		_cancel_gesture()
	else:
		_finish_gesture(_to_global(event.position))
	accept_event()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if _state == GestureState.IDLE:
		return
	if _pointer_id >= 0 and event.index != _pointer_id:
		return
	_update_gesture(_to_global(event.position))


# --- Gesture lifecycle ------------------------------------------------------
func _begin_gesture(global_point: Vector2, pointer_id: int) -> bool:
	var index: int = _slot_index_at(global_point)
	if index == -1:
		GameState.clear_selection()
		return false

	var item: Variant = _items[index]
	if item == null or not is_instance_valid(item):
		GameState.clear_selection()
		return false

	var slot_rect: Rect2 = _slots[index].get_global_rect()
	_state = GestureState.PRESSED
	_drag_index = index
	_drag_item = item
	_pointer_id = pointer_id
	_press_point = global_point
	_pointer_point = global_point
	_grab_offset = global_point - slot_rect.position
	_drag_distance = 0.0
	_last_event_msec = Time.get_ticks_msec()
	return true


func _update_gesture(global_point: Vector2) -> void:
	if _state == GestureState.IDLE:
		return

	_last_event_msec = Time.get_ticks_msec()
	_pointer_point = global_point
	_drag_distance = maxf(_drag_distance, global_point.distance_to(_press_point))

	if _state == GestureState.PRESSED and _drag_distance >= TAP_THRESHOLD:
		_start_dragging()

	if _state == GestureState.DRAGGING:
		_position_floating_tile(global_point)


func _start_dragging() -> void:
	if not is_instance_valid(_drag_item) or _drag_index < 0 or _drag_index >= _slots.size():
		_cancel_gesture()
		return

	var cell_size: Vector2 = _slots[_drag_index].size
	_state = GestureState.DRAGGING

	_drag_item.reparent(_drag_layer, false)
	_drag_item.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_drag_item.size = cell_size
	_drag_item.modulate = Color(1, 1, 1, 0.95)
	_drag_item.z_index = 30
	_slots[_drag_index].add_theme_stylebox_override("panel", UiKit.slot_style(false, Color.WHITE))

	_position_floating_tile(_pointer_point)
	AudioManager.play("tap")


func _position_floating_tile(global_point: Vector2) -> void:
	if _drag_item == null or not is_instance_valid(_drag_item):
		return
	var local_point: Vector2 = _drag_layer.get_global_transform().affine_inverse() * global_point
	_drag_item.position = local_point - _grab_offset


func _finish_gesture(global_point: Vector2) -> void:
	if _state == GestureState.IDLE:
		return

	var from_index: int = _drag_index
	var was_dragging: bool = _state == GestureState.DRAGGING
	var moved: float = _drag_distance
	var floating: Control = _drag_item

	_reset_gesture_fields()
	_release_floating_tile(floating, from_index)

	# A press that never crossed the threshold is a tap: select, do not move.
	if not was_dragging or moved < TAP_THRESHOLD:
		if from_index >= 0:
			GameState.select_item(from_index)
			AudioManager.play("tap")
		_rebuild()
		return

	var target: int = _slot_index_at(global_point)
	if target == -1 or target == from_index:
		# Dropped outside the grid or back on itself: nothing changes.
		_rebuild()
		return

	var result: Dictionary = GameState.attempt_drop(from_index, target)
	var merged: bool = false
	if bool(result.get("ok", false)):
		if str(result.get("action", "")) == "merge":
			merged = true
			_pop_index = int(result.get("index", target))
			AudioManager.play_with_haptic("merge", 40)
		else:
			AudioManager.play("tap")
	else:
		var message: String = str(result.get("message", ""))
		if message != "":
			AudioManager.play("error")
			GameState.push_notice(message, "warn")

	# Rebuild unconditionally: a failed drop emits no board_changed, and the
	# floating tile was detached from its slot.
	_rebuild()

	if merged and target >= 0 and target < _slots.size():
		_spawn_burst(_slots[target].get_global_rect().get_center())


func _cancel_gesture() -> void:
	if _state == GestureState.IDLE and _drag_item == null:
		return
	var floating: Control = _drag_item
	var index: int = _drag_index
	_reset_gesture_fields()
	_release_floating_tile(floating, index)
	_rebuild()


func _reset_gesture_fields() -> void:
	_state = GestureState.IDLE
	_drag_index = -1
	_drag_item = null
	_pointer_id = -1
	_drag_distance = 0.0


func _release_floating_tile(item: Variant, index: int) -> void:
	if item == null or not is_instance_valid(item):
		return
	if index >= 0 and index < _items.size() and _items[index] == item:
		_items[index] = null
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	item.queue_free()


# --- Layout / data sync -----------------------------------------------------
func _on_board_changed() -> void:
	if _state != GestureState.IDLE:
		# Something outside the gesture changed the board; drop the floating tile.
		_cancel_gesture()
	else:
		_rebuild()


func _on_resized() -> void:
	if _state != GestureState.IDLE:
		_cancel_gesture()
	_fit_cells()


func _build_slots() -> void:
	for slot in _slots:
		_grid.remove_child(slot)
		slot.queue_free()
	_slots.clear()
	_items.clear()
	_reset_gesture_fields()

	for index in GameState.board_size():
		var slot := Panel.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", UiKit.slot_style(false, Color.WHITE))
		_grid.add_child(slot)
		_slots.append(slot)
		_items.append(null)

	_fit_cells()


func _rebuild() -> void:
	if _slots.size() != GameState.board_size():
		_build_slots()

	var selected_item_id: Variant = GameState.selected_item()

	for index in _slots.size():
		var existing: Variant = _items[index]
		if existing != null and is_instance_valid(existing):
			# Detach first so the old tile cannot draw under the new one this frame.
			if existing.get_parent() != null:
				existing.get_parent().remove_child(existing)
			existing.queue_free()
		_items[index] = null

		var slot: Panel = _slots[index]
		var cell: Variant = GameState.item_at(index)
		if cell == null:
			slot.add_theme_stylebox_override("panel", UiKit.slot_style(false, Color.WHITE))
			continue

		var definition: Dictionary = Catalog.item(str(cell))
		var tint: Color = definition.get("color", Color.WHITE)
		slot.add_theme_stylebox_override("panel", UiKit.slot_style(true, tint.darkened(0.4)))

		var item = MergeItemScene.instantiate()
		slot.add_child(item)
		item.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item.setup(str(cell))
		item.set_selected(GameState.selected_index == index)
		var is_match: bool = selected_item_id != null and str(cell) == str(selected_item_id) and GameState.selected_index != index
		item.set_match_glow(is_match)
		_items[index] = item

		if _pop_index == index:
			_pop_index = -1
			item.pop_in()

	_fit_cells()


func _fit_cells() -> void:
	var rows: int = GameState.board_rows
	var columns: int = Catalog.BOARD_COLUMNS
	var available: Vector2 = size - Vector2(BOARD_PADDING * 2.0, BOARD_PADDING * 2.0)
	if available.x < 60.0 or available.y < 60.0:
		return

	var cell_width: float = (available.x - CELL_GAP * float(columns - 1)) / float(columns)
	var cell_height: float = (available.y - CELL_GAP * float(rows - 1)) / float(rows)
	var cell: float = clampf(floorf(minf(cell_width, cell_height)), MIN_CELL, MAX_CELL)
	for slot in _slots:
		slot.custom_minimum_size = Vector2(cell, cell)


func _to_global(local_point: Vector2) -> Vector2:
	return get_global_transform() * local_point


func _slot_index_at(global_point: Vector2) -> int:
	for index in _slots.size():
		if _slots[index].get_global_rect().has_point(global_point):
			return index
	return -1


func _spawn_burst(global_center: Vector2) -> void:
	var particles := CPUParticles2D.new()
	particles.position = global_center - global_position
	particles.amount = 14
	particles.lifetime = 0.45
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 10.0
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 190.0
	particles.gravity = Vector2(0, 280)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	particles.color = Color("#43e8ff")
	particles.z_index = 40
	add_child(particles)
	particles.emitting = true

	var timer := get_tree().create_timer(0.9)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)
