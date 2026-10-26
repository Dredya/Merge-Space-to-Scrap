extends Control
## Application shell: animated background, persistent credit bar, bottom
## navigation between the four gameplay screens and the settings overlay.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Starfield = preload("res://scripts/ui/starfield.gd")
const WorkshopScene = preload("res://scenes/workshop/workshop.tscn")
const UpgradesScene = preload("res://scenes/ui/upgrade_panel.tscn")
const SpaceshipScene = preload("res://scenes/spaceship/spaceship_screen.tscn")
const ExpeditionScene = preload("res://scenes/expedition/expedition_screen.tscn")
const SettingsScene = preload("res://scenes/ui/settings_screen.tscn")

const NAV_ITEMS := [
	{"id": "workshop", "label": "WORKSHOP"},
	{"id": "upgrades", "label": "UPGRADES"},
	{"id": "spaceship", "label": "SHIP"},
	{"id": "expedition", "label": "TRAVEL"},
]

var _screens: Dictionary = {}
var _current: String = ""
var _screen_host: Control
var _credits_label: Label
var _nav_buttons: Dictionary = {}
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _settings_overlay: Control


func _ready() -> void:
	theme = UiKit.make_theme()
	_build_background()
	_build_frame()
	_create_screens()
	_build_settings_overlay()
	_build_toast()

	GameState.credits_changed.connect(_on_credits_changed)
	GameState.notice.connect(_show_toast)

	_on_credits_changed(GameState.credits)
	go_to("workshop")

	AudioManager.apply_settings(
		float(GameState.settings.get("music", 0.55)),
		float(GameState.settings.get("sfx", 0.8)),
		bool(GameState.settings.get("haptics", true))
	)


func _build_background() -> void:
	var background := Starfield.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func _build_frame() -> void:
	var column := UiKit.vbox(0)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var top := UiKit.panel(8, Color("#0d1730"))
	top.custom_minimum_size = Vector2(0, 66)
	var top_row := UiKit.hbox(10)
	top.add_child(top_row)

	var title := UiKit.label("SCRAP TO SPACE", 16, UiKit.COLOR_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(title)

	_credits_label = UiKit.label(UiKit.credits(0), 19, UiKit.COLOR_GOLD)
	_credits_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(_credits_label)

	var settings_button := UiKit.button("SETTINGS", 11)
	settings_button.custom_minimum_size = Vector2(108, 44)
	settings_button.pressed.connect(_toggle_settings)
	top_row.add_child(settings_button)

	column.add_child(UiKit.margin(top, 12, 6, 12, 0))

	_screen_host = Control.new()
	_screen_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_screen_host)

	var nav := UiKit.panel(6, Color("#0d1730"))
	var nav_row := UiKit.hbox(6)
	nav.add_child(nav_row)
	for item in NAV_ITEMS:
		var button := UiKit.button(str(item["label"]), 12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 54)
		button.pressed.connect(go_to.bind(str(item["id"])))
		nav_row.add_child(button)
		_nav_buttons[str(item["id"])] = button

	column.add_child(UiKit.margin(nav, 10, 0, 10, 10))


func _create_screens() -> void:
	_screens["workshop"] = WorkshopScene.instantiate()
	_screens["upgrades"] = UpgradesScene.instantiate()
	_screens["spaceship"] = SpaceshipScene.instantiate()
	_screens["expedition"] = ExpeditionScene.instantiate()

	for screen_id in _screens:
		var screen: Control = _screens[screen_id]
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.visible = false
		_screen_host.add_child(screen)
		if screen.has_signal("request_screen"):
			screen.request_screen.connect(go_to)


func _build_settings_overlay() -> void:
	_settings_overlay = SettingsScene.instantiate()
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.visible = false
	add_child(_settings_overlay)
	if _settings_overlay.has_signal("closed"):
		_settings_overlay.closed.connect(_toggle_settings)


func _build_toast() -> void:
	_toast = UiKit.panel(10, Color("#16223f"))
	_toast.anchor_left = 0.06
	_toast.anchor_right = 0.94
	_toast.anchor_top = 0.0
	_toast.anchor_bottom = 0.0
	_toast.offset_top = 80.0
	_toast.offset_bottom = 156.0
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

	_toast_label = UiKit.label("", 13, UiKit.COLOR_ACCENT, true)
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)


func go_to(screen_id: String) -> void:
	if not _screens.has(screen_id):
		return
	_current = screen_id

	for key in _screens:
		var screen: Control = _screens[key]
		screen.visible = key == screen_id

	var active_screen: Control = _screens[screen_id]
	if active_screen.has_method("on_show"):
		active_screen.on_show()

	for key in _nav_buttons:
		_style_nav_button(_nav_buttons[key], key == screen_id)

	AudioManager.play("tap")


func _style_nav_button(button: Button, active: bool) -> void:
	if active:
		button.add_theme_stylebox_override("normal", UiKit.selected_box())
		button.add_theme_color_override("font_color", UiKit.COLOR_ACCENT)
	else:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_color_override("font_color")


func _on_credits_changed(value: int) -> void:
	if _credits_label != null:
		_credits_label.text = UiKit.credits(value)


func _toggle_settings() -> void:
	if _settings_overlay == null:
		return
	_settings_overlay.visible = not _settings_overlay.visible
	AudioManager.play("tap")


func _show_toast(text: String, kind: String = "info") -> void:
	if _toast == null or text.strip_edges() == "":
		return

	var color: Color = UiKit.COLOR_ACCENT
	if kind == "good":
		color = UiKit.COLOR_GOOD
	elif kind == "warn":
		color = UiKit.COLOR_BAD

	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast.modulate = Color(1, 1, 1, 1)

	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)
