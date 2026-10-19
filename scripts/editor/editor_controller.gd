class_name EditorController
extends Node3D
## Выделение, перемещение точек с привязкой к сетке, удаление и история.

signal selection_changed
signal history_changed
signal marquee_changed(active: bool, rect: Rect2)

@export var points_root_path: NodePath = ^"../Points"
@export var camera_rig_path: NodePath = ^"../CameraRig"
@export var grid_path: NodePath = ^"../Grid"

const CLICK_TOLERANCE := 4.0

var _points_root: Node3D
var _grid: EditorGrid
var _camera: Camera3D
var _history := UndoStack.new()

var _selected: Array[EditorPoint] = []
var _hovered: EditorPoint

var _dragged_point: EditorPoint
var _drag_plane := Plane()
var _drag_offset := Vector3.ZERO
var _drag_origin := Vector3.ZERO
var _drag_moved := false

var _marquee_active := false
var _marquee_start := Vector2.ZERO
var _marquee_base: Array[EditorPoint] = []

var _rmb_down := false
var _rmb_dragged := false
var _rmb_press_position := Vector2.ZERO


func _ready() -> void:
	_points_root = get_node_or_null(points_root_path) as Node3D
	_grid = get_node_or_null(grid_path) as EditorGrid

	var rig := get_node_or_null(camera_rig_path) as EditorCameraRig
	if rig != null:
		_camera = rig.get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = get_viewport().get_camera_3d()

	_history.changed.connect(_on_history_changed)


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()

	if event is InputEventKey:
		_handle_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo or _is_typing():
		return

	if event.ctrl_pressed and _matches_key(event, KEY_Z):
		if event.shift_pressed:
			_history.redo()
		else:
			_history.undo()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and _matches_key(event, KEY_Y):
		_history.redo()
		get_viewport().set_input_as_handled()
	elif _matches_key(event, KEY_DELETE) or _matches_key(event, KEY_BACKSPACE):
		_delete_selected()
		get_viewport().set_input_as_handled()
	elif _matches_key(event, KEY_ESCAPE):
		_set_selection([])


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var additive := Input.is_key_pressed(KEY_SHIFT)
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_pressed(event.position, additive)
			else:
				_on_left_released()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_rmb_down = true
				_rmb_dragged = false
				_rmb_press_position = event.position
			else:
				if _rmb_down and not _rmb_dragged:
					_set_selection([])
				_rmb_down = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _rmb_down and event.position.distance_to(_rmb_press_position) > CLICK_TOLERANCE:
		_rmb_dragged = true

	if _marquee_active:
		_update_marquee(event.position)
	elif _dragged_point != null:
		_update_drag(event.position)
	else:
		_update_hover(event.position)


func _on_left_pressed(position: Vector2, additive: bool) -> void:
	if _camera == null:
		return

	var hit := _pick_point(position)
	if hit == null:
		_set_hovered(null)
		if additive:
			_begin_marquee(position)
		else:
			_set_selection([])
		return

	if additive:
		_toggle_selection(hit)
		return

	if _selected.size() != 1 or _selected[0] != hit:
		_set_selection([hit])
	_begin_drag(hit, position)


func _on_left_released() -> void:
	if _marquee_active:
		_finish_marquee()
	elif _dragged_point != null:
		_finish_drag()
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _begin_drag(point: EditorPoint, screen_position: Vector2) -> void:
	var normal := -_camera.global_basis.z.normalized()
	var plane := Plane(normal, normal.dot(point.global_position))
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return

	var hit_position: Vector3 = hit
	_dragged_point = point
	_drag_plane = plane
	_drag_offset = point.global_position - hit_position
	_drag_origin = point.global_position
	_drag_moved = false
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)


func _update_drag(screen_position: Vector2) -> void:
	if _dragged_point == null or _camera == null:
		return

	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var hit: Variant = _drag_plane.intersects_ray(origin, direction)
	if hit == null:
		return

	var target: Vector3 = hit
	target += _drag_offset
	var snapped := EditorPoint.snap_to_grid(target, _get_grid_step())
	if not snapped.is_equal_approx(_dragged_point.global_position):
		_dragged_point.global_position = snapped
		_drag_moved = true


func _finish_drag() -> void:
	var point := _dragged_point
	var old_position := _drag_origin
	var new_position := point.global_position
	var moved := _drag_moved and not old_position.is_equal_approx(new_position)

	_dragged_point = null
	_drag_moved = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	if not moved or not is_instance_valid(point):
		return

	var undo_call := func() -> void:
		if is_instance_valid(point):
			point.global_position = old_position
	var redo_call := func() -> void:
		if is_instance_valid(point):
			point.global_position = new_position
	_history.push("Перемещение точки", undo_call, redo_call)


func _begin_marquee(position: Vector2) -> void:
	_marquee_active = true
	_marquee_start = position
	_marquee_base.clear()
	_marquee_base.append_array(_selected)
	marquee_changed.emit(true, Rect2(position, Vector2.ZERO))
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


func _update_marquee(position: Vector2) -> void:
	var rect := Rect2(_marquee_start, position - _marquee_start).abs()
	_update_marquee_selection(rect)
	marquee_changed.emit(true, rect)


func _update_marquee_selection(rect: Rect2) -> void:
	if _camera == null or _points_root == null:
		return

	var next: Array[EditorPoint] = []
	next.append_array(_marquee_base)
	var hit_area := rect.grow(4.0)

	for child in _points_root.get_children():
		var point := child as EditorPoint
		if point == null or next.has(point):
			continue
		if _camera.is_position_behind(point.global_position):
			continue
		var screen := _camera.unproject_position(point.global_position)
		if hit_area.has_point(screen):
			next.append(point)

	_set_selection(next)


func _finish_marquee() -> void:
	_marquee_active = false
	marquee_changed.emit(false, Rect2())
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _update_hover(screen_position: Vector2) -> void:
	var hit := _pick_point(screen_position)
	_set_hovered(hit)
	if hit != null:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _set_hovered(point: EditorPoint) -> void:
	if _hovered == point:
		return
	if is_instance_valid(_hovered):
		_hovered.set_hovered(false)
	_hovered = point
	if is_instance_valid(_hovered):
		_hovered.set_hovered(true)


func _pick_point(screen_position: Vector2) -> EditorPoint:
	if _camera == null or _points_root == null:
		return null

	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var best: EditorPoint = null
	var best_distance := INF

	for child in _points_root.get_children():
		var point := child as EditorPoint
		if point == null:
			continue
		var to_point := point.global_position - origin
		var along := to_point.dot(direction)
		if along <= 0.0:
			continue
		var closest := origin + direction * along
		var radius := maxf(EditorPoint.PICK_RADIUS, along * 0.012)
		if closest.distance_to(point.global_position) > radius:
			continue
		if along < best_distance:
			best = point
			best_distance = along

	return best


func _set_selection(points: Array[EditorPoint]) -> void:
	var next: Array[EditorPoint] = []
	for point in points:
		if is_instance_valid(point) and not next.has(point):
			next.append(point)

	for point in _selected:
		if is_instance_valid(point):
			point.set_selected(false)
	_selected = next
	for point in _selected:
		point.set_selected(true)
	selection_changed.emit()


func _toggle_selection(point: EditorPoint) -> void:
	var next: Array[EditorPoint] = []
	next.append_array(_selected)
	if next.has(point):
		next.erase(point)
	else:
		next.append(point)
	_set_selection(next)


func _delete_selected() -> void:
	if _selected.is_empty() or _points_root == null:
		return

	var points: Array[EditorPoint] = []
	points.append_array(_selected)
	var entries: Array[Dictionary] = []
	for point in points:
		entries.append({"point": point, "position": point.global_position})

	_set_hovered(null)
	_set_selection([])
	for entry in entries:
		var point: EditorPoint = entry["point"]
		if point.get_parent() != null:
			point.get_parent().remove_child(point)

	var undo_call := func() -> void:
		var restored: Array[EditorPoint] = []
		for entry in entries:
			var point: EditorPoint = entry["point"]
			if point.get_parent() == null and is_instance_valid(_points_root):
				_points_root.add_child(point)
			point.global_position = entry["position"]
			restored.append(point)
		_set_selection(restored)

	var redo_call := func() -> void:
		_set_selection([])
		for entry in entries:
			var point: EditorPoint = entry["point"]
			if point.get_parent() != null:
				point.get_parent().remove_child(point)

	_history.push("Удаление точек (%d)" % entries.size(), undo_call, redo_call)


func _get_grid_step() -> float:
	if _grid != null:
		return _grid.grid_step
	return 0.5


func _is_typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _matches_key(event: InputEventKey, keycode: Key) -> bool:
	return event.keycode == keycode or event.physical_keycode == keycode


func _on_history_changed() -> void:
	history_changed.emit()


func get_selected_points() -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	result.append_array(_selected)
	return result


func get_selected_count() -> int:
	return _selected.size()


func get_point_count() -> int:
	if _points_root == null:
		return 0
	return _points_root.get_child_count()


func get_undo_name() -> String:
	return _history.get_undo_name()


func get_redo_name() -> String:
	return _history.get_redo_name()
