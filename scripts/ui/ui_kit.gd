extends RefCounted
## Shared visual language: palette, theme and reusable widget builders.
##
## Every screen uses these helpers so spacing, colours and touch-target sizes
## stay consistent across the game.

const COLOR_BG := Color("#080e20")
const COLOR_PANEL := Color("#151f3f")
const COLOR_PANEL_HI := Color("#1d2a52")
const COLOR_BORDER := Color("#2c3d70")
const COLOR_TEXT := Color("#e9efff")
const COLOR_MUTED := Color("#93a4cc")
const COLOR_ACCENT := Color("#43e8ff")
const COLOR_GOLD := Color("#ffc857")
const COLOR_GOOD := Color("#57e389")
const COLOR_BAD := Color("#ff6b7a")

const TOUCH_HEIGHT := 52


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20

	theme.set_color("font_color", "Label", COLOR_TEXT)

	theme.set_stylebox("normal", "Button", _button_box(COLOR_PANEL_HI, COLOR_BORDER))
	theme.set_stylebox("hover", "Button", _button_box(COLOR_PANEL_HI.lightened(0.08), COLOR_ACCENT))
	theme.set_stylebox("pressed", "Button", _button_box(COLOR_PANEL.darkened(0.12), COLOR_ACCENT))
	theme.set_stylebox("disabled", "Button", _button_box(COLOR_PANEL.darkened(0.2), COLOR_BORDER.darkened(0.35)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_ACCENT)
	theme.set_color("font_pressed_color", "Button", COLOR_ACCENT)
	theme.set_color("font_disabled_color", "Button", COLOR_MUTED)
	theme.set_font_size("font_size", "Button", 20)

	theme.set_stylebox("panel", "PanelContainer", _panel_box())
	theme.set_stylebox("panel", "Panel", _panel_box())
	theme.set_stylebox("panel", "PopupPanel", _panel_box())
	theme.set_color("font_color", "RichTextLabel", COLOR_TEXT)

	return theme


static func label(text: String, size: int = 20, color: Color = COLOR_TEXT, wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func button(text: String, size: int = 20, accent: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0, TOUCH_HEIGHT)
	node.add_theme_font_size_override("font_size", size)
	if accent:
		node.add_theme_stylebox_override("normal", _button_box(COLOR_ACCENT, COLOR_ACCENT))
		node.add_theme_stylebox_override("hover", _button_box(COLOR_ACCENT.lightened(0.15), COLOR_ACCENT.lightened(0.2)))
		node.add_theme_stylebox_override("pressed", _button_box(COLOR_ACCENT.darkened(0.15), COLOR_ACCENT))
		node.add_theme_color_override("font_color", Color("#04121f"))
		node.add_theme_color_override("font_hover_color", Color("#04121f"))
		node.add_theme_color_override("font_pressed_color", Color("#04121f"))
	return node


static func panel(padding: int = 12, background: Color = COLOR_PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", _panel_box(background, padding))
	return node


static func vbox(separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func margin(child: Control, left: int = 14, top: int = 10, right: int = 14, bottom: int = 10) -> MarginContainer:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", left)
	wrapper.add_theme_constant_override("margin_top", top)
	wrapper.add_theme_constant_override("margin_right", right)
	wrapper.add_theme_constant_override("margin_bottom", bottom)
	wrapper.add_child(child)
	return wrapper


static func spacer(height: int, expand: bool = false) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	if expand:
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node


static func slot_style(occupied: bool, tint: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0d1630") if not occupied else Color("#111d3c")
	style.set_corner_radius_all(10)
	style.border_color = tint if occupied else Color("#22325c")
	style.set_border_width_all(2 if occupied else 1)
	return style


static func selected_box() -> StyleBoxFlat:
	return _button_box(COLOR_PANEL_HI, COLOR_ACCENT)


static func frame_style(background: Color = Color("#0d1630")) -> StyleBoxFlat:
	var style := _panel_box(background, 10)
	style.border_color = Color("#22325c")
	return style


static func format_number(value: int) -> String:
	var negative: bool = value < 0
	var digits: String = str(absi(value))
	var formatted: String = ""
	var count: int = 0
	for index in range(digits.length() - 1, -1, -1):
		formatted = digits[index] + formatted
		count += 1
		if count % 3 == 0 and index > 0:
			formatted = "," + formatted
	return ("-" if negative else "") + formatted


static func credits(value: int) -> String:
	return "%s cr" % format_number(value)


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


static func _button_box(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


static func _panel_box(background: Color = COLOR_PANEL, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = float(padding)
	style.content_margin_right = float(padding)
	style.content_margin_top = float(padding)
	style.content_margin_bottom = float(padding)
	return style
