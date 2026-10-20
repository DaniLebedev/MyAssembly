class_name EditorJoint
extends EditorEntity
## Базовая деталь соединения: два крепления и ось между ними.

const BODY_COLOR := Color(0.46, 0.55, 0.68)
const ACCENT_COLOR := Color(1.0, 0.58, 0.18)
const HOVER_COLOR := Color(0.48, 0.72, 0.92)
const SELECTED_COLOR := Color(1.0, 0.56, 0.12)

var point_a: EditorPoint
var point_b: EditorPoint

var _visual_root: Node3D
var _body: StaticBody3D
var _collision: CollisionShape3D
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _collision_radius := 0.22


func _ready() -> void:
	add_to_group("editor_structures")
	_ensure_visuals()
	refresh_geometry()
	_refresh_visual()


func get_editor_points() -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	if point_a != null:
		result.append(point_a)
	if point_b != null:
		result.append(point_b)
	return result


func get_attachment_points() -> Array[EditorPoint]:
	return get_editor_points()


func get_axis_world() -> Vector3:
	if point_a == null or point_b == null:
		return Vector3.RIGHT
	return (point_b.global_position - point_a.global_position).normalized()


func get_joint_kind() -> String:
	return "joint"


func refresh_geometry() -> void:
	if point_a == null or point_b == null or _collision == null:
		visible = false
		return
	var a := point_a.global_position
	var b := point_b.global_position
	var delta := b - a
	var length := delta.length()
	if length < 0.001:
		visible = false
		return

	var axis := delta / length
	global_transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), (a + b) * 0.5)
	visible = true

	var shape := CylinderShape3D.new()
	shape.radius = _collision_radius
	shape.height = length
	_collision.shape = shape
	_update_visual(length)


func _ensure_visuals() -> void:
	if _visual_root != null:
		return

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	_body = StaticBody3D.new()
	_body.name = "StaticBody"
	add_child(_body)

	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	_body.add_child(_collision)

	_build_visual()


func _build_visual() -> void:
	pass


func _update_visual(_length: float) -> void:
	pass


func _make_material(
	base_color: Color,
	metallic: float = 0.25,
	roughness: float = 0.35
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = base_color
	material.metallic = metallic
	material.roughness = roughness
	_materials.append(material)
	_base_colors.append(base_color)
	return material


func _add_cylinder(
	radius: float,
	height: float,
	material: Material,
	node_name: String
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(instance)
	return instance


func _add_box(size: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(instance)
	return instance


func _add_torus(
	inner_radius: float,
	outer_radius: float,
	material: Material,
	node_name: String
) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 24
	mesh.ring_segments = 12

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(instance)
	return instance


func _refresh_visual() -> void:
	for i in _materials.size():
		var material := _materials[i]
		var base := _base_colors[i]
		var color := base
		var emission := Color.BLACK
		var energy := 0.0
		if is_selected:
			color = base.lerp(SELECTED_COLOR, 0.35)
			emission = Color(1.0, 0.4, 0.05)
			energy = 0.7
		elif is_hovered:
			color = base.lerp(HOVER_COLOR, 0.4)
			emission = Color(0.2, 0.6, 1.0)
			energy = 0.3
		material.albedo_color = color
		material.emission_enabled = energy > 0.0
		material.emission = emission
		material.emission_energy_multiplier = energy
