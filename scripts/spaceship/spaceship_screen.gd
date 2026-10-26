extends Control
## Spaceship screen: the ship illustration plus build/upgrade cards for every
## required component.

signal request_screen(screen_id: String)

const Catalog = preload("res://scripts/data/game_catalog.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const ShipViewScript = preload("res://scripts/spaceship/ship_view.gd")

var _part_widgets: Array = []
var _summary: Label
var _ship_view: Control
var _travel_button: Button


func _ready() -> void:
	_build()
	GameState.ship_changed.connect(_refresh)
	GameState.credits_changed.connect(_on_credits_changed)
	GameState.board_changed.connect(_refresh)
	_refresh()


func on_show() -> void:
	_refresh()


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
	var title := UiKit.label("Starship", 20, UiKit.COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_summary = UiKit.label("", 12, UiKit.COLOR_MUTED)
	header.add_child(_summary)
	column.add_child(header)

	var ship_panel := UiKit.card(6, UiKit.COLOR_ACCENT_DIM)
	ship_panel.custom_minimum_size = Vector2(0, 270)
	_ship_view = ShipViewScript.new()
	ship_panel.add_child(_ship_view)
	column.add_child(ship_panel)

	_travel_button = UiKit.button("OPEN TRAVEL", 16, true)
	_travel_button.custom_minimum_size = Vector2(0, 48)
	_travel_button.pressed.connect(func() -> void: request_screen.emit("expedition"))
	column.add_child(_travel_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var cards := UiKit.vbox(8)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)

	for definition in Catalog.SHIP_PART_DEFS:
		cards.add_child(_build_part_card(definition))


func _build_part_card(definition: Dictionary) -> Control:
	var card := UiKit.card(10, UiKit.COLOR_BORDER)
	var body := UiKit.vbox(3)
	card.add_child(body)

	var head := UiKit.hbox(8)
	var name_label := UiKit.label(str(definition.get("name", "")), 16, definition.get("color", UiKit.COLOR_TEXT))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var level_label := UiKit.label("", 13, UiKit.COLOR_ACCENT)
	head.add_child(level_label)
	body.add_child(head)

	body.add_child(UiKit.label(str(definition.get("blurb", "")), 11, UiKit.COLOR_MUTED, true))

	var effect := UiKit.label("", 11, UiKit.COLOR_GOOD)
	body.add_child(effect)

	var next := UiKit.label("", 11, UiKit.COLOR_GOLD, true)
	body.add_child(next)

	var button := UiKit.button("BUILD", 14)
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(_on_build_pressed.bind(str(definition["id"])))
	body.add_child(button)

	_part_widgets.append({
		"definition": definition,
		"level": level_label,
		"effect": effect,
		"next": next,
		"button": button,
	})
	return card


func _on_credits_changed(_value: int) -> void:
	_refresh()


func _refresh() -> void:
	if _part_widgets.is_empty():
		return

	var total_levels: int = 0
	for entry in _part_widgets:
		var definition: Dictionary = entry["definition"]
		var part_id: String = str(definition["id"])
		var level: int = GameState.part_level(part_id)
		total_levels += level

		entry["level"].text = "LV %d/%d" % [level, int(definition.get("max_level", Catalog.PART_MAX_LEVEL))]
		entry["effect"].text = GameState.part_current_effect(part_id)

		var cost: Dictionary = GameState.next_part_upgrade(part_id)
		var button: Button = entry["button"]
		if cost.is_empty():
			entry["next"].text = "Fully upgraded."
			entry["next"].add_theme_color_override("font_color", UiKit.COLOR_GOOD)
			button.text = "MAX LEVEL"
			button.disabled = true
			continue

		var requirements: Array[String] = [UiKit.credits(int(cost.get("credits", 0)))]
		var cost_items: Dictionary = cost.get("items", {})
		for item_id in cost_items:
			var item_name: String = str(Catalog.item(str(item_id)).get("name", item_id))
			var have: int = GameState.item_count(str(item_id))
			var need: int = int(cost_items[item_id])
			requirements.append("%dx %s (%d on board)" % [need, item_name, have])

		entry["next"].text = "Next: %s - %s" % [str(cost.get("effect", "")), ", ".join(requirements)]

		var check: Dictionary = GameState.can_build_part(part_id)
		button.disabled = not bool(check.get("ok", false))
		button.text = "BUILD  %s" % UiKit.credits(int(cost.get("credits", 0)))
		entry["next"].add_theme_color_override(
			"font_color",
			UiKit.COLOR_GOLD if bool(check.get("ok", false)) else UiKit.COLOR_MUTED
		)

	var max_total: int = Catalog.SHIP_PART_DEFS.size() * Catalog.PART_MAX_LEVEL
	_summary.text = "Ship integrity %d/%d" % [total_levels, max_total]
	_travel_button.disabled = false


func _on_build_pressed(part_id: String) -> void:
	var result: Dictionary = GameState.build_part(part_id)
	if bool(result.get("ok", false)):
		AudioManager.play_with_haptic("buy", 40)
	else:
		AudioManager.play("error")
		GameState.push_notice(str(result.get("message", "Cannot build that yet.")), "warn")
