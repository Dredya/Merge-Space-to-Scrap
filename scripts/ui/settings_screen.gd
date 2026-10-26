extends Control
## Settings overlay: audio volume, haptics, saving and progress reset.

signal closed

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var _music_slider: HSlider
var _sfx_slider: HSlider
var _haptics_toggle: CheckButton
var _auto_deliver_toggle_ref: CheckButton
var _version_label: Label
var _reset_dialog: ConfirmationDialog


func _ready() -> void:
	_build()
	GameState.settings_changed.connect(_sync)
	_sync()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UiKit.card(18, UiKit.COLOR_BORDER_HI)
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)

	var body := UiKit.vbox(12)
	panel.add_child(body)

	var head := UiKit.hbox(8)
	var title := UiKit.label("Settings", 22, UiKit.COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := UiKit.button("CLOSE", 13)
	close_button.custom_minimum_size = Vector2(110, 44)
	close_button.pressed.connect(func() -> void: closed.emit())
	head.add_child(close_button)
	body.add_child(head)

	body.add_child(UiKit.label("Music volume", 14, UiKit.COLOR_MUTED))
	_music_slider = _make_slider()
	_music_slider.value_changed.connect(func(value: float) -> void: GameState.set_music_volume(value))
	body.add_child(_music_slider)

	body.add_child(UiKit.label("Sound effects volume", 14, UiKit.COLOR_MUTED))
	_sfx_slider = _make_slider()
	_sfx_slider.value_changed.connect(func(value: float) -> void:
		GameState.set_sfx_volume(value)
		AudioManager.play("tap"))
	body.add_child(_sfx_slider)

	_haptics_toggle = CheckButton.new()
	_haptics_toggle.text = "Haptic feedback"
	_haptics_toggle.custom_minimum_size = Vector2(0, 44)
	_haptics_toggle.add_theme_font_size_override("font_size", 15)
	_haptics_toggle.toggled.connect(func(value: bool) -> void: GameState.set_haptics_enabled(value))
	body.add_child(_haptics_toggle)

	var auto_deliver_toggle := CheckButton.new()
	auto_deliver_toggle.text = "Auto-deliver workshop orders"
	auto_deliver_toggle.custom_minimum_size = Vector2(0, 44)
	auto_deliver_toggle.add_theme_font_size_override("font_size", 15)
	auto_deliver_toggle.toggled.connect(func(value: bool) -> void: GameState.set_auto_deliver(value))
	body.add_child(auto_deliver_toggle)
	# store reference via meta? Use a var by changing class. We'll instead sync through settings_changed by re-reading. Need reference; add to a var.
	_auto_deliver_toggle_ref = auto_deliver_toggle

	body.add_child(UiKit.label(
		"Save data lives in the user:// folder and is written automatically.",
		11, UiKit.COLOR_MUTED, true
	))

	var save_button := UiKit.button("SAVE NOW", 14)
	save_button.pressed.connect(_on_save_pressed)
	body.add_child(save_button)

	var skip_button := UiKit.button("SKIP TUTORIAL", 14)
	skip_button.pressed.connect(func() -> void:
		GameState.finish_tutorial()
		GameState.push_notice("Tutorial skipped.", "info"))
	body.add_child(skip_button)

	var reset_button := UiKit.button("RESET PROGRESS", 14)
	reset_button.pressed.connect(_on_reset_pressed)
	body.add_child(reset_button)

	_version_label = UiKit.label("", 11, UiKit.COLOR_MUTED)
	body.add_child(_version_label)

	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Reset progress"
	_reset_dialog.dialog_text = "Delete all progress and start over? Credits, board, ship and destinations will be lost. This cannot be undone."
	_reset_dialog.ok_button_text = "RESET"
	_reset_dialog.cancel_button_text = "CANCEL"
	_reset_dialog.confirmed.connect(_on_reset_confirmed)
	add_child(_reset_dialog)


func _make_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(0, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _sync() -> void:
	if _music_slider == null:
		return
	_music_slider.set_value_no_signal(float(GameState.settings.get("music", 0.55)))
	_sfx_slider.set_value_no_signal(float(GameState.settings.get("sfx", 0.8)))
	_haptics_toggle.set_pressed_no_signal(bool(GameState.settings.get("haptics", true)))
	if _auto_deliver_toggle_ref != null:
		_auto_deliver_toggle_ref.set_pressed_no_signal(bool(GameState.settings.get("auto_deliver", false)))
	var version: String = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	_version_label.text = "Scrap to Space v%s - offline build" % version


func _on_save_pressed() -> void:
	if GameState.save_now(true):
		GameState.push_notice("Progress saved.", "good")
	else:
		GameState.push_notice("Could not save progress.", "warn")


func _on_reset_pressed() -> void:
	_reset_dialog.popup_centered()


func _on_reset_confirmed() -> void:
	GameState.reset_progress()
	GameState.push_notice("Progress reset. Welcome back to the junkyard.", "info")
	closed.emit()
