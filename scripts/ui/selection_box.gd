class_name SelectionBoxOverlay
extends Control
## Рамка выделения, рисуется поверх 3D-сцены.

const FILL_COLOR := Color(0.32, 0.72, 1.0, 0.09)
const BORDER_COLOR := Color(0.48, 0.82, 1.0, 0.9)

var _active := false
var _rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func set_box(active: bool, rect: Rect2) -> void:
	_active = active
	_rect = rect
	visible = active
	queue_redraw()


func _draw() -> void:
	if not _active or _rect.size.x < 1.0 or _rect.size.y < 1.0:
		return
	draw_rect(_rect, FILL_COLOR, true)
	draw_rect(_rect, BORDER_COLOR, false, 1.5)
