class_name EditorMotor
extends EditorJoint
## Мотор: крепление корпуса и выходного вала, скорость и крутящий момент.

@export var speed := 2.0
@export var torque := 24.0
@export var enabled := false

var _motor_body: MeshInstance3D
var _shaft: MeshInstance3D
var _ring: MeshInstance3D
var _plate_a: MeshInstance3D
var _plate_b: MeshInstance3D


static func create(a: EditorPoint, b: EditorPoint) -> EditorMotor:
	var motor := EditorMotor.new()
	motor.point_a = a
	motor.point_b = b
	return motor


func get_joint_kind() -> String:
	return "motor"


func set_motor_enabled(value: bool) -> void:
	enabled = value
	_refresh_visual()


func get_parameters_text() -> String:
	return "%.2f рад/с · %.1f Н·м" % [speed, torque]


func _build_visual() -> void:
	_collision_radius = 0.30
	var shell := _make_material(Color(0.42, 0.48, 0.60), 0.45, 0.3)
	var accent := _make_material(ACCENT_COLOR, 0.3, 0.28)
	var shaft := _make_material(Color(0.7, 0.76, 0.86), 0.7, 0.2)

	_motor_body = _add_cylinder(0.28, 1.0, shell, "MotorBody")
	_shaft = _add_cylinder(0.07, 1.0, shaft, "Shaft")
	_ring = _add_torus(0.13, 0.22, accent, "MotorRing")
	_plate_a = _add_box(Vector3(0.34, 0.08, 0.30), shell, "PlateA")
	_plate_b = _add_box(Vector3(0.34, 0.08, 0.30), shell, "PlateB")


func _update_visual(length: float) -> void:
	var half := length * 0.5
	_motor_body.scale = Vector3(1.0, length * 0.52, 1.0)
	_motor_body.position = Vector3(0.0, -length * 0.08, 0.0)
	_shaft.scale = Vector3(1.0, length * 0.94, 1.0)
	_ring.position = Vector3(0.0, length * 0.22, 0.0)
	_plate_a.position = Vector3(0.0, -half + 0.045, 0.0)
	_plate_b.position = Vector3(0.0, half - 0.045, 0.0)


func _refresh_visual() -> void:
	super._refresh_visual()
	if _ring != null and is_instance_valid(_ring):
		_ring.visible = enabled
