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
var _bin_fill: Label
var _bin_timer: Label
var _board: Control
var _scrap_timer_label: Label
var _selection_label: Label
var _sell_button: Button
var _order_widgets: Array = []
var _orders_meta: Label
var _auto_deliver_toggle: CheckButton
var _refresh_timer: float = 0.0
var _ui_timer: float = 0.0


func _ready() -> void:
	_build()
	GameState.board_changed.connect(_refresh_selection)
	GameState.board_changed.connect(_refresh_orders)
	GameState.production_changed.connect(_refresh_production)
	GameState.generators_changed.connect(_refresh_production)
	GameState.orders_changed.connect(_refresh_orders)
	GameState.tutorial_changed.connect(_refresh_tutorial)
	GameState.settings_changed.connect(_sync_auto_deliver)
	_refresh_tutorial()
	_refresh_production()
	_refresh_selection()
	_refresh_orders()
	_sync_auto_deliver()
	set_process(true)


func on_show() -> void:
	_refresh_tutorial()
	_refresh_production()
	_refresh_selection()
	_refresh_orders()
	_sync_auto_deliver()


func _process(delta: float) -> void:
	_ui_timer += delta
	if _ui_timer >= 0.5:
		_ui_timer = 0.0
		_refresh_boost_label()
		if _scrap_timer_label != null:
			if GameState.free_slot_count() <= 0:
				_scrap_timer_label.text = "Board full"
			else:
				_scrap_timer_label.text = "Next scrap in %ds" % int(ceil(GameState.scrap_spawn_seconds_remaining()))

	_refresh_timer += delta
	if _refresh_timer >= 3.0:
		_refresh_timer = 0.0
		_refresh_orders()
		_refresh_selection()
	# pulse deliverable order cards
	for entry in _order_widgets:
		if not entry.has("card"):
			continue
		var card: PanelContainer = entry["card"]
		var index: int = int(entry["index"])
		var order: Dictionary = GameState.orders[index] if index < GameState.orders.size() else {}
		if not order.is_empty() and GameState.can_deliver_order(order):
			var pulse: float = 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.006)
			card.modulate = Color(pulse, pulse, pulse, 1.0)
		else:
			card.modulate = Color(1, 1, 1, 1)


# --- Construction -----------------------------------------------------------
func _build() -> void:
	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 6)
	page.add_theme_constant_override("margin_top", 6)
	page.add_theme_constant_override("margin_right", 6)
	page.add_theme_constant_override("margin_bottom", 6)
	add_child(page)

	var column := UiKit.vbox(8)
	page.add_child(column)

	_build_tutorial(column)
	_build_production(column)

	var scrap_timer_row := UiKit.hbox(6)
	_scrap_timer_label = UiKit.label("Next scrap in 10s", 12, UiKit.COLOR_ACCENT)
	scrap_timer_row.add_child(_scrap_timer_label)
	var scrap_spacer := Control.new()
	scrap_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrap_timer_row.add_child(scrap_spacer)
	column.add_child(scrap_timer_row)

	_board = MergeBoardScene.instantiate()
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 300)
	column.add_child(_board)

	_build_selection(column)
	_build_orders(column)


func _build_tutorial(column: VBoxContainer) -> void:
	_tutorial_panel = UiKit.card(8, UiKit.COLOR_ACCENT_DIM)
	var row := UiKit.hbox(8)
	_tutorial_panel.add_child(row)

	_tutorial_label = UiKit.label("", 13, UiKit.COLOR_ACCENT, true)
	_tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_tutorial_label)

	_tutorial_progress = UiKit.label("", 13, UiKit.COLOR_GOLD)
	row.add_child(_tutorial_progress)
	column.add_child(_tutorial_panel)


func _build_production(column: VBoxContainer) -> void:
	var production := UiKit.card(9, UiKit.COLOR_BORDER_HI)
	var body := UiKit.vbox(6)
	production.add_child(body)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.section_header("SALVAGE LINE", 13, UiKit.COLOR_MUTED))
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

	# Auto-spawn: items appear on the board as they are produced.

	column.add_child(production)


func _build_generator_widget(definition: Dictionary) -> Control:
	var card := UiKit.card(6, UiKit.COLOR_BORDER)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := UiKit.vbox(2)
	card.add_child(body)

	var title := UiKit.label(str(definition.get("short", "")), 12, UiKit.COLOR_TEXT)
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
	var selection := UiKit.card(7, UiKit.COLOR_BORDER)
	var row := UiKit.hbox(8)
	selection.add_child(row)

	_selection_label = UiKit.label("Tap an item to inspect it.", 13, UiKit.COLOR_MUTED, true)
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_selection_label)

	_sell_button = UiKit.button("SELL", 15)
	_sell_button.custom_minimum_size = Vector2(112, 48)
	_sell_button.disabled = true
	_sell_button.pressed.connect(_on_sell_pressed)
	row.add_child(_sell_button)

	column.add_child(selection)


func _build_orders(column: VBoxContainer) -> void:
	var orders := UiKit.card(8, UiKit.COLOR_BORDER_HI)
	var body := UiKit.vbox(6)
	orders.add_child(body)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.section_header("WORKSHOP ORDERS", 13, UiKit.COLOR_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	_auto_deliver_toggle = CheckButton.new()
	_auto_deliver_toggle.text = "Auto-deliver"
	_auto_deliver_toggle.custom_minimum_size = Vector2(0, 44)
	_auto_deliver_toggle.add_theme_font_size_override("font_size", 11)
	_auto_deliver_toggle.toggled.connect(func(value: bool) -> void: GameState.set_auto_deliver(value))

	_orders_meta = UiKit.label("", 12, UiKit.COLOR_MUTED)
	head.add_child(_orders_meta)
	head.add_child(_auto_deliver_toggle)
	body.add_child(head)

	var row := UiKit.hbox(8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	for index in Catalog.ORDER_SLOTS:
		var card := _build_order_card(index)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 150)
		row.add_child(card)

	column.add_child(orders)


func _build_order_card(index: int) -> Control:
	var card := UiKit.card(6, UiKit.COLOR_BORDER)
	card.custom_minimum_size = Vector2(168, 0)
	var body := UiKit.vbox(4)
	card.add_child(body)

	var head := UiKit.hbox(8)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(40, 40)
	head.add_child(icon)
	var name_label := UiKit.label("", 12, Color("#dfe8ff"), true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var tier_label := UiKit.label("", 11, UiKit.COLOR_MUTED)
	head.add_child(tier_label)
	body.add_child(head)

	var progress := UiKit.label("", 11, UiKit.COLOR_MUTED)
	body.add_child(progress)
	var reward := UiKit.label("", 12, UiKit.COLOR_GOLD)
	body.add_child(reward)

	var progress_bar := UiKit.progress_bar(0.0, 1.0, 8)
	body.add_child(progress_bar)

	var button := UiKit.button("DELIVER", 12)
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(_on_deliver_pressed.bind(index))
	body.add_child(button)

	_order_widgets.append({
		"index": index,
		"name": name_label,
		"progress": progress,
		"reward": reward,
		"button": button,
		"card": card,
		"icon": icon,
		"progress_bar": progress_bar,
		"tier": tier_label,
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
	var total_capacity: int = 0
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
		total_capacity += capacity

		entry["title"].text = "%s L%d" % [str(definition.get("short", "")), level]
		entry["rate"].text = "%.0fs each" % interval
		entry["pending"].text = "%d/%d" % [pending, capacity]
		entry["pending"].add_theme_color_override(
			"font_color",
			UiKit.COLOR_BAD if pending >= capacity else UiKit.COLOR_GOLD
		)
		card.modulate = Color(1, 1, 1, 1)

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
	_selection_label.text = "%s  ·  %s" % [
		str(definition.get("name", "")),
		UiKit.credits(int(definition.get("sell_value", 0))),
	]
	_selection_label.add_theme_color_override("font_color", UiKit.COLOR_TEXT)
	_sell_button.disabled = false
	_sell_button.text = "Sell · %s" % UiKit.credits(int(definition.get("sell_value", 0)))


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
			entry["progress_bar"].value = 0
			if entry.has("tier"):
				entry["tier"].text = ""
			entry["card"].modulate = Color(1, 1, 1, 0.6)
			# clear icon
			for c in entry["icon"].get_children():
				c.queue_free()
			continue

		var item_id: String = str(order.get("item_id", ""))
		var definition: Dictionary = Catalog.item(item_id)
		var have: int = GameState.item_count(item_id)
		var qty: int = int(order.get("qty", 1))
		entry["name"].text = str(definition.get("name", "?"))
		entry["progress"].text = "%d on board (need %d)" % [have, qty]
		entry["reward"].text = "+%s" % UiKit.credits(int(order.get("reward", 0)))
		entry["button"].disabled = not GameState.can_deliver_order(order)
		entry["progress_bar"].max_value = qty
		entry["progress_bar"].value = mini(have, qty)

		var order_tier: int = clampi(int(order.get("tier", 1)), 1, 3)
		var tier_names := ["", "EASY", "MED", "HARD"]
		var tier_colors := [UiKit.COLOR_MUTED, UiKit.COLOR_GOOD, UiKit.COLOR_ACCENT, UiKit.COLOR_BAD]
		entry["tier"].text = tier_names[order_tier]
		entry["tier"].add_theme_color_override("font_color", tier_colors[order_tier])

		# large icon
		for c in entry["icon"].get_children():
			c.queue_free()
		var item_icon = preload("res://scenes/workshop/merge_item.tscn").instantiate()
		entry["icon"].add_child(item_icon)
		item_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_icon.setup(item_id)

		# pulse deliverable
		if GameState.can_deliver_order(order):
			entry["card"].modulate = Color(1.0, 1.0, 1.0, 1.0)
			# add a tween pulse if not already
		else:
			entry["card"].modulate = Color(1, 1, 1, 0.85)


func _sync_auto_deliver() -> void:
	if _auto_deliver_toggle == null:
		return
	_auto_deliver_toggle.set_pressed_no_signal(bool(GameState.settings.get("auto_deliver", false)))


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
