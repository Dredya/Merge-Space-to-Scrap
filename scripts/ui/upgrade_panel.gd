extends Control
## Upgrades screen: production machines, board expansion and the optional
## simulated-ad salvage overdrive.

const Catalog = preload("res://scripts/data/game_catalog.gd")
const EconomyRules = preload("res://scripts/logic/economy_rules.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

var _credits_label: Label
var _generator_widgets: Array = []
var _expansion_info: Label
var _expansion_button: Button
var _ad_status: Label
var _ad_button: Button


func _ready() -> void:
	_build()
	GameState.credits_changed.connect(_on_credits_changed)
	GameState.generators_changed.connect(_refresh)
	GameState.production_changed.connect(_refresh_boost_only)
	GameState.ad_changed.connect(_refresh_ad_status)
	_refresh()
	set_process(true)


func on_show() -> void:
	_refresh()

var _ad_timer: float = 0.0
func _process(delta: float) -> void:
	_ad_timer += delta
	if _ad_timer >= 1.0:
		_ad_timer = 0.0
		_refresh_ad_status()


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
	var title := UiKit.label("Salvage Upgrades", 20, UiKit.COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var credits_chip := UiKit.chip(UiKit.credits(GameState.credits), UiKit.COLOR_GOLD)
	_credits_label = credits_chip.get_child(0) as Label
	_credits_label.add_theme_font_size_override("font_size", 15)
	header.add_child(credits_chip)
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var cards := UiKit.vbox(8)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)

	for definition in Catalog.GENERATOR_DEFS:
		cards.add_child(_build_generator_card(definition))

	cards.add_child(_build_expansion_card())
	cards.add_child(_build_ad_card())


func _build_generator_card(definition: Dictionary) -> Control:
	var card := UiKit.card(10, UiKit.COLOR_BORDER)
	var body := UiKit.vbox(4)
	card.add_child(body)

	var head := UiKit.hbox(8)
	var name_label := UiKit.label(str(definition.get("name", "")), 16, UiKit.COLOR_TEXT, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var level_label := UiKit.label("", 14, UiKit.COLOR_ACCENT)
	head.add_child(level_label)
	body.add_child(head)

	var blurb := UiKit.label(str(definition.get("blurb", "")), 12, UiKit.COLOR_MUTED, true)
	body.add_child(blurb)

	var info := UiKit.label("", 12, UiKit.COLOR_ACCENT)
	body.add_child(info)

	var foot := UiKit.hbox(8)
	var requirement := UiKit.label("", 11, UiKit.COLOR_MUTED, true)
	requirement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(requirement)
	var button := UiKit.button("UPGRADE", 14)
	button.custom_minimum_size = Vector2(168, 46)
	button.pressed.connect(_on_upgrade_pressed.bind(str(definition["id"])))
	foot.add_child(button)
	body.add_child(foot)

	_generator_widgets.append({
		"definition": definition,
		"level": level_label,
		"info": info,
		"requirement": requirement,
		"button": button,
	})
	return card


func _build_expansion_card() -> Control:
	var card := UiKit.card(10, UiKit.COLOR_ACCENT_DIM)
	var body := UiKit.vbox(4)
	card.add_child(body)

	body.add_child(UiKit.label("Board Expansion", 16, UiKit.COLOR_TEXT))
	body.add_child(UiKit.label("Extra rows for the merge board. Every slot counts.", 12, UiKit.COLOR_MUTED, true))

	_expansion_info = UiKit.label("", 12, UiKit.COLOR_ACCENT)
	body.add_child(_expansion_info)

	_expansion_button = UiKit.button("EXPAND", 14)
	_expansion_button.custom_minimum_size = Vector2(0, 46)
	_expansion_button.pressed.connect(_on_expand_pressed)
	body.add_child(_expansion_button)
	return card


func _build_ad_card() -> Control:
	var card := UiKit.card(10, UiKit.COLOR_GOLD_DIM)
	var body := UiKit.vbox(4)
	card.add_child(body)

	body.add_child(UiKit.label("Salvage Overdrive", 16, UiKit.COLOR_TEXT))
	body.add_child(UiKit.label(
		"Doubles production for 5 minutes. Rewarded through a simulated ad in this build.",
		12, UiKit.COLOR_MUTED, true
	))

	_ad_status = UiKit.label("", 12, UiKit.COLOR_GOLD)
	body.add_child(_ad_status)

	_ad_button = UiKit.button("WATCH SIMULATED AD", 14)
	_ad_button.custom_minimum_size = Vector2(0, 46)
	_ad_button.pressed.connect(_on_watch_ad_pressed)
	body.add_child(_ad_button)
	return card


# --- Refresh ----------------------------------------------------------------
func _on_credits_changed(value: int) -> void:
	_credits_label.text = UiKit.credits(value)
	_refresh()


func _refresh_boost_only() -> void:
	_refresh_ad_status()


func _refresh() -> void:
	if _generator_widgets.is_empty():
		return
	_credits_label.text = UiKit.credits(GameState.credits)
	var levels: Dictionary = GameState.generator_levels()

	for entry in _generator_widgets:
		var definition: Dictionary = entry["definition"]
		var generator_id: String = str(definition["id"])
		var level: int = int(levels.get(generator_id, 0))
		var button: Button = entry["button"]
		var requirement: Label = entry["requirement"]

		if level <= 0:
			entry["level"].text = "NOT BUILT"
			entry["info"].text = "Produces %s" % str(Catalog.item(str(definition["item"])).get("name", "scrap"))
		else:
			var interval: float = EconomyRules.generator_interval(definition, level)
			var capacity: int = EconomyRules.generator_capacity(definition, level)
			entry["level"].text = "LEVEL %d" % level
			entry["info"].text = "1 item every %.1fs - holds %d" % [interval, capacity]

		if level >= Catalog.MAX_GENERATOR_LEVEL:
			button.text = "MAX LEVEL"
			button.disabled = true
			requirement.text = "Fully upgraded."
			continue

		var cost: int = EconomyRules.generator_upgrade_cost(definition, level)
		button.text = "%s  %s" % ["BUILD" if level <= 0 else "UPGRADE", UiKit.credits(cost)]
		var met: bool = EconomyRules.generator_requirements_met(definition, levels)
		var ship_requires: Dictionary = definition.get("ship_requires", {})
		var ship_met: bool = true
		var ship_text: String = ""
		for part_id in ship_requires:
			if GameState.part_level(str(part_id)) < int(ship_requires[part_id]):
				ship_met = false
				var part_name: String = str(Catalog.ship_part_def(str(part_id)).get("name", part_id))
				ship_text = "Requires %s Lv %d" % [part_name, int(ship_requires[part_id])]
				break
		if not met:
			button.disabled = true
			requirement.text = "Requires %s" % EconomyRules.generator_requirement_text(definition)
		elif not ship_met:
			button.disabled = true
			requirement.text = ship_text
		else:
			button.disabled = GameState.credits < cost
			requirement.text = "" if GameState.credits >= cost else "Need %s more" % UiKit.credits(cost - GameState.credits)

	_refresh_expansion()
	_refresh_ad_status()


func _refresh_expansion() -> void:
	if not GameState.can_expand():
		_expansion_info.text = "Board fully expanded: %d slots." % GameState.board_size()
		_expansion_button.text = "MAX SIZE"
		_expansion_button.disabled = true
		return

	var cost: int = GameState.next_expansion_cost()
	var rows: int = EconomyRules.expansion_rows(GameState.expansions_bought)
	_expansion_info.text = "Currently %d slots (%d rows) - next: %d slots (%d rows)" % [
		GameState.board_size(), GameState.board_rows, rows * Catalog.BOARD_COLUMNS, rows
	]
	_expansion_button.text = "EXPAND  %s" % UiKit.credits(cost)
	_expansion_button.disabled = GameState.credits < cost


func _refresh_ad_status() -> void:
	if _ad_status == null:
		return
	var remaining: float = GameState.boost_seconds_remaining()
	if remaining > 0.0:
		_ad_status.text = "Overdrive active: %d:%02d remaining" % [int(remaining) / 60, int(remaining) % 60]
	else:
		_ad_status.text = "Inactive"

	if not Monetization.ads_available():
		_ad_button.disabled = true
		_ad_button.text = "ADS UNAVAILABLE"
	elif Monetization.is_busy():
		_ad_button.disabled = true
		_ad_button.text = "PLAYING..."
	else:
		_ad_button.disabled = false
		_ad_button.text = "WATCH SIMULATED AD"


# --- Actions ----------------------------------------------------------------
func _on_upgrade_pressed(generator_id: String) -> void:
	var result: Dictionary = GameState.upgrade_generator(generator_id)
	if bool(result.get("ok", false)):
		AudioManager.play_with_haptic("buy", 30)
	else:
		AudioManager.play("error")
		GameState.push_notice(str(result.get("message", "Cannot upgrade.")), "warn")


func _on_expand_pressed() -> void:
	var result: Dictionary = GameState.buy_expansion()
	if bool(result.get("ok", false)):
		AudioManager.play_with_haptic("buy", 30)
	else:
		AudioManager.play("error")
		GameState.push_notice(str(result.get("message", "Cannot expand.")), "warn")


func _on_watch_ad_pressed() -> void:
	_ad_button.disabled = true
	_ad_button.text = "PLAYING..."
	var granted: bool = await Monetization.watch_rewarded_ad("production_boost")
	if granted:
		GameState.apply_production_boost()
		AudioManager.play("buy")
	else:
		GameState.push_notice("No reward was granted.", "warn")
	_refresh_ad_status()
