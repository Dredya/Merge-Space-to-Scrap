extends Control
## Main workshop screen: production strip, merge board, selection bar and
## workshop orders. Purely presentational - all rules live in GameState.

signal request_screen(screen_id: String)

const Catalog = preload("res://scripts/data/game_catalog.gd")
const EconomyRules = preload("res://scripts/logic/economy_rules.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const MergeBoardScene = preload("res://scenes/workshop/merge_board.tscn")

var _tutorial_panel: PanelContainer
var _tutorial_label: Label
var _tutorial_progress: Label
var _generator_widgets: Array = []
var _collect_button: Button
var _boost_label: Label
var _board: Control
var _selection_label: Label
var _sell_button: Button
var _order_widgets: Array = []
var _orders_meta: Label
var _ui_timer: float = 0.0


func _ready() -> void:
	_build()
	GameState.board_changed.connect(_refresh_selection)
	GameState.production_changed.connect(_refresh_production)
	GameState.generators_changed.connect(_refresh_production)
	GameState.orders_changed.connect(_refresh_orders)
	GameState.tutorial_changed.connect(_refresh_tutorial)
	_refresh_tutorial()
	_refresh_production()
	_refresh_selection()
	_refresh_orders()
	set_process(true)


func on_show() -> void:
	_refresh_tutorial()
	_refresh_production()
	_refresh_selection()
	_refresh_orders()


func _process(delta: float) -> void:
	_ui_timer += delta
	if _ui_timer >= 0.5:
		_ui_timer = 0.0
		_refresh_boost_label()


# --- Construction -----------------------------------------------------------
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

	_build_tutorial(column)
	_build_production(column)

	_board = MergeBoardScene.instantiate()
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 240)
	column.add_child(_board)

	_build_selection(column)
	_build_orders(column)


func _build_tutorial(column: VBoxContainer) -> void:
	_tutorial_panel = UiKit.panel(8, Color("#16223f"))
	var row := UiKit.hbox(8)
	_tutorial_panel.add_child(row)

	_tutorial_label = UiKit.label("", 12, UiKit.COLOR_ACCENT, true)
	_tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_tutorial_label)

	_tutorial_progress = UiKit.label("", 13, UiKit.COLOR_MUTED)
	row.add_child(_tutorial_progress)
	column.add_child(_tutorial_panel)


func _build_production(column: VBoxContainer) -> void:
	var production := UiKit.panel(9)
	var body := UiKit.vbox(6)
	production.add_child(body)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.label("SALVAGE LINE", 13, UiKit.COLOR_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_boost_label = UiKit.label("", 12, UiKit.COLOR_GOLD)
	head.add_child(_boost_label)
	body.add_child(head)

	var generator_row := UiKit.hbox(6)
	for definition in Catalog.GENERATOR_DEFS:
		generator_row.add_child(_build_generator_widget(definition))
	body.add_child(generator_row)

	_collect_button = UiKit.button("COLLECT", 18, true)
	_collect_button.custom_minimum_size = Vector2(0, 46)
	_collect_button.pressed.connect(_on_collect_pressed)
	body.add_child(_collect_button)

	column.add_child(production)


func _build_generator_widget(definition: Dictionary) -> Control:
	var card := UiKit.panel(6, Color("#101a34"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := UiKit.vbox(1)
	card.add_child(body)

	var title := UiKit.label(str(definition.get("short", "")), 12, Color("#dfe8ff"))
	body.add_child(title)
	var rate := UiKit.label("", 11, UiKit.COLOR_ACCENT)
	body.add_child(rate)
	var pending := UiKit.label("", 12, UiKit.COLOR_GOLD)
	body.add_child(pending)

	_generator_widgets.append({
		"definition": definition,
		"card": card,
		"title": title,
		"rate": rate,
		"pending": pending,
	})
	return card


func _build_selection(column: VBoxContainer) -> void:
	var selection := UiKit.panel(7)
	var row := UiKit.hbox(8)
	selection.add_child(row)

	_selection_label = UiKit.label("Tap an item to inspect it.", 13, UiKit.COLOR_MUTED, true)
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_selection_label)

	_sell_button = UiKit.button("SELL", 15)
	_sell_button.custom_minimum_size = Vector2(104, 46)
	_sell_button.disabled = true
	_sell_button.pressed.connect(_on_sell_pressed)
	row.add_child(_sell_button)

	column.add_child(selection)


func _build_orders(column: VBoxContainer) -> void:
	var orders := UiKit.panel(8)
	var body := UiKit.vbox(6)
	orders.add_child(body)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.label("WORKSHOP ORDERS", 13, UiKit.COLOR_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_orders_meta = UiKit.label("", 12, UiKit.COLOR_MUTED)
	head.add_child(_orders_meta)
	body.add_child(head)

	var row := UiKit.hbox(6)
	for index in Catalog.ORDER_SLOTS:
		row.add_child(_build_order_card(index))
	body.add_child(row)

	column.add_child(orders)


func _build_order_card(index: int) -> Control:
	var card := UiKit.panel(6, Color("#101a34"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := UiKit.vbox(2)
	card.add_child(body)

	var name_label := UiKit.label("", 11, Color("#dfe8ff"), true)
	name_label.custom_minimum_size = Vector2(0, 30)
	body.add_child(name_label)
	var progress := UiKit.label("", 10, UiKit.COLOR_MUTED)
	body.add_child(progress)
	var reward := UiKit.label("", 11, UiKit.COLOR_GOLD)
	body.add_child(reward)

	var button := UiKit.button("DELIVER", 11)
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(_on_deliver_pressed.bind(index))
	body.add_child(button)

	_order_widgets.append({
		"index": index,
		"name": name_label,
		"progress": progress,
		"reward": reward,
		"button": button,
	})
	return card


# --- Refresh ----------------------------------------------------------------
func _refresh_tutorial() -> void:
	if GameState.tutorial_active():
		_tutorial_panel.visible = true
		_tutorial_label.text = GameState.tutorial_text()
		_tutorial_progress.text = GameState.tutorial_progress_text()
	else:
		_tutorial_panel.visible = false


func _refresh_boost_label() -> void:
	if _boost_label == null:
		return
	var remaining: float = GameState.boost_seconds_remaining()
	if remaining <= 0.0:
		_boost_label.text = ""
		return
	_boost_label.text = "OVERDRIVE %d:%02d" % [int(remaining) / 60, int(remaining) % 60]


func _refresh_production() -> void:
	if _generator_widgets.is_empty():
		return
	var total_pending: int = 0
	for entry in _generator_widgets:
		var definition: Dictionary = entry["definition"]
		var state: Dictionary = GameState.generators.get(str(definition["id"]), {})
		var level: int = int(state.get("level", 0))
		var card: PanelContainer = entry["card"]

		if level <= 0:
			entry["title"].text = str(definition.get("short", ""))
			entry["rate"].text = "not built"
			entry["pending"].text = "---"
			card.modulate = Color(1, 1, 1, 0.5)
			continue

		var interval: float = EconomyRules.generator_interval(definition, level)
		var capacity: int = EconomyRules.generator_capacity(definition, level)
		var pending: int = int(state.get("pending", 0))
		total_pending += pending

		entry["title"].text = "%s L%d" % [str(definition.get("short", "")), level]
		entry["rate"].text = "%.0fs each" % interval
		entry["pending"].text = "%d/%d" % [pending, capacity]
		entry["pending"].add_theme_color_override(
			"font_color",
			UiKit.COLOR_BAD if pending >= capacity else UiKit.COLOR_GOLD
		)
		card.modulate = Color(1, 1, 1, 1)

	_collect_button.text = "COLLECT (%d)" % total_pending if total_pending > 0 else "COLLECT"
	_collect_button.disabled = total_pending <= 0
	_refresh_boost_label()


func _refresh_selection() -> void:
	if _selection_label == null:
		return
	var item_id: Variant = GameState.selected_item()
	if item_id == null:
		_selection_label.text = "Tap an item to inspect it."
		_selection_label.add_theme_color_override("font_color", UiKit.COLOR_MUTED)
		_sell_button.disabled = true
		_sell_button.text = "SELL"
		return

	var definition: Dictionary = Catalog.item(str(item_id))
	_selection_label.text = "%s - sells for %s" % [
		str(definition.get("name", "")),
		UiKit.credits(int(definition.get("sell_value", 0))),
	]
	_selection_label.add_theme_color_override("font_color", UiKit.COLOR_TEXT)
	_sell_button.disabled = false
	_sell_button.text = "SELL"


func _refresh_orders() -> void:
	_orders_meta.text = "%d completed" % int(GameState.stats.get("orders_completed", 0))
	for entry in _order_widgets:
		var index: int = int(entry["index"])
		var order: Dictionary = GameState.orders[index] if index < GameState.orders.size() else {}
		if order.is_empty():
			entry["name"].text = "-"
			entry["progress"].text = ""
			entry["reward"].text = ""
			entry["button"].disabled = true
			continue

		var definition: Dictionary = Catalog.item(str(order.get("item_id", "")))
		var have: int = GameState.item_count(str(order.get("item_id", "")))
		entry["name"].text = str(definition.get("name", "?"))
		entry["progress"].text = "%d/%d ready" % [mini(have, int(order.get("qty", 1))), int(order.get("qty", 1))]
		entry["reward"].text = "+%s" % UiKit.credits(int(order.get("reward", 0)))
		entry["button"].disabled = not GameState.can_deliver_order(order)


# --- Actions ----------------------------------------------------------------
func _on_collect_pressed() -> void:
	var result: Dictionary = GameState.collect_production()
	if int(result.get("collected", 0)) > 0:
		AudioManager.play_with_haptic("collect")
	elif int(result.get("blocked", 0)) > 0:
		AudioManager.play("error")


func _on_sell_pressed() -> void:
	var result: Dictionary = GameState.sell_selected()
	if bool(result.get("ok", false)):
		AudioManager.play("buy")
		GameState.push_notice("Sold for %s." % UiKit.credits(int(result.get("credits", 0))), "good")
	else:
		AudioManager.play("error")
		GameState.push_notice(str(result.get("message", "Cannot sell that.")), "warn")


func _on_deliver_pressed(index: int) -> void:
	var result: Dictionary = GameState.deliver_order(index)
	if bool(result.get("ok", false)):
		AudioManager.play_with_haptic("order", 30)
		GameState.push_notice("Order delivered: +%s." % UiKit.credits(int(result.get("reward", 0))), "good")
	else:
		AudioManager.play("error")
		GameState.push_notice(str(result.get("message", "Order not ready.")), "warn")
