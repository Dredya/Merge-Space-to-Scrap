extends Control
## Expedition screen: destinations, requirements, active-trip countdown and the
## reward result panel (with an optional simulated-ad bonus).

signal request_screen(screen_id: String)

const Catalog = preload("res://scripts/data/game_catalog.gd")
const ExpeditionRules = preload("res://scripts/logic/expedition_rules.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

var _active_panel: PanelContainer
var _active_title: Label
var _active_status: Label
var _claim_button: Button
var _planet_widgets: Array = []
var _result_overlay: Control
var _result_body: Label
var _result_ad_button: Button
var _result_credits: int = 0
var _result_ad_used: bool = false
var _ui_timer: float = 0.0


func _ready() -> void:
	_build()
	GameState.expedition_changed.connect(_refresh)
	GameState.ship_changed.connect(_refresh)
	GameState.credits_changed.connect(func(_value: int) -> void: _refresh_buttons())
	_refresh()
	set_process(true)


func on_show() -> void:
	_refresh()


func _process(delta: float) -> void:
	_ui_timer += delta
	if _ui_timer < 0.25:
		return
	_ui_timer = 0.0
	_refresh_active()


func _build() -> void:
	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 12)
	page.add_theme_constant_override("margin_top", 8)
	page.add_theme_constant_override("margin_right", 12)
	page.add_theme_constant_override("margin_bottom", 8)
	add_child(page)

	var column := UiKit.vbox(8)
	page.add_child(column)

	var header := UiKit.hbox(8)
	var title := UiKit.label("Expeditions", 20, UiKit.COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(UiKit.label("3 destinations", 12, UiKit.COLOR_MUTED))
	column.add_child(header)

	_build_active_panel(column)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var cards := UiKit.vbox(8)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)

	for definition in Catalog.PLANET_DEFS:
		cards.add_child(_build_planet_card(definition))

	_build_result_overlay()


func _build_active_panel(column: VBoxContainer) -> void:
	_active_panel = UiKit.panel(9, Color("#14224a"))
	var body := UiKit.vbox(3)
	_active_panel.add_child(body)

	_active_title = UiKit.label("", 15, UiKit.COLOR_ACCENT)
	body.add_child(_active_title)
	_active_status = UiKit.label("", 13, UiKit.COLOR_TEXT)
	body.add_child(_active_status)

	_claim_button = UiKit.button("CLAIM SALVAGE", 15, true)
	_claim_button.custom_minimum_size = Vector2(0, 44)
	_claim_button.pressed.connect(_on_claim_pressed)
	body.add_child(_claim_button)

	column.add_child(_active_panel)


func _build_planet_card(definition: Dictionary) -> Control:
	var accent: Color = definition.get("accent", UiKit.COLOR_ACCENT)
	var card := UiKit.panel(10)
	var body := UiKit.vbox(4)
	card.add_child(body)

	var head := UiKit.hbox(8)
	var name_label := UiKit.label(str(definition.get("name", "")), 17, accent)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var duration_label := UiKit.label("%ds" % int(definition.get("duration", 30)), 12, UiKit.COLOR_MUTED)
	head.add_child(duration_label)
	body.add_child(head)

	body.add_child(UiKit.label(str(definition.get("blurb", "")), 11, UiKit.COLOR_MUTED, true))

	var rewards := UiKit.label("%d-%d cr - %d-%d salvage - %d%% rare" % [
		int(definition.get("credits_min", 0)),
		int(definition.get("credits_max", 0)),
		int(definition.get("items_min", 1)),
		int(definition.get("items_max", 1)),
		int(round(float(definition.get("rare_chance", 0.0)) * 100.0)),
	], 11, UiKit.COLOR_GOLD)
	body.add_child(rewards)

	var requirements := UiKit.label("", 11, UiKit.COLOR_MUTED, true)
	body.add_child(requirements)

	var button := UiKit.button("DEPART", 14)
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(_on_depart_pressed.bind(str(definition["id"])))
	body.add_child(button)

	_planet_widgets.append({
		"definition": definition,
		"requirements": requirements,
		"button": button,
	})
	return card


func _build_result_overlay() -> void:
	_result_overlay = Control.new()
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.visible = false
	add_child(_result_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.add_child(center)

	var panel := UiKit.panel(16)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var body := UiKit.vbox(10)
	panel.add_child(body)

	body.add_child(UiKit.label("Expedition complete", 20, UiKit.COLOR_ACCENT))
	_result_body = UiKit.label("", 14, UiKit.COLOR_TEXT, true)
	body.add_child(_result_body)

	_result_ad_button = UiKit.button("WATCH SIMULATED AD (+50% CREDITS)", 13)
	_result_ad_button.custom_minimum_size = Vector2(0, 46)
	_result_ad_button.pressed.connect(_on_result_ad_pressed)
	body.add_child(_result_ad_button)

	var continue_button := UiKit.button("CONTINUE", 15, true)
	continue_button.custom_minimum_size = Vector2(0, 48)
	continue_button.pressed.connect(_close_result)
	body.add_child(continue_button)


func _refresh() -> void:
	_refresh_active()
	_refresh_buttons()


func _refresh_active() -> void:
	if _active_panel == null:
		return
	if GameState.expedition.is_empty():
		_active_panel.visible = false
		return

	_active_panel.visible = true
	var planet_name: String = str(GameState.expedition.get("planet_name", "Unknown"))
	var remaining: float = GameState.expedition_remaining()
	_active_title.text = "In transit: %s" % planet_name

	if remaining > 0.0:
		var seconds: int = int(ceil(remaining))
		_active_status.text = "Arriving in %d:%02d" % [seconds / 60, seconds % 60]
		_claim_button.disabled = true
		_claim_button.text = "SCANNING..."
	else:
		_active_status.text = "Salvage secured - claim your reward."
		_claim_button.disabled = false
		_claim_button.text = "CLAIM SALVAGE"


func _refresh_buttons() -> void:
	for entry in _planet_widgets:
		var definition: Dictionary = entry["definition"]
		var status: Dictionary = ExpeditionRules.requirements_status(definition, GameState.parts)
		var lines: Array[String] = []
		for missing in status["missing"]:
			lines.append("%s Lv %d (have %d)" % [
				str(missing.get("name", "")), int(missing.get("required", 1)), int(missing.get("current", 0))
			])
		if lines.is_empty():
			entry["requirements"].text = "Requirements met."
			entry["requirements"].add_theme_color_override("font_color", UiKit.COLOR_GOOD)
		else:
			entry["requirements"].text = "Needs " + ", ".join(lines)
			entry["requirements"].add_theme_color_override("font_color", UiKit.COLOR_BAD)

		var button: Button = entry["button"]
		if not bool(status.get("ok", false)):
			button.disabled = true
			button.text = "LOCKED"
		elif not GameState.expedition.is_empty():
			button.disabled = true
			button.text = "SHIP AWAY"
		else:
			button.disabled = false
			button.text = "DEPART"


func _on_depart_pressed(planet_id: String) -> void:
	var result: Dictionary = GameState.start_expedition(planet_id)
	if bool(result.get("ok", false)):
		AudioManager.play_with_haptic("depart", 60)
		GameState.push_notice("Departure confirmed. Salvage run underway.", "good")
		_refresh()
	else:
		AudioManager.play("error")
		GameState.push_notice(str(result.get("message", "Cannot depart.")), "warn")


func _on_claim_pressed() -> void:
	var result: Dictionary = GameState.claim_expedition()
	if not bool(result.get("ok", false)):
		AudioManager.play("error")
		GameState.push_notice(str(result.get("message", "Nothing to claim.")), "warn")
		return

	AudioManager.play_with_haptic("arrive", 40)
	_result_credits = int(result.get("credits", 0))
	_result_ad_used = false
	_result_ad_button.disabled = _result_credits <= 0
	_result_ad_button.text = "WATCH SIMULATED AD (+%s)" % UiKit.credits(int(round(float(_result_credits) * 0.5)))

	var lines: Array[String] = []
	lines.append("%s hauled in %s." % [str(result.get("planet_name", "Ship")), UiKit.credits(_result_credits)])
	var items: Dictionary = result.get("items", {})
	for item_id in items:
		lines.append("- %dx %s" % [int(items[item_id]), str(Catalog.item(str(item_id)).get("name", item_id))])
	if bool(result.get("rare", false)):
		lines.append("Rare salvage recovered!")
	if int(result.get("overflow_credits", 0)) > 0:
		lines.append("Board was full: %s auto-sold." % UiKit.credits(int(result["overflow_credits"])))
	_result_body.text = "\n".join(lines)

	_result_overlay.visible = true
	_refresh()


func _on_result_ad_pressed() -> void:
	if _result_credits <= 0 or _result_ad_used:
		return
	_result_ad_button.disabled = true
	_result_ad_button.text = "PLAYING..."
	var granted: bool = await Monetization.watch_rewarded_ad("expedition_bonus")
	if granted and not _result_ad_used:
		var bonus: int = int(round(float(_result_credits) * 0.5))
		GameState.grant_expedition_bonus(bonus)
		_result_ad_used = true
		_result_body.text += "\nBonus salvage sold: +%s" % UiKit.credits(bonus)
		_result_ad_button.text = "BONUS GRANTED"
		AudioManager.play("buy")
	elif not granted:
		_result_ad_button.disabled = false
		_result_ad_button.text = "WATCH SIMULATED AD (+%s)" % UiKit.credits(int(round(float(_result_credits) * 0.5)))
		GameState.push_notice("No reward was granted.", "warn")


func _close_result() -> void:
	_result_overlay.visible = false
