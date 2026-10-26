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

const NAV_ICONS := {
	"workshop": "🛠️",
	"upgrades": "⬆️",
	"spaceship": "🚀",
	"expedition": "🌌",
}

func _nav_icon(id: String) -> String:
	return str(NAV_ICONS.get(id, "•"))

var _screens: Dictionary = {}
var _current: String = ""
var _screen_host: Control
var _credits_label: Label
var _ship_level_label: Label
var _nav_buttons: Dictionary = {}
var _nav_dots: Dictionary = {}
var _nav_indicators: Dictionary = {}
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _settings_overlay: Control
var _interstitial_timer: float = 0.0
var _interstitial_playing: bool = false
var _paused: bool = false


func _ready() -> void:
	theme = UiKit.make_theme()
	_build_background()
	_build_frame()
	_create_screens()
	_build_settings_overlay()
	_build_toast()

	GameState.credits_changed.connect(_on_credits_changed)
	GameState.notice.connect(_show_toast)
	GameState.ship_changed.connect(_on_ship_changed)
	GameState.orders_changed.connect(_refresh_nav_dots)
	GameState.expedition_changed.connect(_refresh_nav_dots)
	GameState.board_changed.connect(_refresh_nav_dots)

	_on_credits_changed(GameState.credits)
	_on_ship_changed()
	_refresh_nav_dots()
	go_to("workshop")

	AudioManager.apply_settings(
		float(GameState.settings.get("music", 0.55)),
		float(GameState.settings.get("sfx", 0.8)),
		bool(GameState.settings.get("haptics", true))
	)
	set_process(true)


func _process(delta: float) -> void:
	if _paused:
		return
	_interstitial_timer += delta
	if _interstitial_timer >= 300.0 and not _interstitial_playing:
		_interstitial_timer = 0.0
		_play_interstitial()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_paused = false


func _play_interstitial() -> void:
	if not Monetization.ads_available():
		return
	_interstitial_playing = true
	var granted: bool = await Monetization.watch_rewarded_ad("interstitial")
	_interstitial_playing = false
	GameState.push_notice("Ad finished.", "info")


func _build_background() -> void:
	var background := Starfield.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func _build_frame() -> void:
	var column := UiKit.vbox(0)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var top := UiKit.card(8, UiKit.COLOR_BORDER_HI)
	top.custom_minimum_size = Vector2(0, 74)
	var top_row := UiKit.hbox(10)
	top.add_child(top_row)

	_ship_level_label = UiKit.label("Ship Lv. 1", 15, UiKit.COLOR_ACCENT)
	_ship_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(_ship_level_label)

	var credits_chip := UiKit.chip(UiKit.credits(0), UiKit.COLOR_GOLD)
	_credits_label = credits_chip.get_child(0) as Label
	_credits_label.add_theme_font_size_override("font_size", 17)
	top_row.add_child(credits_chip)

	var settings_button := UiKit.icon_button("⚙", 44)
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
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 62)
		button.flat = true
		var col := UiKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var indicator := Control.new()
		indicator.custom_minimum_size = Vector2(0, 3)
		indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		indicator.modulate = Color(1, 1, 1, 0)
		col.add_child(indicator)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 10)
		dot.add_theme_color_override("font_color", UiKit.COLOR_BAD)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.visible = false
		col.add_child(dot)
		var icon := UiKit.label(_nav_icon(str(item["id"])), 20, UiKit.COLOR_MUTED)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(icon)
		var lbl := UiKit.label(str(item["label"]), 10, UiKit.COLOR_MUTED)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lbl)
		button.add_child(col)
		button.pressed.connect(go_to.bind(str(item["id"])))
		nav_row.add_child(button)
		_nav_buttons[str(item["id"])] = button
		_nav_dots[str(item["id"])] = dot
		_nav_indicators[str(item["id"])] = indicator

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
		if key != screen_id:
			screen.modulate = Color(1, 1, 1, 1)

	var active_screen: Control = _screens[screen_id]
	active_screen.modulate = Color(1, 1, 1, 0.0)
	if active_screen.has_method("on_show"):
		active_screen.on_show()
	var tween := create_tween()
	tween.tween_property(active_screen, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	for key in _nav_buttons:
		_style_nav_button(_nav_buttons[key], key == screen_id)

	AudioManager.play("tap")


func _style_nav_button(button: Button, active: bool) -> void:
	var color: Color = UiKit.COLOR_ACCENT if active else UiKit.COLOR_MUTED
	for child in button.get_children():
		if child is VBoxContainer:
			for grand in child.get_children():
				if grand is Label:
					grand.add_theme_color_override("font_color", color)
				elif grand is Control and grand.custom_minimum_size.y == 3:
					grand.modulate = Color(color.r, color.g, color.b, 1.0 if active else 0.0)


func _on_credits_changed(value: int) -> void:
	if _credits_label != null:
		_credits_label.text = UiKit.credits(value)
	_refresh_nav_dots()


func _on_ship_changed() -> void:
	if _ship_level_label != null:
		var total: int = 0
		for part_id in GameState.parts:
			total += int(GameState.parts[part_id])
		_ship_level_label.text = "Ship Lv. %d" % total
	_refresh_nav_dots()


func _refresh_nav_dots() -> void:
	var workshop_dot: Control = _nav_dots.get("workshop", null)
	if workshop_dot != null:
		var has_deliverable: bool = false
		for order in GameState.orders:
			var o: Dictionary = order if order is Dictionary else {}
			if not o.is_empty() and GameState.can_deliver_order(o):
				has_deliverable = true
				break
		workshop_dot.visible = has_deliverable

	var upgrades_dot: Control = _nav_dots.get("upgrades", null)
	if upgrades_dot != null:
		upgrades_dot.visible = _any_affordable_part_upgrade()

	var travel_dot: Control = _nav_dots.get("expedition", null)
	if travel_dot != null:
		var claim_ready: bool = false
		if not GameState.expedition.is_empty():
			claim_ready = float(GameState.expedition.get("end_unix", 0.0)) <= Time.get_unix_time_from_system()
		travel_dot.visible = claim_ready


func _any_affordable_part_upgrade() -> bool:
	for part_id in GameState.parts:
		var cost: Dictionary = GameState.next_part_upgrade(str(part_id))
		if cost.is_empty():
			continue
		var credits_cost: int = int(cost.get("credits", 0))
		if GameState.credits < credits_cost:
			continue
		var items: Dictionary = cost.get("items", {}) if cost.get("items", {}) is Dictionary else {}
		var ok: bool = true
		for item_id in items:
			if GameState.item_count(str(item_id)) < int(items[item_id]):
				ok = false
				break
		if ok:
			return true
	return false


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
	_toast.modulate = Color(1, 1, 1, 0)
	_toast.offset_top = 40.0

	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_property(_toast, "offset_top", 80.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.set_parallel(false)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)
