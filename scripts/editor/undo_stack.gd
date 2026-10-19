class_name UndoStack
extends RefCounted
## Стек действий, которые уже выполнены.
## Действие хранится как пара Callable: отмена и повтор.

signal changed

const MAX_ACTIONS := 100

var _undo_actions: Array[Dictionary] = []
var _redo_actions: Array[Dictionary] = []


func push(action_name: String, undo_call: Callable, redo_call: Callable) -> void:
	_undo_actions.append({
		"name": action_name,
		"undo": undo_call,
		"redo": redo_call,
	})
	if _undo_actions.size() > MAX_ACTIONS:
		_undo_actions.pop_front()
	_redo_actions.clear()
	changed.emit()


func undo() -> bool:
	if _undo_actions.is_empty():
		return false
	var action: Dictionary = _undo_actions.pop_back()
	var undo_call: Callable = action["undo"]
	undo_call.call()
	_redo_actions.append(action)
	changed.emit()
	return true


func redo() -> bool:
	if _redo_actions.is_empty():
		return false
	var action: Dictionary = _redo_actions.pop_back()
	var redo_call: Callable = action["redo"]
	redo_call.call()
	_undo_actions.append(action)
	changed.emit()
	return true


func can_undo() -> bool:
	return not _undo_actions.is_empty()


func can_redo() -> bool:
	return not _redo_actions.is_empty()


func get_undo_name() -> String:
	if _undo_actions.is_empty():
		return ""
	return str(_undo_actions.back()["name"])


func get_redo_name() -> String:
	if _redo_actions.is_empty():
		return ""
	return str(_redo_actions.back()["name"])


func clear() -> void:
	_undo_actions.clear()
	_redo_actions.clear()
	changed.emit()
