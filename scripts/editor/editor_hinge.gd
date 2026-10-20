class_name EditorHinge
extends EditorJoint
## Шарнир: два крепления на концах и ось вращения между ними.

var _pin: MeshInstance3D
var _hub: MeshInstance3D
var _plate_a: MeshInstance3D
var _plate_b: MeshInstance3D
var _cap_a: MeshInstance3D
var _cap_b: MeshInstance3D


static func create(a: EditorPoint, b: EditorPoint) -> EditorHinge:
	var hinge := EditorHinge.new()
	hinge.point_a = a
	hinge.point_b = b
	return hinge


func get_joint_kind() -> String:
	return "hinge"


func _build_visual() -> void:
	_collision_radius = 0.22
	var steel := _make_material(Color(0.58, 0.66, 0.78), 0.55, 0.26)
	var accent := _make_material(ACCENT_COLOR, 0.32, 0.3)

	_pin = _add_cylinder(0.055, 1.0, steel, "Pin")
	_hub = _add_torus(0.12, 0.21, accent, "Hub")
	_plate_a = _add_box(Vector3(0.36, 0.08, 0.30), steel, "PlateA")
	_plate_b = _add_box(Vector3(0.36, 0.08, 0.30), steel, "PlateB")
	_cap_a = _add_cylinder(0.15, 0.055, accent, "CapA")
	_cap_b = _add_cylinder(0.15, 0.055, accent, "CapB")


func _update_visual(length: float) -> void:
	var half := length * 0.5
	_pin.scale = Vector3(1.0, length, 1.0)
	_hub.position = Vector3.ZERO
	_plate_a.position = Vector3(0.0, -half + 0.045, 0.0)
	_plate_b.position = Vector3(0.0, half - 0.045, 0.0)
	_cap_a.position = Vector3(0.0, -half + 0.015, 0.0)
	_cap_b.position = Vector3(0.0, half - 0.015, 0.0)
