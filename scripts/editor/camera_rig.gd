class_name EditorCameraRig
extends Node3D
## Орбитальная камера редактора: ПКМ — вращение, СКМ — панорама,
## колесо — зум, Home — возврат к исходному виду.

@export var initial_target := Vector3(0.0, 1.0, 0.0)
@export var initial_yaw_degrees := 35.0
@export var initial_pitch_degrees := 30.0
@export var initial_distance := 8.5

@export var min_distance := 2.5
@export var max_distance := 90.0
@export var orbit_sensitivity := 0.28
@export var pan_sensitivity := 0.0016
@export var zoom_factor := 1.12
@export var smoothing := 22.0

var _target := Vector3.ZERO
var _goal_target := Vector3.ZERO
var _yaw := 0.0
var _goal_yaw := 0.0
var _pitch := 0.0
var _goal_pitch := 0.0
var _distance := 10.0
var _goal_distance := 10.0

var _orbiting := false
var _panning := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_target = initial_target
	_goal_target = initial_target
	_yaw = deg_to_rad(initial_yaw_degrees)
	_goal_yaw = _yaw
	_pitch = deg_to_rad(initial_pitch_degrees)
	_goal_pitch = _pitch
	_distance = initial_distance
	_goal_distance = initial_distance
	_apply_transform()
	camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_HOME or key.physical_keycode == KEY_HOME):
			reset_view()


func _process(delta: float) -> void:
	var weight := 1.0 - exp(-smoothing * delta)
	_target = _target.lerp(_goal_target, weight)
	_yaw = lerpf(_yaw, _goal_yaw, weight)
	_pitch = lerpf(_pitch, _goal_pitch, weight)
	_distance = lerpf(_distance, _goal_distance, weight)
	_apply_transform()


func reset_view() -> void:
	_goal_target = initial_target
	_goal_yaw = deg_to_rad(initial_yaw_degrees)
	_goal_pitch = deg_to_rad(initial_pitch_degrees)
	_goal_distance = initial_distance


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			if not _orbiting and not _panning:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			if not _panning and not _orbiting:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom(-1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom(1.0)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _orbiting:
		_goal_yaw -= deg_to_rad(event.relative.x * orbit_sensitivity)
		_goal_pitch = clampf(
			_goal_pitch + deg_to_rad(event.relative.y * orbit_sensitivity),
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)
	if _panning:
		_pan(event.relative)


func _pan(relative: Vector2) -> void:
	var camera_basis := camera.global_basis
	var right := camera_basis.x.normalized()
	var up := camera_basis.y.normalized()
	var amount := _distance * pan_sensitivity
	_goal_target += (-right * relative.x + up * relative.y) * amount


func _zoom(direction: float) -> void:
	_goal_distance = clampf(
		_goal_distance * pow(zoom_factor, direction),
		min_distance,
		max_distance
	)


func _apply_transform() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance
	camera.global_position = _target + offset
	if camera.global_position.distance_squared_to(_target) > 0.0001:
		camera.look_at(_target, Vector3.UP)
