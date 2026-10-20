class_name EditorController
extends Node3D
## Редактор в стиле Blender: выбор, G, E, F, M, осевой замок и история.

signal selection_changed
signal history_changed
signal context_changed
signal marquee_changed(active: bool, rect: Rect2)

@export var points_root_path: NodePath = ^"../Points"
@export var structures_root_path: NodePath = ^"../Structures"
@export var camera_rig_path: NodePath = ^"../CameraRig"
@export var grid_path: NodePath = ^"../Grid"

const EPSILON := 0.000001
const WELD_NEAR_DISTANCE := 1.0

enum Mode {
	NONE,
	GRAB,
	EXTRUDE_POINT,
	EXTRUDE_LINE,
	EXTRUDE_LOOP,
}

var _points_root: Node3D
var _structures_root: Node3D
var _grid: EditorGrid
var _camera: Camera3D
var _history := UndoStack.new()

var _selected: Array[EditorEntity] = []
var _hovered: EditorEntity

var _mode := Mode.NONE
var _axis_lock := -1
var _marquee_active := false
var _marquee_start := Vector2.ZERO
var _marquee_base: Array[EditorEntity] = []

var _grab_points: Array[EditorPoint] = []
var _grab_old_positions: Dictionary = {}
var _grab_plane := Plane()
var _grab_start_hit := Vector3.ZERO
var _grab_delta := Vector3.ZERO
var _grab_moved := false

var _extrude_profile: Array[EditorPoint] = []
var _extrude_plane := Plane()
var _extrude_start_hit := Vector3.ZERO
var _extrude_center := Vector3.ZERO
var _extrude_normal := Vector3.UP
var _extrude_screen_origin := Vector2.ZERO
var _extrude_offset := Vector3.ZERO
var _extrude_preview_positions: Array[Vector3] = []
var _extrude_valid := false

var _preview_root: Node3D
var _preview_beam: MeshInstance3D
var _preview_faces: Array[MeshInstance3D] = []
var _preview_points: Array[MeshInstance3D] = []
var _preview_surface_material: StandardMaterial3D
var _preview_point_material: StandardMaterial3D


func _ready() -> void:
	_points_root = get_node_or_null(points_root_path) as Node3D
	_structures_root = get_node_or_null(structures_root_path) as Node3D
	_grid = get_node_or_null(grid_path) as EditorGrid

	var rig := get_node_or_null(camera_rig_path) as EditorCameraRig
	if rig != null:
		_camera = rig.get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = get_viewport().get_camera_3d()

	_history.changed.connect(_on_history_changed)
	_build_preview()


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

	if _mode != Mode.NONE:
		if _matches_key(event, KEY_ESCAPE):
			_cancel_modal()
			get_viewport().set_input_as_handled()
			return
		if not event.ctrl_pressed and not event.alt_pressed:
			if _matches_key(event, KEY_X):
				_set_axis_lock(0)
				get_viewport().set_input_as_handled()
				return
			if _matches_key(event, KEY_Y):
				_set_axis_lock(1)
				get_viewport().set_input_as_handled()
				return
			if _matches_key(event, KEY_Z):
				_set_axis_lock(2)
				get_viewport().set_input_as_handled()
				return
		return

	if event.ctrl_pressed and event.shift_pressed and _matches_key(event, KEY_M):
		_weld_selected_points(false)
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and _matches_key(event, KEY_M):
		_weld_selected_points(true)
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and _matches_key(event, KEY_Z):
		if event.shift_pressed:
			_history.redo()
		else:
			_history.undo()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and _matches_key(event, KEY_Y):
		_history.redo()
		get_viewport().set_input_as_handled()
	elif not event.ctrl_pressed and not event.alt_pressed and _matches_key(event, KEY_G):
		_start_grab()
		get_viewport().set_input_as_handled()
	elif not event.ctrl_pressed and not event.alt_pressed and _matches_key(event, KEY_E):
		_start_extrude()
		get_viewport().set_input_as_handled()
	elif not event.ctrl_pressed and not event.alt_pressed and _matches_key(event, KEY_F):
		_fill()
		get_viewport().set_input_as_handled()
	elif not event.ctrl_pressed and not event.alt_pressed and _matches_key(event, KEY_M):
		_weld_selected()
		get_viewport().set_input_as_handled()
	elif not event.ctrl_pressed and _matches_key(event, KEY_X):
		_delete_selected()
		get_viewport().set_input_as_handled()
	elif _matches_key(event, KEY_DELETE) or _matches_key(event, KEY_BACKSPACE):
		_delete_selected()
		get_viewport().set_input_as_handled()
	elif _matches_key(event, KEY_ESCAPE):
		_set_selection([])


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.alt_pressed:
				return
			if _mode != Mode.NONE:
				_confirm_modal()
			else:
				var additive := event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
				_on_left_pressed(event.position, additive)
		else:
			_on_left_released()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if _mode != Mode.NONE:
				_cancel_modal()
			else:
				_set_selection([])


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _mode == Mode.GRAB:
		_update_grab(event.position)
	elif _mode == Mode.EXTRUDE_POINT or _mode == Mode.EXTRUDE_LINE or _mode == Mode.EXTRUDE_LOOP:
		_update_extrude(event.position)
	elif _marquee_active:
		_update_marquee(event.position)
	else:
		_update_hover(event.position)


func _on_left_pressed(position: Vector2, additive: bool) -> void:
	if _camera == null:
		return

	var hit := _pick_entity(position)
	if hit == null:
		_set_hovered(null)
		if not additive:
			_set_selection([])
		_begin_marquee(position)
		return

	if additive:
		_toggle_selection(hit)
		return

	_set_selection([hit])


func _on_left_released() -> void:
	if _marquee_active:
		_finish_marquee()
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _update_hover(position: Vector2) -> void:
	var hit := _pick_entity(position)
	_set_hovered(hit)
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if hit != null else Input.CURSOR_ARROW
	)


func _set_hovered(entity: EditorEntity) -> void:
	if _hovered == entity:
		return
	if is_instance_valid(_hovered):
		_hovered.set_hovered(false)
	_hovered = entity
	if is_instance_valid(_hovered):
		_hovered.set_hovered(true)


func _pick_entity(screen_position: Vector2) -> EditorEntity:
	if _camera == null:
		return null

	var point := _pick_point(screen_position)
	if point != null:
		return point

	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var best: EditorEntity = null
	var best_distance := INF

	if _structures_root != null:
		for child in _structures_root.get_children():
			var entity := child as EditorEntity
			if entity == null:
				continue
			var distance := _pick_structure_distance(entity, origin, direction)
			if distance >= 0.0 and distance < best_distance:
				best = entity
				best_distance = distance

	return best


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


func _pick_structure_distance(
	entity: EditorEntity,
	origin: Vector3,
	direction: Vector3
) -> float:
	if entity is EditorBeam:
		var beam := entity as EditorBeam
		if beam.point_a == null or beam.point_b == null:
			return -1.0
		var hit := EditorGeometry.ray_segment_distance(
			origin, direction, beam.point_a.global_position, beam.point_b.global_position
		)
		var threshold := maxf(0.09, hit.y * 0.006)
		if hit.y > 0.0 and hit.x <= threshold:
			return hit.y
		return -1.0

	var points := entity.get_editor_points()
	if points.size() < 3:
		return -1.0

	var best := INF
	if entity is EditorPanel:
		best = _pick_polygon(points, origin, direction)
	elif entity is EditorCube:
		var triangles := [
			[0, 3, 2], [0, 2, 1],
			[4, 5, 6], [4, 6, 7],
			[0, 1, 5], [0, 5, 4],
			[1, 2, 6], [1, 6, 5],
			[2, 3, 7], [2, 7, 6],
			[3, 0, 4], [3, 4, 7],
		]
		for triangle in triangles:
			var distance := _pick_triangle(
				points[triangle[0]].global_position,
				points[triangle[1]].global_position,
				points[triangle[2]].global_position,
				origin,
				direction
			)
			if distance >= 0.0 and distance < best:
				best = distance

	return best if best < INF else -1.0


func _pick_polygon(points: Array[EditorPoint], origin: Vector3, direction: Vector3) -> float:
	var best := INF
	for i in range(1, points.size() - 1):
		var distance := _pick_triangle(
			points[0].global_position,
			points[i].global_position,
			points[i + 1].global_position,
			origin,
			direction
		)
		if distance >= 0.0 and distance < best:
			best = distance
	return best if best < INF else -1.0


func _pick_triangle(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	origin: Vector3,
	direction: Vector3
) -> float:
	var hit: Variant = EditorGeometry.ray_triangle(origin, direction, a, b, c)
	if hit == null:
		return -1.0
	var point: Vector3 = hit
	return origin.distance_to(point)


func _set_selection(entities: Array[EditorEntity]) -> void:
	var next: Array[EditorEntity] = []
	for entity in entities:
		if is_instance_valid(entity) and not next.has(entity):
			next.append(entity)

	for entity in _selected:
		if is_instance_valid(entity):
			entity.set_selected(false)
	_selected = next
	for entity in _selected:
		entity.set_selected(true)

	selection_changed.emit()
	context_changed.emit()


func _toggle_selection(entity: EditorEntity) -> void:
	var next: Array[EditorEntity] = []
	next.append_array(_selected)
	if next.has(entity):
		next.erase(entity)
	else:
		next.append(entity)
	_set_selection(next)


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
	if _camera == null:
		return

	var next: Array[EditorEntity] = []
	next.append_array(_marquee_base)
	var hit_area := rect.grow(4.0)

	if _points_root != null:
		for child in _points_root.get_children():
			var point := child as EditorPoint
			if point == null or next.has(point):
				continue
			if _world_point_in_rect(point.global_position, hit_area):
				next.append(point)

	if _structures_root != null:
		for child in _structures_root.get_children():
			var entity := child as EditorEntity
			if entity == null or next.has(entity):
				continue
			if _entity_intersects_rect(entity, hit_area):
				next.append(entity)

	_set_selection(next)


func _world_point_in_rect(world_position: Vector3, rect: Rect2) -> bool:
	if _camera == null or _camera.is_position_behind(world_position):
		return false
	return rect.has_point(_camera.unproject_position(world_position))


func _entity_intersects_rect(entity: EditorEntity, rect: Rect2) -> bool:
	if entity is EditorBeam:
		var beam := entity as EditorBeam
		if beam.point_a == null or beam.point_b == null:
			return false
		return _world_segment_intersects_rect(
			beam.point_a.global_position,
			beam.point_b.global_position,
			rect
		)

	var points := entity.get_editor_points()
	if points.size() < 3:
		return false

	if entity is EditorPanel:
		for i in range(1, points.size() - 1):
			if _world_triangle_intersects_rect(
				points[0].global_position,
				points[i].global_position,
				points[i + 1].global_position,
				rect
			):
				return true
		return false

	if entity is EditorCube and points.size() == 8:
		var triangles := [
			[0, 3, 2], [0, 2, 1],
			[4, 5, 6], [4, 6, 7],
			[0, 1, 5], [0, 5, 4],
			[1, 2, 6], [1, 6, 5],
			[2, 3, 7], [2, 7, 6],
			[3, 0, 4], [3, 4, 7],
		]
		for triangle in triangles:
			if _world_triangle_intersects_rect(
				points[triangle[0]].global_position,
				points[triangle[1]].global_position,
				points[triangle[2]].global_position,
				rect
			):
				return true

	return false


func _world_segment_intersects_rect(a: Vector3, b: Vector3, rect: Rect2) -> bool:
	if _camera == null or _camera.is_position_behind(a) or _camera.is_position_behind(b):
		return false
	var pa := _camera.unproject_position(a)
	var pb := _camera.unproject_position(b)
	if rect.has_point(pa) or rect.has_point(pb):
		return true
	return _segment_intersects_rect_2d(pa, pb, rect)


func _world_triangle_intersects_rect(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	rect: Rect2
) -> bool:
	if _camera == null:
		return false
	if _camera.is_position_behind(a) or _camera.is_position_behind(b) or _camera.is_position_behind(c):
		return false
	return _triangle_intersects_rect_2d(
		_camera.unproject_position(a),
		_camera.unproject_position(b),
		_camera.unproject_position(c),
		rect
	)


func _triangle_intersects_rect_2d(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	rect: Rect2
) -> bool:
	if rect.has_point(a) or rect.has_point(b) or rect.has_point(c):
		return true

	var polygon := PackedVector2Array([a, b, c])
	for corner in _rect_corners(rect):
		if Geometry2D.is_point_in_polygon(corner, polygon):
			return true

	if _segment_intersects_rect_2d(a, b, rect):
		return true
	if _segment_intersects_rect_2d(b, c, rect):
		return true
	return _segment_intersects_rect_2d(c, a, rect)


func _segment_intersects_rect_2d(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var corners := _rect_corners(rect)
	for i in 4:
		var c := corners[i]
		var d := corners[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return true
	return false


func _rect_corners(rect: Rect2) -> PackedVector2Array:
	var p := rect.position
	var s := rect.size
	return PackedVector2Array([
		p,
		Vector2(p.x + s.x, p.y),
		Vector2(p.x + s.x, p.y + s.y),
		Vector2(p.x, p.y + s.y),
	])


func _finish_marquee() -> void:
	_marquee_active = false
	marquee_changed.emit(false, Rect2())
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _start_grab() -> void:
	if _mode != Mode.NONE or _selected.is_empty() or _camera == null:
		return
	var points := _collect_selected_points()
	if points.is_empty():
		return

	var center := _average_positions(points)
	var normal := -_camera.global_basis.z.normalized()
	var plane := Plane(normal, normal.dot(center))
	var hit: Variant = _mouse_plane_point(get_viewport().get_mouse_position(), plane)
	if hit == null:
		return

	_grab_points = points
	_grab_old_positions.clear()
	for point in points:
		_grab_old_positions[point] = point.global_position
	_grab_plane = plane
	_grab_start_hit = hit
	_grab_delta = Vector3.ZERO
	_grab_moved = false
	_axis_lock = -1
	_mode = Mode.GRAB
	_set_hovered(null)
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	context_changed.emit()


func _update_grab(position: Vector2) -> void:
	var hit: Variant = _mouse_plane_point(position, _grab_plane)
	if hit == null:
		return
	var hit_point: Vector3 = hit
	var raw_delta := hit_point - _grab_start_hit
	if _axis_lock >= 0:
		var axis := _axis_vector()
		raw_delta = axis * raw_delta.dot(axis)
	var delta := _snap_vector(raw_delta, _get_grid_step())
	if delta.is_equal_approx(_grab_delta):
		return

	_grab_delta = delta
	for point in _grab_points:
		var origin: Vector3 = _grab_old_positions[point]
		point.global_position = origin + delta
	_refresh_structures()
	_grab_moved = not delta.is_zero_approx()


func _confirm_grab() -> void:
	var entries: Array[Dictionary] = []
	if _grab_moved:
		for point in _grab_points:
			var old_position: Vector3 = _grab_old_positions[point]
			var new_position := point.global_position
			if not old_position.is_equal_approx(new_position):
				entries.append({"point": point, "old": old_position, "new": new_position})

	var action_name := "G: перемещение (%d)" % entries.size()
	_finish_modal()

	if entries.is_empty():
		return

	var undo_call := func() -> void:
		for entry in entries:
			var point: EditorPoint = entry["point"]
			if is_instance_valid(point):
				point.global_position = entry["old"]
		_refresh_structures()
	var redo_call := func() -> void:
		for entry in entries:
			var point: EditorPoint = entry["point"]
			if is_instance_valid(point):
				point.global_position = entry["new"]
		_refresh_structures()

	_history.push(action_name, undo_call, redo_call)


func _start_extrude() -> void:
	if _mode != Mode.NONE or _camera == null:
		return

	var points := _selected_points_only()
	var beams := _selected_beams_only()
	var profile: Array[EditorPoint] = []
	var new_mode := Mode.NONE

	if _selected.size() == 1 and _selected[0] is EditorPoint:
		profile.append(_selected[0] as EditorPoint)
		new_mode = Mode.EXTRUDE_POINT
	elif points.size() == 2 or points.size() == 3 or points.size() == 4:
		# Профиль важнее прочих выбранных деталей: рамка может захватить
		# точки вместе с их балками и гранью.
		if points.size() == 2:
			profile.append_array(points)
			new_mode = Mode.EXTRUDE_LINE
		else:
			var existing := _find_existing_panel(points)
			if existing != null:
				profile.append_array(existing.points)
			else:
				profile.append_array(_order_profile_points(points))
			new_mode = Mode.EXTRUDE_LOOP
	elif _selected.size() == 1 and _selected[0] is EditorBeam:
		var beam := _selected[0] as EditorBeam
		if beam.point_a != null and beam.point_b != null:
			profile.append(beam.point_a)
			profile.append(beam.point_b)
			new_mode = Mode.EXTRUDE_LINE
	elif _selected.size() == 1 and _selected[0] is EditorPanel:
		var panel := _selected[0] as EditorPanel
		if panel.points.size() >= 3:
			profile.append_array(panel.points)
			new_mode = Mode.EXTRUDE_LOOP
	elif (beams.size() == 3 or beams.size() == 4) and points.is_empty():
		var loop := _beams_to_loop(beams)
		if loop.size() == beams.size():
			profile.append_array(loop)
			new_mode = Mode.EXTRUDE_LOOP

	if profile.is_empty() or new_mode == Mode.NONE:
		return

	_begin_extrude(profile, new_mode)


func _begin_extrude(profile: Array[EditorPoint], new_mode: int) -> void:
	var center := _average_positions(profile)
	var normal := -_camera.global_basis.z.normalized()
	var plane := Plane(normal, normal.dot(center))
	var hit: Variant = _mouse_plane_point(get_viewport().get_mouse_position(), plane)
	if hit == null:
		return

	_extrude_profile = []
	_extrude_profile.append_array(profile)
	_mode = new_mode
	_axis_lock = -1
	_extrude_center = center
	_extrude_plane = plane
	_extrude_start_hit = hit
	_extrude_screen_origin = get_viewport().get_mouse_position()

	if profile.size() >= 3:
		var vertices := PackedVector3Array()
		for point in profile:
			vertices.append(point.global_position)
		_extrude_normal = EditorGeometry.polygon_normal(vertices)
	else:
		_extrude_normal = plane.normal

	_extrude_offset = Vector3.ZERO
	_extrude_preview_positions.clear()
	for point in profile:
		_extrude_preview_positions.append(point.global_position)
	_extrude_valid = false

	_set_hovered(null)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	_show_extrude_preview(Vector3.ZERO)
	context_changed.emit()


func _update_extrude(position: Vector2) -> void:
	if _camera == null or _extrude_profile.is_empty():
		return

	var step := _get_grid_step()
	var offset := Vector3.ZERO

	match _mode:
		Mode.EXTRUDE_POINT:
			var source := _extrude_profile[0].global_position
			var hit: Variant = _mouse_plane_point(position, _extrude_plane)
			if hit == null:
				return
			var hit_point: Vector3 = hit
			if _axis_lock >= 0:
				var axis := _axis_vector()
				var raw := hit_point - _extrude_start_hit
				offset = axis * snappedf(raw.dot(axis), step)
			else:
				var target := EditorPoint.snap_to_grid(hit_point, step)
				offset = target - source
		Mode.EXTRUDE_LINE:
			var hit: Variant = _mouse_plane_point(position, _extrude_plane)
			if hit == null:
				return
			var hit_point: Vector3 = hit
			var raw := hit_point - _extrude_start_hit
			if _axis_lock >= 0:
				var axis := _axis_vector()
				raw = axis * raw.dot(axis)
			offset = _snap_vector(raw, step)
		Mode.EXTRUDE_LOOP:
			if _axis_lock >= 0:
				var hit: Variant = _mouse_plane_point(position, _extrude_plane)
				if hit == null:
					return
				var hit_point: Vector3 = hit
				var raw := hit_point - _extrude_start_hit
				var axis := _axis_vector()
				raw = axis * raw.dot(axis)
				offset = _snap_vector(raw, step)
			else:
				var distance := _loop_extrude_distance(position)
				offset = _extrude_normal * distance
		_:
			return

	_show_extrude_preview(offset)


func _show_extrude_preview(offset: Vector3) -> void:
	if _extrude_profile.is_empty():
		return

	_extrude_offset = offset
	_extrude_preview_positions.clear()
	for point in _extrude_profile:
		_extrude_preview_positions.append(point.global_position + offset)
	_extrude_valid = offset.length_squared() > EPSILON
	if _mode == Mode.EXTRUDE_LINE and _extrude_profile.size() == 2:
		var line := _extrude_profile[1].global_position - _extrude_profile[0].global_position
		if line.cross(offset).length_squared() < EPSILON:
			_extrude_valid = false

	_preview_begin()
	_preview_show_points(_extrude_preview_positions)

	if not _extrude_valid:
		return

	match _mode:
		Mode.EXTRUDE_POINT:
			_preview_show_beam(_extrude_profile[0].global_position, _extrude_preview_positions[0])
		Mode.EXTRUDE_LINE:
			_preview_show_face(PackedVector3Array([
				_extrude_profile[0].global_position,
				_extrude_profile[1].global_position,
				_extrude_preview_positions[1],
				_extrude_preview_positions[0],
			]))
		Mode.EXTRUDE_LOOP:
			if _find_existing_panel(_extrude_profile) == null:
				var bottom := PackedVector3Array()
				for point in _extrude_profile:
					bottom.append(point.global_position)
				_preview_show_face(bottom)

			var top := PackedVector3Array()
			for position in _extrude_preview_positions:
				top.append(position)
			_preview_show_face(top)

			for i in _extrude_profile.size():
				var next := (i + 1) % _extrude_profile.size()
				_preview_show_face(PackedVector3Array([
					_extrude_profile[i].global_position,
					_extrude_profile[next].global_position,
					_extrude_preview_positions[next],
					_extrude_preview_positions[i],
				]))


func _loop_extrude_distance(screen_position: Vector2) -> float:
	if _camera == null:
		return 0.0
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var closest: Variant = EditorGeometry.closest_point_on_line_to_ray(
		_extrude_center, _extrude_normal, origin, direction
	)

	var distance := 0.0
	if closest != null:
		var point: Vector3 = closest
		distance = (point - _extrude_center).dot(_extrude_normal)
	else:
		var screen_delta := screen_position - _extrude_screen_origin
		var camera_distance := _camera.global_position.distance_to(_extrude_center)
		distance = -screen_delta.y * maxf(camera_distance, 1.0) * 0.0012

	return snappedf(distance, _get_grid_step())


func _confirm_extrude() -> void:
	if not _extrude_valid or _extrude_profile.is_empty():
		_cancel_modal()
		return

	var mode := _mode
	var profile: Array[EditorPoint] = []
	profile.append_array(_extrude_profile)
	var offset := _extrude_offset
	var previous: Array[EditorEntity] = []
	previous.append_array(_selected)

	var created_points: Array[EditorPoint] = []
	var created_beams: Array[EditorBeam] = []
	var created_panels: Array[EditorPanel] = []
	var result: Array[EditorEntity] = []
	var action_name := "E: деталь"

	for point in profile:
		created_points.append(_create_point(point.global_position + offset))

	match mode:
		Mode.EXTRUDE_POINT:
			var beam := _ensure_beam(profile[0], created_points[0], created_beams)
			if beam != null:
				result.append(beam)
			action_name = "E: балка"
		Mode.EXTRUDE_LINE:
			var p0 := profile[0]
			var p1 := profile[1]
			var n0 := created_points[0]
			var n1 := created_points[1]
			_ensure_beam(p0, p1, created_beams)
			_ensure_beam(p1, n1, created_beams)
			_ensure_beam(n1, n0, created_beams)
			_ensure_beam(n0, p0, created_beams)
			var panel := _create_panel([p0, p1, n1, n0], created_panels)
			result.append(panel)
			action_name = "E: плоскость"
		Mode.EXTRUDE_LOOP:
			var bottom := _find_existing_panel(profile)
			if bottom == null:
				_create_panel(profile, created_panels)

			var top := _create_panel(created_points, created_panels)
			for i in profile.size():
				var next := (i + 1) % profile.size()
				_create_panel([profile[i], profile[next], created_points[next], created_points[i]], created_panels)

			for i in profile.size():
				var next := (i + 1) % profile.size()
				_ensure_beam(profile[i], profile[next], created_beams)
				_ensure_beam(created_points[i], created_points[next], created_beams)
				_ensure_beam(profile[i], created_points[i], created_beams)

			result.append(top)
			action_name = "E: куб" if profile.size() == 4 else "E: призма"
		_:
			_cancel_modal()
			return

	var created_structures: Array[EditorEntity] = []
	for beam in created_beams:
		created_structures.append(beam)
	for panel in created_panels:
		created_structures.append(panel)

	_finish_modal()
	_refresh_structures()
	_set_selection(result)
	_push_created(action_name, created_points, created_structures, previous, result)


func _fill() -> void:
	if _mode != Mode.NONE or _structures_root == null:
		return

	var points := _selected_points_only()
	var beams := _selected_beams_only()
	var previous: Array[EditorEntity] = []
	previous.append_array(_selected)

	if points.size() == 2:
		var existing := _find_existing_beam(points[0], points[1])
		if existing != null:
			_set_selection([existing])
			return
		var beam := EditorBeam.create(points[0], points[1])
		beam.name = "Beam_%02d" % (_structures_root.get_child_count() + 1)
		_add_structure(beam)
		var created_beams: Array[EditorBeam] = [beam]
		var created_structures: Array[EditorEntity] = [beam]
		var result: Array[EditorEntity] = [beam]
		var no_points: Array[EditorPoint] = []
		_refresh_structures()
		_set_selection(result)
		_push_created("F: балка", no_points, created_structures, previous, result)
		return

	if points.size() == 3 or points.size() == 4:
		var ordered := _order_profile_points(points)
		var existing := _find_existing_panel(ordered)
		if existing != null:
			_set_selection([existing])
			return
		var created_panels: Array[EditorPanel] = []
		var panel := _create_panel(ordered, created_panels)
		var result: Array[EditorEntity] = [panel]
		var no_points: Array[EditorPoint] = []
		var created_structures: Array[EditorEntity] = [panel]
		var action_name := "F: треугольник" if ordered.size() == 3 else "F: панель"
		_refresh_structures()
		_set_selection(result)
		_push_created(action_name, no_points, created_structures, previous, result)
		return

	if points.size() == 8:
		var ordered := _order_cube_points(points)
		var cube := EditorCube.create(ordered)
		cube.name = "Cube_%02d" % (_structures_root.get_child_count() + 1)
		_add_structure(cube)
		var result: Array[EditorEntity] = [cube]
		var no_points: Array[EditorPoint] = []
		var created_structures: Array[EditorEntity] = [cube]
		_refresh_structures()
		_set_selection(result)
		_push_created("F: куб", no_points, created_structures, previous, result)
		return

	if (beams.size() == 3 or beams.size() == 4) and _selected.size() == beams.size():
		var loop := _beams_to_loop(beams)
		if loop.size() != beams.size():
			return
		var existing := _find_existing_panel(loop)
		if existing != null:
			_set_selection([existing])
			return
		var created_panels: Array[EditorPanel] = []
		var panel := _create_panel(loop, created_panels)
		var result: Array[EditorEntity] = [panel]
		var no_points: Array[EditorPoint] = []
		var created_structures: Array[EditorEntity] = [panel]
		var action_name := "F: треугольник" if loop.size() == 3 else "F: панель"
		_refresh_structures()
		_set_selection(result)
		_push_created(action_name, no_points, created_structures, previous, result)


func _weld_selected() -> void:
	if _mode != Mode.NONE:
		return
	var points := _selected_points_only()
	if points.size() >= 2:
		var center := _average_positions(points)
		_apply_weld(points[0], _sources_from(points, points[0]), center, {}, [points[0]], "M: сварка точек")
		return

	var beams := _selected_beams_only()
	if beams.size() == 2 and _selected.size() == 2:
		_weld_two_beams(beams[0], beams[1])


func _weld_selected_points(into_first: bool) -> void:
	if _mode != Mode.NONE:
		return
	var points := _selected_points_only()
	if points.size() < 2:
		return
	var target := points[0] if into_first else points[points.size() - 1]
	_apply_weld(
		target,
		_sources_from(points, target),
		target.global_position,
		{},
		[target],
		"M: сварка точек"
	)


func _weld_two_beams(first: EditorBeam, second: EditorBeam) -> void:
	if first == second or first.point_a == null or first.point_b == null:
		return
	if second.point_a == null or second.point_b == null:
		return

	var shared: EditorPoint = null
	if first.point_a == second.point_a or first.point_a == second.point_b:
		shared = first.point_a
	elif first.point_b == second.point_a or first.point_b == second.point_b:
		shared = first.point_b

	if shared != null:
		var far_first := first.point_b if first.point_a == shared else first.point_a
		var far_second := second.point_b if second.point_a == shared else second.point_a
		var direction := shared.global_position - far_first.global_position
		if direction.length_squared() < EPSILON:
			direction = first.point_b.global_position - first.point_a.global_position
		if direction.length_squared() < EPSILON:
			return
		direction = direction.normalized()
		var length := shared.global_position.distance_to(far_second.global_position)
		var target_far := shared.global_position + direction * length
		if target_far.is_equal_approx(far_second.global_position):
			return
		var extra := {far_second: target_far}
		_apply_weld(shared, [], shared.global_position, extra, [first, second], "M: выравнивание балок")
		return

	var endpoints_a: Array[EditorPoint] = [first.point_a, first.point_b]
	var endpoints_b: Array[EditorPoint] = [second.point_a, second.point_b]
	var best_a: EditorPoint = null
	var best_b: EditorPoint = null
	var best_distance := INF
	for a in endpoints_a:
		for b in endpoints_b:
			var distance := a.global_position.distance_to(b.global_position)
			if distance < best_distance:
				best_distance = distance
				best_a = a
				best_b = b

	if best_a == null or best_b == null:
		return

	if best_distance <= maxf(WELD_NEAR_DISTANCE, _get_grid_step() * 2.0):
		var midpoint := (best_a.global_position + best_b.global_position) * 0.5
		_apply_weld(best_a, [best_b], midpoint, {}, [first, second], "M: соединение балок")
		return

	var far_a := first.point_b if first.point_a == best_a else first.point_a
	var far_b := second.point_b if second.point_a == best_b else second.point_a
	var direction := best_a.global_position - far_a.global_position
	if direction.length_squared() < EPSILON:
		direction = first.point_b.global_position - first.point_a.global_position
	if direction.length_squared() < EPSILON:
		return
	direction = direction.normalized()
	var length := best_b.global_position.distance_to(far_b.global_position)
	var target_far := best_a.global_position + direction * length
	var extra := {far_b: target_far}
	_apply_weld(best_a, [best_b], best_a.global_position, extra, [first, second], "M: соединение балок")


func _apply_weld(
	target: EditorPoint,
	sources: Array[EditorPoint],
	target_new_position: Vector3,
	extra_moves: Dictionary,
	result_selection: Array[EditorEntity],
	action_name: String
) -> void:
	if target == null or not is_instance_valid(target):
		return

	var filtered_sources: Array[EditorPoint] = []
	for source in sources:
		if is_instance_valid(source) and source != target and not filtered_sources.has(source):
			filtered_sources.append(source)

	var moved: Array[EditorPoint] = [target]
	for key in extra_moves.keys():
		var point := key as EditorPoint
		if point != null and point != target and not filtered_sources.has(point) and not moved.has(point):
			moved.append(point)

	if filtered_sources.is_empty() and moved.size() == 1 and target_new_position.is_equal_approx(target.global_position):
		return

	var previous: Array[EditorEntity] = []
	previous.append_array(_selected)

	var old_positions: Dictionary = {}
	var new_positions: Dictionary = {}
	for point in moved:
		old_positions[point] = point.global_position
	new_positions[target] = target_new_position
	for key in extra_moves.keys():
		var point := key as EditorPoint
		if point != null and moved.has(point):
			new_positions[point] = extra_moves[key]

	var affected: Array[EditorEntity] = []
	var old_refs: Dictionary = {}
	if _structures_root != null:
		for child in _structures_root.get_children():
			var entity := child as EditorEntity
			if entity == null:
				continue
			for point in entity.get_editor_points():
				if filtered_sources.has(point):
					affected.append(entity)
					old_refs[entity] = _snapshot_entity_points(entity)
					break

	_set_selection([])
	for point in moved:
		var new_position: Vector3 = new_positions.get(point, point.global_position)
		point.global_position = new_position
	for source in filtered_sources:
		if source.get_parent() != null:
			source.get_parent().remove_child(source)
	_weld_apply_mutation(affected, old_refs, filtered_sources, target)
	_refresh_structures()
	_set_selection(result_selection)

	var undo_call := func() -> void:
		_set_selection([])
		for point in moved:
			var old_position: Vector3 = old_positions[point]
			point.global_position = old_position
		for source in filtered_sources:
			if source.get_parent() == null:
				_points_root.add_child(source)
		for entity in affected:
			_set_entity_points(entity, old_refs[entity])
			if entity.get_parent() == null:
				_structures_root.add_child(entity)
			entity.refresh_geometry()
		_refresh_structures()
		_set_selection(previous)

	var redo_call := func() -> void:
		_set_selection([])
		for point in moved:
			var new_position: Vector3 = new_positions.get(point, point.global_position)
			point.global_position = new_position
		for source in filtered_sources:
			if source.get_parent() != null:
				source.get_parent().remove_child(source)
		_weld_apply_mutation(affected, old_refs, filtered_sources, target)
		_refresh_structures()
		_set_selection(result_selection)

	_history.push(action_name, undo_call, redo_call)


func _weld_apply_mutation(
	affected: Array[EditorEntity],
	old_refs: Dictionary,
	sources: Array[EditorPoint],
	target: EditorPoint
) -> void:
	for entity in affected:
		_set_entity_points(entity, old_refs[entity])
		_replace_entity_points(entity, sources, target)
		if _entity_is_degenerate(entity):
			if entity.get_parent() != null:
				entity.get_parent().remove_child(entity)
		else:
			if entity.get_parent() == null:
				_structures_root.add_child(entity)
			entity.refresh_geometry()


func _sources_from(points: Array[EditorPoint], target: EditorPoint) -> Array[EditorPoint]:
	var sources: Array[EditorPoint] = []
	for point in points:
		if point != target:
			sources.append(point)
	return sources


func _snapshot_entity_points(entity: EditorEntity) -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	if entity is EditorBeam:
		var beam := entity as EditorBeam
		result.append(beam.point_a)
		result.append(beam.point_b)
	elif entity is EditorPanel:
		result.append_array((entity as EditorPanel).points)
	elif entity is EditorCube:
		result.append_array((entity as EditorCube).points)
	return result


func _set_entity_points(entity: EditorEntity, refs: Array) -> void:
	if entity is EditorBeam:
		var beam := entity as EditorBeam
		if refs.size() >= 2:
			beam.point_a = refs[0] as EditorPoint
			beam.point_b = refs[1] as EditorPoint
	elif entity is EditorPanel:
		var panel := entity as EditorPanel
		panel.points.clear()
		for ref in refs:
			panel.points.append(ref as EditorPoint)
	elif entity is EditorCube:
		var cube := entity as EditorCube
		cube.points.clear()
		for ref in refs:
			cube.points.append(ref as EditorPoint)


func _replace_entity_points(
	entity: EditorEntity,
	sources: Array[EditorPoint],
	target: EditorPoint
) -> void:
	if entity is EditorBeam:
		var beam := entity as EditorBeam
		if sources.has(beam.point_a):
			beam.point_a = target
		if sources.has(beam.point_b):
			beam.point_b = target
	elif entity is EditorPanel:
		var panel := entity as EditorPanel
		for i in panel.points.size():
			if sources.has(panel.points[i]):
				panel.points[i] = target
	elif entity is EditorCube:
		var cube := entity as EditorCube
		for i in cube.points.size():
			if sources.has(cube.points[i]):
				cube.points[i] = target


func _entity_is_degenerate(entity: EditorEntity) -> bool:
	if entity is EditorBeam:
		var beam := entity as EditorBeam
		return beam.point_a == null or beam.point_b == null or beam.point_a == beam.point_b
	if entity is EditorPanel:
		return _has_duplicate_points((entity as EditorPanel).points) or (entity as EditorPanel).points.size() < 3
	if entity is EditorCube:
		var cube := entity as EditorCube
		return _has_duplicate_points(cube.points) or cube.points.size() != 8
	return false


func _has_duplicate_points(points: Array[EditorPoint]) -> bool:
	for i in points.size():
		if points[i] == null:
			return true
		for j in range(i + 1, points.size()):
			if points[i] == points[j]:
				return true
	return false


func _push_created(
	action_name: String,
	created_points: Array[EditorPoint],
	created_structures: Array[EditorEntity],
	previous_selection: Array[EditorEntity],
	result_selection: Array[EditorEntity]
) -> void:
	var undo_call := func() -> void:
		_set_selection([])
		for structure in created_structures:
			if is_instance_valid(structure) and structure.get_parent() != null:
				structure.get_parent().remove_child(structure)
		for point in created_points:
			if is_instance_valid(point) and point.get_parent() != null:
				point.get_parent().remove_child(point)
		_refresh_structures()
		_set_selection(previous_selection)

	var redo_call := func() -> void:
		for point in created_points:
			if is_instance_valid(point) and point.get_parent() == null:
				_points_root.add_child(point)
		for structure in created_structures:
			if is_instance_valid(structure) and structure.get_parent() == null:
				_structures_root.add_child(structure)
		_refresh_structures()
		_set_selection(result_selection)

	_history.push(action_name, undo_call, redo_call)


func _delete_selected() -> void:
	if _selected.is_empty() or _points_root == null or _structures_root == null:
		return

	var points_to_delete: Array[EditorPoint] = []
	var structures_to_delete: Array[EditorEntity] = []
	for entity in _selected:
		if entity is EditorPoint:
			points_to_delete.append(entity as EditorPoint)
		else:
			structures_to_delete.append(entity)

	for child in _structures_root.get_children():
		var structure := child as EditorEntity
		if structure == null or structures_to_delete.has(structure):
			continue
		for point in structure.get_editor_points():
			if points_to_delete.has(point):
				structures_to_delete.append(structure)
				break

	var previous: Array[EditorEntity] = []
	previous.append_array(_selected)
	_set_hovered(null)
	_set_selection([])

	for structure in structures_to_delete:
		if structure.get_parent() != null:
			structure.get_parent().remove_child(structure)
	for point in points_to_delete:
		if point.get_parent() != null:
			point.get_parent().remove_child(point)

	var total := points_to_delete.size() + structures_to_delete.size()
	var undo_call := func() -> void:
		for point in points_to_delete:
			if point.get_parent() == null:
				_points_root.add_child(point)
		for structure in structures_to_delete:
			if structure.get_parent() == null:
				_structures_root.add_child(structure)
		_refresh_structures()
		_set_selection(previous)

	var redo_call := func() -> void:
		_set_selection([])
		for structure in structures_to_delete:
			if structure.get_parent() != null:
				structure.get_parent().remove_child(structure)
		for point in points_to_delete:
			if point.get_parent() != null:
				point.get_parent().remove_child(point)
		_refresh_structures()

	_history.push("X: удаление (%d)" % total, undo_call, redo_call)


func _confirm_modal() -> void:
	match _mode:
		Mode.GRAB:
			_confirm_grab()
		Mode.EXTRUDE_POINT, Mode.EXTRUDE_LINE, Mode.EXTRUDE_LOOP:
			_confirm_extrude()


func _cancel_modal() -> void:
	if _mode == Mode.GRAB:
		for point in _grab_points:
			var old_position: Vector3 = _grab_old_positions[point]
			point.global_position = old_position
		_refresh_structures()
	_finish_modal()


func _finish_modal() -> void:
	_mode = Mode.NONE
	_axis_lock = -1
	_grab_points.clear()
	_grab_old_positions.clear()
	_grab_delta = Vector3.ZERO
	_grab_moved = false
	_extrude_profile.clear()
	_extrude_preview_positions.clear()
	_extrude_offset = Vector3.ZERO
	_extrude_valid = false
	_hide_preview()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	context_changed.emit()


func _set_axis_lock(axis: int) -> void:
	_axis_lock = -1 if _axis_lock == axis else axis
	var mouse := get_viewport().get_mouse_position()
	if _mode == Mode.GRAB:
		_update_grab(mouse)
	elif _mode == Mode.EXTRUDE_POINT or _mode == Mode.EXTRUDE_LINE or _mode == Mode.EXTRUDE_LOOP:
		_update_extrude(mouse)
	context_changed.emit()


func _axis_vector() -> Vector3:
	match _axis_lock:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		2:
			return Vector3.BACK
	return Vector3.ZERO


func _axis_suffix() -> String:
	match _axis_lock:
		0:
			return " [X]"
		1:
			return " [Y]"
		2:
			return " [Z]"
	return ""


func _build_preview() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "Preview"
	_preview_root.visible = false
	add_child(_preview_root)

	_preview_surface_material = StandardMaterial3D.new()
	_preview_surface_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_surface_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_surface_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_preview_surface_material.albedo_color = Color(0.3, 0.75, 1.0, 0.28)
	_preview_surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_preview_point_material = StandardMaterial3D.new()
	_preview_point_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_point_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_point_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_preview_point_material.albedo_color = Color(0.35, 0.8, 1.0, 0.75)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.045
	cylinder.bottom_radius = 0.045
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	cylinder.rings = 1

	_preview_beam = MeshInstance3D.new()
	_preview_beam.mesh = cylinder
	_preview_beam.material_override = _preview_surface_material
	_preview_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_root.add_child(_preview_beam)

	for i in 6:
		var face := MeshInstance3D.new()
		face.material_override = _preview_surface_material
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview_root.add_child(face)
		_preview_faces.append(face)

	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 16
	sphere.rings = 8

	for i in 4:
		var ghost := MeshInstance3D.new()
		ghost.mesh = sphere
		ghost.material_override = _preview_point_material
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview_root.add_child(ghost)
		_preview_points.append(ghost)


func _preview_begin() -> void:
	_preview_root.visible = true
	_preview_beam.visible = false
	for face in _preview_faces:
		face.visible = false
		face.mesh = null
	for node in _preview_points:
		node.visible = false


func _preview_show_face(vertices: PackedVector3Array) -> void:
	for face in _preview_faces:
		if not face.visible:
			face.mesh = EditorGeometry.make_panel_mesh(vertices)
			face.visible = true
			return


func _preview_show_beam(a: Vector3, b: Vector3) -> void:
	if a.distance_squared_to(b) < EPSILON:
		return
	_preview_beam.global_transform = EditorGeometry.beam_transform(a, b)
	_preview_beam.visible = true


func _preview_show_points(positions: Array[Vector3]) -> void:
	for i in _preview_points.size():
		var node := _preview_points[i]
		if i < positions.size():
			node.global_position = positions[i]
			node.visible = true
		else:
			node.visible = false


func _hide_preview() -> void:
	if _preview_root == null:
		return
	_preview_root.visible = false
	_preview_beam.visible = false
	for face in _preview_faces:
		face.mesh = null
		face.visible = false
	for node in _preview_points:
		node.visible = false


func _add_structure(structure: EditorEntity) -> void:
	if structure.get_parent() == null:
		_structures_root.add_child(structure)


func _create_point(local_position: Vector3) -> EditorPoint:
	var max_id := 0
	for child in _points_root.get_children():
		var existing := child as EditorPoint
		if existing != null:
			max_id = maxi(max_id, existing.point_id)

	var point := EditorPoint.new()
	point.point_id = max_id + 1
	point.name = "Point%02d" % point.point_id
	point.position = local_position
	_points_root.add_child(point)
	point.global_position = local_position
	return point


func _create_panel(points: Array[EditorPoint], created: Array[EditorPanel]) -> EditorPanel:
	var panel := EditorPanel.create(points.duplicate())
	panel.name = "Panel_%02d" % (_structures_root.get_child_count() + 1)
	_add_structure(panel)
	if created != null:
		created.append(panel)
	return panel


func _ensure_beam(
	a: EditorPoint,
	b: EditorPoint,
	created: Array[EditorBeam]
) -> EditorBeam:
	if a == null or b == null or a == b:
		return null
	var existing := _find_existing_beam(a, b)
	if existing != null:
		return existing
	var beam := EditorBeam.create(a, b)
	beam.name = "Beam_%02d" % (_structures_root.get_child_count() + 1)
	_add_structure(beam)
	if created != null:
		created.append(beam)
	return beam


func _find_existing_beam(a: EditorPoint, b: EditorPoint) -> EditorBeam:
	if _structures_root == null:
		return null
	for child in _structures_root.get_children():
		var beam := child as EditorBeam
		if beam == null:
			continue
		if (beam.point_a == a and beam.point_b == b) or (beam.point_a == b and beam.point_b == a):
			return beam
	return null


func _find_existing_panel(points: Array[EditorPoint]) -> EditorPanel:
	if _structures_root == null or points.size() < 3:
		return null
	for child in _structures_root.get_children():
		var panel := child as EditorPanel
		if panel != null and _same_point_set(panel.points, points):
			return panel
	return null


func _same_point_set(first: Array[EditorPoint], second: Array[EditorPoint]) -> bool:
	if first.size() != second.size():
		return false
	for point in first:
		if not second.has(point):
			return false
	return true


func _refresh_structures() -> void:
	if _structures_root == null:
		return
	for child in _structures_root.get_children():
		var structure := child as EditorEntity
		if structure != null:
			structure.refresh_geometry()


func _collect_selected_points() -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	for entity in _selected:
		if not is_instance_valid(entity):
			continue
		for point in entity.get_editor_points():
			if is_instance_valid(point) and not result.has(point):
				result.append(point)
	return result


func _selected_points_only() -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	for entity in _selected:
		if entity is EditorPoint:
			result.append(entity as EditorPoint)
	return result


func _selected_beams_only() -> Array[EditorBeam]:
	var result: Array[EditorBeam] = []
	for entity in _selected:
		if entity is EditorBeam:
			result.append(entity as EditorBeam)
	return result


func _selected_panels_only() -> Array[EditorPanel]:
	var result: Array[EditorPanel] = []
	for entity in _selected:
		if entity is EditorPanel:
			result.append(entity as EditorPanel)
	return result


func _order_profile_points(points: Array[EditorPoint]) -> Array[EditorPoint]:
	var center := _average_positions(points)
	var vertices := PackedVector3Array()
	for point in points:
		vertices.append(point.global_position)
	var normal := EditorGeometry.polygon_normal(vertices)

	var u := Vector3.RIGHT
	var best_length := 0.0
	for point in points:
		var direction := point.global_position - center
		direction -= normal * direction.dot(normal)
		if direction.length_squared() > best_length:
			best_length = direction.length_squared()
			u = direction.normalized()
	if best_length < EPSILON:
		u = normal.cross(Vector3.UP)
		if u.length_squared() < EPSILON:
			u = normal.cross(Vector3.RIGHT)
		u = u.normalized()
	var v := normal.cross(u).normalized()

	var sorted: Array[EditorPoint] = []
	sorted.append_array(points)
	sorted.sort_custom(func(a: EditorPoint, b: EditorPoint) -> bool:
		var da := a.global_position - center
		var db := b.global_position - center
		return atan2(da.dot(v), da.dot(u)) < atan2(db.dot(v), db.dot(u))
	)
	return sorted


func _order_cube_points(points: Array[EditorPoint]) -> Array[EditorPoint]:
	var center := _average_positions(points)
	var axis := Vector3.UP
	var best_variance := -1.0
	for candidate in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var variance := 0.0
		for point in points:
			var distance := (point.global_position - center).dot(candidate)
			variance += distance * distance
		if variance > best_variance:
			best_variance = variance
			axis = candidate

	var sorted: Array[EditorPoint] = []
	sorted.append_array(points)
	sorted.sort_custom(func(a: EditorPoint, b: EditorPoint) -> bool:
		return (a.global_position - center).dot(axis) < (b.global_position - center).dot(axis)
	)

	var ring_a: Array[EditorPoint] = []
	var ring_b: Array[EditorPoint] = []
	ring_a.append_array(sorted.slice(0, 4))
	ring_b.append_array(sorted.slice(4, 8))

	var basis := _ring_basis(axis)
	var u: Vector3 = basis[0]
	var v: Vector3 = basis[1]
	_sort_ring(ring_a, u, v)
	_sort_ring(ring_b, u, v)
	ring_b = _align_rings(ring_a, ring_b)

	var result: Array[EditorPoint] = []
	result.append_array(ring_a)
	result.append_array(ring_b)
	return result


func _beams_to_loop(beams: Array[EditorBeam]) -> Array[EditorPoint]:
	if beams.size() < 3 or beams.size() > 4:
		return []
	var points: Array[EditorPoint] = []
	var adjacency: Dictionary = {}

	for beam in beams:
		if beam.point_a == null or beam.point_b == null:
			return []
		for point in [beam.point_a, beam.point_b]:
			if not points.has(point):
				points.append(point)
				adjacency[point] = []
		adjacency[beam.point_a].append(beam.point_b)
		adjacency[beam.point_b].append(beam.point_a)

	if points.size() != beams.size():
		return []
	for point in points:
		var neighbors: Array = adjacency[point]
		if neighbors.size() != 2:
			return []

	var start := points[0]
	var ordered: Array[EditorPoint] = []
	var previous: EditorPoint = null
	var current: EditorPoint = start
	for i in points.size():
		ordered.append(current)
		var neighbors: Array = adjacency[current]
		var next := neighbors[0] as EditorPoint
		if next == previous:
			next = neighbors[1] as EditorPoint
		previous = current
		current = next

	if current != start:
		return []
	return ordered


func _ring_basis(axis: Vector3) -> Array[Vector3]:
	var u := axis.cross(Vector3.UP)
	if u.length_squared() < EPSILON:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	var result: Array[Vector3] = [u, v]
	return result


func _sort_ring(ring: Array[EditorPoint], u: Vector3, v: Vector3) -> void:
	var center := _average_positions(ring)
	ring.sort_custom(func(a: EditorPoint, b: EditorPoint) -> bool:
		var da := a.global_position - center
		var db := b.global_position - center
		return atan2(da.dot(v), da.dot(u)) < atan2(db.dot(v), db.dot(u))
	)


func _align_rings(
	ring_a: Array[EditorPoint],
	ring_b: Array[EditorPoint]
) -> Array[EditorPoint]:
	var best := ring_b
	var best_score := INF
	for shift in 4:
		var candidate: Array[EditorPoint] = []
		for i in 4:
			candidate.append(ring_b[(i + shift) % 4])
		var score := 0.0
		for i in 4:
			score += ring_a[i].global_position.distance_squared_to(candidate[i].global_position)
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _average_positions(points: Array) -> Vector3:
	var total := Vector3.ZERO
	if points.is_empty():
		return total
	for point in points:
		total += (point as Node3D).global_position
	return total / float(points.size())


func _mouse_plane_point(screen_position: Vector2, plane: Plane) -> Variant:
	if _camera == null:
		return null
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	return plane.intersects_ray(origin, direction)


func _snap_vector(value: Vector3, step: float) -> Vector3:
	var safe_step := maxf(step, 0.001)
	return Vector3(
		snappedf(value.x, safe_step),
		snappedf(value.y, safe_step),
		snappedf(value.z, safe_step)
	)


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


func get_context_hint() -> String:
	match _mode:
		Mode.GRAB:
			return "G · движение%s — ЛКМ подтвердить · ПКМ / Esc отменить" % _axis_suffix()
		Mode.EXTRUDE_POINT:
			return "E · балка%s — ЛКМ создать · ПКМ / Esc отменить" % _axis_suffix()
		Mode.EXTRUDE_LINE:
			return "E · плоскость%s — ЛКМ создать · ПКМ / Esc отменить" % _axis_suffix()
		Mode.EXTRUDE_LOOP:
			var label := "куб" if _extrude_profile.size() == 4 else "призма"
			return "E · %s%s — ЛКМ создать · ПКМ / Esc отменить" % [label, _axis_suffix()]

	if _selected.is_empty():
		return "ЛКМ — выбрать точку, балку или грань"

	var points := _selected_points_only()
	var beams := _selected_beams_only()

	if _selected.size() == 1:
		var entity := _selected[0]
		if entity is EditorPoint:
			return "E — создать балку · G — двигать · X — удалить"
		if entity is EditorBeam:
			return "E — плоскость · M (2 балки) — соединить · G — двигать"
		if entity is EditorPanel:
			var panel := entity as EditorPanel
			if panel.points.size() == 3:
				return "E — призма · G — двигать · X — удалить"
			return "E — куб · G — двигать · X — удалить"
		if entity is EditorCube:
			return "G — двигать · X — удалить"

	if beams.size() == 2 and _selected.size() == 2:
		return "M — соединить концы / выровнять балки · G — двигать"

	if (beams.size() == 3 or beams.size() == 4) and _selected.size() == beams.size():
		var loop := _beams_to_loop(beams)
		if loop.size() == beams.size():
			if beams.size() == 3:
				return "E — призма · F — треугольник · G — двигать"
			return "E — куб · F — панель · G — двигать"

	match points.size():
		2:
			return "E — плоскость · F — балка · M — сварить"
		3:
			return "E — призма · F — треугольник · M — сварить"
		4:
			return "E — куб · F — панель · M — сварить"
		8:
			return "F — куб · G — двигать · M — сварить"

	if points.size() > 1:
		return "M — сварить точки · G — двигать"
	return "G — двигать · X — удалить"


func is_modal_active() -> bool:
	return _mode != Mode.NONE


func get_selected_points() -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	for entity in _selected:
		if entity is EditorPoint:
			result.append(entity as EditorPoint)
	return result


func get_selected_objects() -> Array[EditorEntity]:
	var result: Array[EditorEntity] = []
	result.append_array(_selected)
	return result


func get_selected_count() -> int:
	return _selected.size()


func get_point_count() -> int:
	if _points_root == null:
		return 0
	return _points_root.get_child_count()


func get_structure_count() -> int:
	if _structures_root == null:
		return 0
	return _structures_root.get_child_count()


func get_undo_name() -> String:
	return _history.get_undo_name()


func get_redo_name() -> String:
	return _history.get_redo_name()
