class_name EditorEntity
extends Node3D
## Базовый класс выделяемого объекта редактора.

var is_selected := false
var is_hovered := false


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	_refresh_visual()


func set_hovered(value: bool) -> void:
	if is_hovered == value:
		return
	is_hovered = value
	_refresh_visual()


func get_editor_points() -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	return result


func refresh_geometry() -> void:
	pass


func _refresh_visual() -> void:
	pass
