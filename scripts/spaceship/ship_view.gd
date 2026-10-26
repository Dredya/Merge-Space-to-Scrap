extends Control
## Procedural spacecraft illustration.
##
## The silhouette changes with installed components: plating count follows the
## hull, flames follow the engine, the core glows with power, the dish grows with
## navigation and cargo pods appear with the cargo module.

var hull_level: int = 1
var engine_level: int = 1
var power_level: int = 1
var navigation_level: int = 1
var cargo_level: int = 1

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.ship_changed.connect(_sync)
	_sync()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _sync() -> void:
	hull_level = GameState.part_level("hull")
	engine_level = GameState.part_level("engine")
	power_level = GameState.part_level("power_core")
	navigation_level = GameState.part_level("navigation")
	cargo_level = GameState.part_level("cargo")
	queue_redraw()


func _draw() -> void:
	if size.x < 40.0 or size.y < 40.0:
		return

	var bob: float = sin(_time * 1.3) * 3.5
	var center := Vector2(size.x * 0.5, size.y * 0.52 + bob)
	var width: float = minf(size.x * 0.66, 420.0) * (1.0 + 0.04 * float(hull_level - 1))
	var height: float = width * 0.42

	_draw_flames(center, width, height)
	_draw_hull(center, width, height)
	_draw_cargo(center, width, height)
	_draw_core(center, width, height)
	_draw_navigation(center, width, height)
	_draw_engine_pods(center, width, height)


func _draw_flames(center: Vector2, width: float, height: float) -> void:
	var flicker: float = 0.75 + 0.25 * sin(_time * 14.0)
	var length: float = width * (0.10 + 0.035 * float(engine_level)) * flicker
	for side in [-1.0, 1.0]:
		var origin := center + Vector2(-width * 0.44, height * 0.20 * side)
		var flame := PackedVector2Array([
			origin,
			origin + Vector2(-length, -height * 0.07 * side),
			origin + Vector2(-length * 1.45, 0.0),
			origin + Vector2(-length, height * 0.07 * side),
		])
		draw_colored_polygon(flame, Color(1.0, 0.55, 0.2, 0.55))
		draw_colored_polygon(
			PackedVector2Array([
				origin,
				origin + Vector2(-length * 0.55, -height * 0.035 * side),
				origin + Vector2(-length * 0.8, 0.0),
				origin + Vector2(-length * 0.55, height * 0.035 * side),
			]),
			Color(1.0, 0.9, 0.5, 0.9)
		)


func _draw_hull(center: Vector2, width: float, height: float) -> void:
	var outline := PackedVector2Array([
		center + Vector2(width * 0.50, 0.0),
		center + Vector2(width * 0.22, -height * 0.34),
		center + Vector2(-width * 0.26, -height * 0.38),
		center + Vector2(-width * 0.48, -height * 0.16),
		center + Vector2(-width * 0.48, height * 0.16),
		center + Vector2(-width * 0.26, height * 0.38),
		center + Vector2(width * 0.22, height * 0.34),
	])
	draw_colored_polygon(outline, Color("#2b3d6b"))
	draw_polyline(outline + PackedVector2Array([outline[0]]), Color("#93b4ff"), 2.5)

	# Armour plating grows with hull level.
	var plates: int = hull_level + 1
	for index in plates:
		var t: float = float(index + 1) / float(plates + 1)
		var x: float = center.x - width * 0.30 + width * 0.60 * t
		var half: float = height * (0.30 - 0.10 * t)
		draw_line(Vector2(x, center.y - half), Vector2(x, center.y + half), Color(0.55, 0.68, 0.95, 0.35), 1.5)

	draw_circle(center + Vector2(width * 0.26, -height * 0.04), width * 0.055, Color("#7fe6ff"))
	draw_circle(center + Vector2(width * 0.26, -height * 0.04), width * 0.03, Color("#d8fbff"))


func _draw_cargo(center: Vector2, width: float, height: float) -> void:
	var pods: int = maxi(cargo_level - 1, 0)
	for index in pods:
		var offset_x: float = -width * 0.22 + width * 0.13 * float(index % 3)
		var offset_y: float = height * (0.44 + 0.10 * float(index / 3))
		var pod := Rect2(
			center + Vector2(offset_x, offset_y) - Vector2(width * 0.055, height * 0.09),
			Vector2(width * 0.11, height * 0.18)
		)
		draw_rect(pod, Color("#3d7a5c"))
		draw_rect(pod, Color("#7ff0ae"), false, 1.5)


func _draw_core(center: Vector2, width: float, height: float) -> void:
	var pulse: float = 0.7 + 0.3 * sin(_time * 2.4)
	var radius: float = width * (0.035 + 0.012 * float(power_level)) * pulse
	draw_circle(center + Vector2(-width * 0.02, 0.0), radius * 2.6, Color(0.26, 0.9, 1.0, 0.14))
	draw_circle(center + Vector2(-width * 0.02, 0.0), radius * 1.6, Color(0.26, 0.9, 1.0, 0.3))
	draw_circle(center + Vector2(-width * 0.02, 0.0), radius, Color("#aef6ff"))


func _draw_navigation(center: Vector2, width: float, height: float) -> void:
	var base := center + Vector2(-width * 0.12, -height * 0.40)
	draw_line(base, base + Vector2(0, -height * 0.18), Color("#c6d6ff"), 2.0)
	draw_circle(base + Vector2(0, -height * 0.24), width * 0.035, Color("#b06bff"))
	for index in navigation_level:
		var radius: float = width * (0.055 + 0.018 * float(index))
		draw_arc(base + Vector2(0, -height * 0.24), radius, PI * 1.05, PI * 1.95, 18, Color(0.72, 0.5, 1.0, 0.55), 1.5)


func _draw_engine_pods(center: Vector2, width: float, height: float) -> void:
	for side in [-1.0, 1.0]:
		var pod_center := center + Vector2(-width * 0.30, height * 0.22 * side)
		var pod := Rect2(
			pod_center - Vector2(width * 0.08, height * 0.10),
			Vector2(width * 0.16, height * 0.20)
		)
		draw_rect(pod, Color("#3a4d80"))
		draw_rect(pod, Color("#ffb37a"), false, 1.5)
		draw_circle(pod.position + Vector2(0, pod.size.y * 0.5), height * 0.05, Color("#ff8a4c"))
