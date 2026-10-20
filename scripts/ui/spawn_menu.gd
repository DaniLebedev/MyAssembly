class_name SpawnMenu
extends Control
## Меню пресетов: Tab или кнопка в правом верхнем углу.

signal preset_selected(preset_id: String)
signal opened
signal closed

const ACCENT := Color(1.0, 0.62, 0.16)
const MUTED := Color(0.62, 0.71, 0.83)
const TEXT := Color(0.92, 0.95, 1.0)
const PANEL_BG := Color(0.045, 0.056, 0.075, 0.98)
const CARD_BG := Color(0.07, 0.085, 0.11, 0.98)
const CARD_HOVER := Color(0.105, 0.13, 0.17, 0.98)

var _overlay: Control
var _panel: PanelContainer
var _dim: ColorRect
var _first_button: Button
var _open := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_toggle()
	_build_overlay()
	_overlay.visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_overlay.visible = true
	if _first_button != null:
		_first_button.grab_focus()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_overlay.visible = false
	closed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _build_toggle() -> void:
	var button := Button.new()
	button.name = "SpawnToggle"
	button.text = "＋  СОЗДАТЬ  [Tab]"
	button.focus_mode = Control.FOCUS_NONE
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.0
	button.anchor_bottom = 0.0
	button.offset_left = -250.0
	button.offset_top = 76.0
	button.offset_right = -24.0
	button.offset_bottom = 118.0
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(1.0, 0.79, 0.48))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.78))
	button.add_theme_stylebox_override("normal", _style(
		Color(0.12, 0.07, 0.035, 0.9), Color(1.0, 0.62, 0.16, 0.55), 10
	))
	button.add_theme_stylebox_override("hover", _style(
		Color(0.19, 0.105, 0.045, 0.95), Color(1.0, 0.68, 0.28, 0.9), 10
	))
	button.add_theme_stylebox_override("pressed", _style(
		Color(0.26, 0.14, 0.05, 0.98), Color(1.0, 0.75, 0.35, 1.0), 10
	))
	button.pressed.connect(toggle)
	add_child(button)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "SpawnOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.008, 0.012, 0.02, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	_overlay.add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -390.0
	_panel.offset_right = 390.0
	_panel.offset_top = -292.0
	_panel.offset_bottom = 292.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _style(
		PANEL_BG, Color(0.36, 0.45, 0.58, 0.55), 18
	))
	_overlay.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	margin.add_child(root_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_box.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	var title := Label.new()
	title.text = "СОЗДАТЬ ДЕТАЛЬ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", TEXT)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Пресет появится перед камерой и сразу выделится"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", MUTED)
	title_box.add_child(subtitle)

	var close_button := Button.new()
	close_button.text = "ЗАКРЫТЬ  Esc"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(138.0, 38.0)
	close_button.add_theme_font_size_override("font_size", 12)
	close_button.add_theme_color_override("font_color", Color(0.76, 0.82, 0.9))
	close_button.add_theme_stylebox_override("normal", _style(
		Color(0.08, 0.095, 0.12, 1.0), Color(0.36, 0.44, 0.56, 0.45), 9
	))
	close_button.add_theme_stylebox_override("hover", _style(
		Color(0.13, 0.15, 0.19, 1.0), Color(0.7, 0.78, 0.9, 0.75), 9
	))
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(1.0, 1.0)
	line.color = Color(0.35, 0.43, 0.54, 0.36)
	root_box.add_child(line)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(grid)

	_add_card(
		grid, "cube", "КУБ  ·  2 × 2 × 2",
		"Базовая объёмная деталь\n8 точек · 12 рёбер · коллизия"
	)
	_add_card(
		grid, "plane", "ПЛОСКОСТЬ  ·  4 × 4",
		"Горизонтальная площадка\n4 точки · панель · 4 балки"
	)
	_add_card(
		grid, "beam", "БАЛКА  ·  3 м",
		"Линейная деталь\n2 точки · притягивается к креплениям"
	)
	_add_card(
		grid, "hinge", "ШАРНИР",
		"Две стороны и ось вращения\n2 точки крепления"
	)
	_add_card(
		grid, "motor", "МОТОР",
		"Корпус и выходной вал\nскорость · крутящий момент"
	)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 108.0)
	grid.add_child(spacer)

	var footer := Label.new()
	footer.text = "ЛКМ по карточке — создать  ·  Tab / Esc — закрыть"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.55, 0.64, 0.76))
	root_box.add_child(footer)


func _add_card(
	grid: GridContainer,
	preset_id: String,
	title_text: String,
	description: String
) -> void:
	var button := Button.new()
	button.name = "Preset_" + preset_id
	button.text = title_text + "\n" + description
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(346.0, 108.0)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.74))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.9, 0.74))
	button.add_theme_stylebox_override("normal", _card_style(CARD_BG, Color(0.30, 0.38, 0.49, 0.42)))
	button.add_theme_stylebox_override("hover", _card_style(CARD_HOVER, Color(1.0, 0.62, 0.16, 0.7)))
	button.add_theme_stylebox_override("pressed", _card_style(
		Color(0.16, 0.105, 0.06, 1.0), Color(1.0, 0.7, 0.26, 0.9)
	))
	button.add_theme_stylebox_override("focus", _card_style(
		Color(0.10, 0.12, 0.16, 1.0), Color(1.0, 0.62, 0.16, 0.8)
	))
	button.pressed.connect(func() -> void: _on_preset_pressed(preset_id))
	grid.add_child(button)
	if _first_button == null:
		_first_button = button


func _on_preset_pressed(preset_id: String) -> void:
	close()
	preset_selected.emit(preset_id)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			close()
			accept_event()


func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _card_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := _style(background, border, 13)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style
