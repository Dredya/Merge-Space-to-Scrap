extends Control
## Lightweight drifting starfield used behind every screen.
##
## Drawn procedurally so the game ships with no background textures and no
## per-frame node churn.

var _stars: Array = []
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20261026
	_regenerate()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_regenerate()


func _process(delta: float) -> void:
	_time += delta
	var bounds: Vector2 = size
	for star in _stars:
		var position: Vector2 = star["pos"]
		position.y += float(star["speed"]) * delta
		if position.y > bounds.y + 4.0:
			position.y = -4.0
		star["pos"] = position
	queue_redraw()


func _draw() -> void:
	var bounds: Vector2 = size
	if bounds.x <= 1.0 or bounds.y <= 1.0:
		return

	draw_circle(Vector2(bounds.x * 0.82, bounds.y * 0.14), bounds.x * 0.55, Color(0.17, 0.09, 0.35, 0.35))
	draw_circle(Vector2(bounds.x * 0.12, bounds.y * 0.72), bounds.x * 0.5, Color(0.04, 0.18, 0.3, 0.3))
	draw_circle(Vector2(bounds.x * 0.55, bounds.y * 0.42), bounds.x * 0.35, Color(0.08, 0.06, 0.22, 0.25))

	for star in _stars:
		var twinkle: float = 0.72 + 0.28 * sin(_time * 1.4 + float(star["radius"]) * 4.0)
		draw_circle(star["pos"], float(star["radius"]), Color(0.86, 0.93, 1.0, float(star["alpha"]) * twinkle))


func _regenerate() -> void:
	var bounds: Vector2 = size
	if bounds.x <= 1.0 or bounds.y <= 1.0:
		return
	_stars.clear()
	for _i in 90:
		_stars.append({
			"pos": Vector2(_rng.randf() * bounds.x, _rng.randf() * bounds.y),
			"radius": _rng.randf_range(0.6, 2.2),
			"speed": _rng.randf_range(4.0, 18.0),
			"alpha": _rng.randf_range(0.14, 0.72),
		})
	queue_redraw()
