extends Control
## A single merge-board tile.
##
## Passive visual: it draws its icon procedurally (no texture assets) and shows
## the tier badge, but it never handles input. The merge board owns the whole
## gesture, because a tile that changes its own mouse_filter (or is reparented)
## while a press is active would otherwise never receive the release.

const Catalog = preload("res://scripts/data/game_catalog.gd")

var item_id: String = ""
var selected: bool = false

var _name_label: Label
var _background := StyleBoxFlat.new()


func _ready() -> void:
	# Input is routed by the board; the tile must never swallow pointer events.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_background.set_corner_radius_all(10)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color("#cfd9f5"))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.clip_text = true
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.anchor_left = 0.0
	_name_label.anchor_right = 1.0
	_name_label.anchor_top = 0.6
	_name_label.anchor_bottom = 1.0
	_name_label.offset_left = 3.0
	_name_label.offset_right = -3.0
	_name_label.offset_top = 0.0
	_name_label.offset_bottom = -4.0
	add_child(_name_label)

	resized.connect(queue_redraw)


func setup(new_item_id: String) -> void:
	item_id = new_item_id
	if _name_label == null:
		_name_label = get_child(0) as Label
	if _name_label != null:
		var definition: Dictionary = Catalog.item(new_item_id)
		_name_label.text = str(definition.get("name", ""))
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func pop_in() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.55, 0.55)
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)


func _draw() -> void:
	var definition: Dictionary = Catalog.item(item_id)
	if definition.is_empty():
		return

	var tint: Color = definition.get("color", Color.WHITE)
	_background.bg_color = Color("#1d2f59") if selected else Color("#141f3d")
	_background.border_color = Color.WHITE if selected else tint.darkened(0.15)
	_background.set_border_width_all(3 if selected else 2)
	_background.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

	var icon_rect := Rect2(
		Vector2(size.x * 0.14, size.y * 0.10),
		Vector2(size.x * 0.72, size.y * 0.44)
	)
	_draw_icon(icon_rect, str(definition.get("shape", "chip")), tint, int(definition.get("tier", 1)))

	var font: Font = ThemeDB.fallback_font
	var badge: String = "T%d" % int(definition.get("tier", 1))
	draw_string(font, Vector2(7.0, 15.0), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.65, 0.9, 0.9))


func _draw_icon(rect: Rect2, shape: String, tint: Color, tier: int) -> void:
	match shape:
		"plate":
			_draw_plate(rect, tint)
		"crystal":
			_draw_crystal(rect, tint)
		_:
			_draw_chip(rect, tint)

	if tier >= 5:
		var sparkle: Color = Color(1.0, 1.0, 1.0, 0.55)
		draw_line(rect.position, rect.position + Vector2(8.0, 8.0), sparkle, 1.5)
		draw_line(rect.end - Vector2(8.0, 8.0), rect.end, sparkle, 1.5)


func _draw_chip(rect: Rect2, tint: Color) -> void:
	var body := Rect2(
		rect.position + Vector2(rect.size.x * 0.12, rect.size.y * 0.18),
		rect.size * Vector2(0.76, 0.64)
	)
	draw_rect(body, tint.darkened(0.5))
	draw_rect(body.grow(-2.0), tint.darkened(0.18))

	for index in 3:
		var y: float = body.position.y + body.size.y * (0.22 + 0.28 * float(index))
		draw_line(Vector2(rect.position.x + 2.0, y), Vector2(body.position.x, y), tint, 2.0)
		draw_line(Vector2(body.end.x, y), Vector2(rect.end.x - 2.0, y), tint, 2.0)

	var die_size: float = rect.size.x * 0.20
	var die := Rect2(body.get_center() - Vector2(die_size, die_size) * 0.5, Vector2(die_size, die_size))
	draw_rect(die, tint.lightened(0.35))


func _draw_plate(rect: Rect2, tint: Color) -> void:
	var w: float = rect.size.x
	var h: float = rect.size.y
	var points := PackedVector2Array([
		rect.position + Vector2(w * 0.06, h * 0.30),
		rect.position + Vector2(w * 0.22, h * 0.10),
		rect.position + Vector2(w * 0.78, h * 0.10),
		rect.position + Vector2(w * 0.94, h * 0.30),
		rect.position + Vector2(w * 0.86, h * 0.92),
		rect.position + Vector2(w * 0.14, h * 0.92),
	])
	draw_colored_polygon(points, tint.darkened(0.5))
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, tint, 2.0)

	for offset in [Vector2(0.22, 0.30), Vector2(0.78, 0.30), Vector2(0.22, 0.78), Vector2(0.78, 0.78)]:
		draw_circle(rect.position + rect.size * offset, 2.4, tint.lightened(0.35))


func _draw_crystal(rect: Rect2, tint: Color) -> void:
	var center: Vector2 = rect.get_center()
	var w: float = rect.size.x
	var h: float = rect.size.y
	var outer := PackedVector2Array([
		center + Vector2(0.0, -h * 0.46),
		center + Vector2(w * 0.30, 0.0),
		center + Vector2(0.0, h * 0.46),
		center + Vector2(-w * 0.30, 0.0),
	])
	draw_colored_polygon(outer, tint.darkened(0.5))
	var outline: PackedVector2Array = outer.duplicate()
	outline.append(outer[0])
	draw_polyline(outline, tint, 2.0)

	var inner := PackedVector2Array([
		center + Vector2(0.0, -h * 0.24),
		center + Vector2(w * 0.15, 0.0),
		center + Vector2(0.0, h * 0.24),
		center + Vector2(-w * 0.15, 0.0),
	])
	draw_colored_polygon(inner, tint.lightened(0.3))
