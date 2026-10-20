class_name RadialMenu
extends Control
## Круговое меню деталей вокруг курсора при удержании ПКМ.

const LABELS := ["КУБ", "ПЛОСКОСТЬ", "БАЛКА", "ШАРНИР", "МОТОР"]
const SUBLABELS := ["2 × 2 × 2", "4 × 4", "3 м", "2 крепления", "скорость"]
const ACCENT := Color(1.0, 0.62, 0.16)
const TEXT := Color(0.9, 0.94, 1.0)
const MUTED := Color(0.58, 0.67, 0.79)

var _active := false
var _center := Vector2.ZERO
var _hovered := -1
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func show_menu(center: Vector2) -> void:
	_active = true
	_center = center
	_hovered = -1
	visible = true
	set_process(true)
	queue_redraw()


func set_hovered(index: int) -> void:
	if _hovered == index:
		return
	_hovered = index
	queue_redraw()


func hide_menu() -> void:
	_active = false
	_hovered = -1
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not _active:
		return

	var font := ThemeDB.fallback_font
	var count := LABELS.size()
	var sector := TAU / float(count)
	var outer := 176.0
	var inner := 66.0
	var center := _center

	draw_circle(center, outer + 20.0, Color(0.01, 0.018, 0.03, 0.34))
	draw_circle(center, outer + 8.0, Color(0.025, 0.038, 0.06, 0.72))

	for i in count:
		var start := -PI * 0.5 + sector * i
		var end := start + sector
		var points := PackedVector2Array([center])
		for step in 18:
			var angle := lerpf(start, end, float(step) / 17.0)
			points.append(center + Vector2(cos(angle), sin(angle)) * outer)

		var hovered := i == _hovered
		var fill := Color(0.055, 0.075, 0.11, 0.94)
		if hovered:
			fill = Color(0.23, 0.14, 0.055, 0.96)
		draw_colored_polygon(points, fill)

		var border := Color(0.34, 0.43, 0.55, 0.36)
		if hovered:
			border = Color(1.0, 0.62, 0.16, 0.95)
		draw_arc(center, outer, start, end, 24, border, 1.5, true)

	draw_circle(center, inner + 3.0, Color(0.02, 0.03, 0.045, 0.99))
	draw_arc(center, inner + 2.0, 0.0, TAU, 64, Color(1.0, 0.62, 0.16, 0.65), 2.0, true)
	draw_arc(center, outer, 0.0, TAU, 96, Color(1.0, 0.62, 0.16, 0.35), 1.5, true)

	for i in count:
		var start := -PI * 0.5 + sector * i
		var direction := Vector2(cos(start), sin(start))
		draw_line(
			center + direction * (inner + 2.0),
			center + direction * outer,
			Color(0.32, 0.41, 0.53, 0.45),
			1.0,
			true
		)

		var mid := start + sector * 0.5
		var pos := center + Vector2(cos(mid), sin(mid)) * 122.0
		var hovered := i == _hovered
		var color := ACCENT if hovered else Color(0.78, 0.85, 0.94, 0.92)
		draw_icon(i, pos, color)

		draw_string(
			font,
			Vector2(pos.x - 78.0, pos.y + 36.0),
			LABELS[i],
			HORIZONTAL_ALIGNMENT_CENTER,
			156.0,
			14,
			color
		)
		draw_string(
			font,
			Vector2(pos.x - 78.0, pos.y + 51.0),
			SUBLABELS[i],
			HORIZONTAL_ALIGNMENT_CENTER,
			156.0,
			10,
			ACCENT if hovered else MUTED
		)

	if _hovered >= 0:
		var direction := Vector2(
			cos(-PI * 0.5 + sector * (_hovered + 0.5)),
			sin(-PI * 0.5 + sector * (_hovered + 0.5))
		)
		draw_line(center, center + direction * (inner - 8.0), ACCENT, 2.0, true)
		draw_string(
			font,
			Vector2(center.x - 78.0, center.y + 4.0),
			LABELS[_hovered],
			HORIZONTAL_ALIGNMENT_CENTER,
			156.0,
			16,
			ACCENT
		)
		draw_string(
			font,
			Vector2(center.x - 78.0, center.y + 22.0),
			"ОТПУСТИТЕ ПКМ",
			HORIZONTAL_ALIGNMENT_CENTER,
			156.0,
			9,
			MUTED
		)
	else:
		draw_string(
			font,
			Vector2(center.x - 78.0, center.y - 1.0),
			"ВЫБЕРИТЕ",
			HORIZONTAL_ALIGNMENT_CENTER,
			156.0,
			12,
			TEXT
		)
		draw_string(
			font,
			Vector2(center.x - 78.0, center.y + 17.0),
			"ДЕТАЛЬ",
			HORIZONTAL_ALIGNMENT_CENTER,
			156.0,
			12,
			ACCENT
		)


func draw_icon(index: int, pos: Vector2, color: Color) -> void:
	match index:
		0:
			draw_rect(Rect2(pos - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), color, false, 2.0)
			draw_line(pos + Vector2(-10.0, -10.0), pos + Vector2(-4.0, -16.0), color, 2.0, true)
			draw_line(pos + Vector2(10.0, -10.0), pos + Vector2(16.0, -16.0), color, 2.0, true)
			draw_line(pos + Vector2(-4.0, -16.0), pos + Vector2(16.0, -16.0), color, 2.0, true)
		1:
			var quad := PackedVector2Array([
				pos + Vector2(-14.0, 6.0),
				pos + Vector2(-7.0, -7.0),
				pos + Vector2(14.0, -7.0),
				pos + Vector2(7.0, 6.0),
				pos + Vector2(-14.0, 6.0),
			])
			draw_polyline(quad, color, 2.0, true)
		2:
			draw_line(pos + Vector2(-15.0, 0.0), pos + Vector2(15.0, 0.0), color, 5.0, true)
			draw_line(pos + Vector2(-15.0, -5.0), pos + Vector2(-15.0, 5.0), color, 2.0, true)
			draw_line(pos + Vector2(15.0, -5.0), pos + Vector2(15.0, 5.0), color, 2.0, true)
		3:
			draw_circle(pos, 11.0, color, false, 2.0)
			draw_line(pos + Vector2(-16.0, 0.0), pos + Vector2(16.0, 0.0), color, 2.0, true)
			draw_line(pos + Vector2(-7.0, -8.0), pos + Vector2(-7.0, 8.0), color, 2.0, true)
			draw_line(pos + Vector2(7.0, -8.0), pos + Vector2(7.0, 8.0), color, 2.0, true)
		4:
			draw_circle(pos, 9.0, color, false, 2.0)
			for i in 8:
				var angle := TAU * float(i) / 8.0
				var direction := Vector2(cos(angle), sin(angle))
				draw_line(pos + direction * 12.0, pos + direction * 17.0, color, 2.0, true)
