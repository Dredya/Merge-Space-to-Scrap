extends RefCounted
## Shared visual language: palette, theme and reusable widget builders.
##
## Every screen uses these helpers so spacing, colours and touch-target sizes
## stay consistent across the game. Phase 0 of the UI redesign: expanded design
## tokens plus a few new reusable builders while keeping the old API intact.

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
const COLOR_BG := Color("#080e20")
const COLOR_BG_DEEP := Color("#050a18")
const COLOR_PANEL := Color("#151f3f")
const COLOR_PANEL_HI := Color("#1d2a52")
const COLOR_PANEL_ALT := Color("#1a2548")
const COLOR_BORDER := Color("#2c3d70")
const COLOR_BORDER_HI := Color("#3d5290")
const COLOR_TEXT := Color("#e9efff")
const COLOR_MUTED := Color("#93a4cc")
const COLOR_ACCENT := Color("#43e8ff")
const COLOR_ACCENT_DIM := Color("#1fb8cc")
const COLOR_GOLD := Color("#ffc857")
const COLOR_GOLD_DIM := Color("#b88a2f")
const COLOR_GOOD := Color("#57e389")
const COLOR_BAD := Color("#ff6b7a")
const COLOR_SHADOW := Color(0.0, 0.0, 0.0, 0.45)
const COLOR_GLOW := Color("#43e8ff")

# ---------------------------------------------------------------------------
# Spacing / sizing tokens
# ---------------------------------------------------------------------------
const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 16
const SPACE_XL := 24

const RADIUS_SM := 8
const RADIUS_MD := 14
const RADIUS_LG := 18
const RADIUS_XL := 22

const TOUCH_HEIGHT := 52
const TOUCH_MIN := 44

# ---------------------------------------------------------------------------
# Typography scale
# ---------------------------------------------------------------------------
const TEXT_XS := 11
const TEXT_SM := 13
const TEXT_MD := 16
const TEXT_LG := 20
const TEXT_XL := 24
const TEXT_XXL := 30


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = TEXT_MD

	theme.set_color("font_color", "Label", COLOR_TEXT)

	theme.set_stylebox("normal", "Button", _button_box(COLOR_PANEL_HI, COLOR_BORDER))
	theme.set_stylebox("hover", "Button", _button_box(COLOR_PANEL_HI.lightened(0.08), COLOR_ACCENT))
	theme.set_stylebox("pressed", "Button", _button_box(COLOR_PANEL.darkened(0.12), COLOR_ACCENT))
	theme.set_stylebox("disabled", "Button", _button_box(COLOR_PANEL.darkened(0.2), COLOR_BORDER.darkened(0.35)))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_ACCENT)
	theme.set_color("font_pressed_color", "Button", COLOR_ACCENT)
	theme.set_color("font_disabled_color", "Button", COLOR_MUTED)
	theme.set_font_size("font_size", "Button", TEXT_MD)

	theme.set_stylebox("panel", "PanelContainer", _panel_box())
	theme.set_stylebox("panel", "Panel", _panel_box())
	theme.set_stylebox("panel", "PopupPanel", _panel_box())
	theme.set_color("font_color", "RichTextLabel", COLOR_TEXT)

	return theme


static func label(text: String, size: int = TEXT_MD, color: Color = COLOR_TEXT, wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func button(text: String, size: int = TEXT_MD, accent: bool = false) -> Button:
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


static func icon_button(icon: String, size: int = TOUCH_MIN) -> Button:
	var node := Button.new()
	node.text = icon
	node.custom_minimum_size = Vector2(size, size)
	node.add_theme_font_size_override("font_size", TEXT_LG)
	return node


static func panel(padding: int = SPACE_MD, background: Color = COLOR_PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", _panel_box(background, padding))
	return node


static func card(padding: int = SPACE_MD, accent: Color = COLOR_BORDER) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", _card_box(COLOR_PANEL, padding, accent))
	return node


static func chip(text: String, color: Color = COLOR_ACCENT, size: int = TEXT_XS) -> PanelContainer:
	var wrapper := PanelContainer.new()
	wrapper.add_theme_stylebox_override("panel", _chip_box(color))
	var lbl := label(text, size, Color("#04121f") if color == COLOR_ACCENT or color == COLOR_GOLD else COLOR_TEXT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrapper.add_child(lbl)
	return wrapper


static func badge(text: String, color: Color = COLOR_ACCENT) -> PanelContainer:
	return chip(text, color, TEXT_XS)


static func section_header(text: String, size: int = TEXT_SM, color: Color = COLOR_MUTED) -> Label:
	var node := label(text, size, color)
	node.add_theme_color_override("font_color", color)
	return node


static func progress_bar(value: float = 0.0, max_value: float = 100.0, height: int = 8) -> ProgressBar:
	var node := ProgressBar.new()
	node.min_value = 0.0
	node.max_value = max_value
	node.value = value
	node.show_percentage = false
	node.custom_minimum_size = Vector2(0, height)
	return node


static func divider() -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, 1)
	node.modulate = COLOR_BORDER
	return node


static func vbox(separation: int = SPACE_SM) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = SPACE_SM) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func margin(child: Control, left: int = SPACE_LG, top: int = SPACE_SM, right: int = SPACE_LG, bottom: int = SPACE_SM) -> MarginContainer:
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
	style.set_corner_radius_all(RADIUS_MD)
	style.border_color = tint if occupied else Color("#22325c")
	style.set_border_width_all(2 if occupied else 1)
	style.shadow_color = COLOR_SHADOW
	style.shadow_size = 2
	return style


static func selected_box() -> StyleBoxFlat:
	return _button_box(COLOR_PANEL_HI, COLOR_ACCENT)


static func frame_style(background: Color = Color("#0d1630")) -> StyleBoxFlat:
	var style := _panel_box(background, SPACE_SM)
	style.border_color = Color("#22325c")
	style.shadow_size = 6
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


# ---------------------------------------------------------------------------
# Stylebox builders
# ---------------------------------------------------------------------------
static func _button_box(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(RADIUS_MD)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.shadow_color = COLOR_SHADOW
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


static func _panel_box(background: Color = COLOR_PANEL, padding: int = SPACE_MD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_LG)
	style.content_margin_left = float(padding)
	style.content_margin_right = float(padding)
	style.content_margin_top = float(padding)
	style.content_margin_bottom = float(padding)
	style.shadow_color = COLOR_SHADOW
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


static func _card_box(background: Color, padding: int, accent: Color) -> StyleBoxFlat:
	var style := _panel_box(background, padding)
	style.border_color = accent
	style.set_border_width_all(1)
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	style.shadow_size = 8
	return style


static func _chip_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_SM)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


static func _focus_box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(RADIUS_MD)
	return style
