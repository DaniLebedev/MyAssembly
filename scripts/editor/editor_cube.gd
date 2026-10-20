class_name EditorCube
extends EditorEntity
## Объём по восьми точкам: две четвёрки по периметру.

const BASE_COLOR := Color(0.26, 0.34, 0.44)
const HOVER_COLOR := Color(0.48, 0.72, 0.92)
const SELECTED_COLOR := Color(1.0, 0.56, 0.12)

var points: Array[EditorPoint] = []

var _mesh: MeshInstance3D
var _material: StandardMaterial3D


static func create(cube_points: Array[EditorPoint]) -> EditorCube:
	var cube := EditorCube.new()
	cube.points = cube_points.duplicate()
	return cube


func _ready() -> void:
	add_to_group("editor_structures")
	_ensure_visuals()
	refresh_geometry()
	_refresh_visual()


func get_editor_points() -> Array[EditorPoint]:
	return points.duplicate()


func refresh_geometry() -> void:
	if _mesh == null or points.size() != 8:
		return
	var vertices := PackedVector3Array()
	for point in points:
		if point == null:
			return
		vertices.append(point.global_position)
	_mesh.mesh = EditorGeometry.make_cube_mesh(vertices)


func _ensure_visuals() -> void:
	if _mesh != null:
		return

	_material = StandardMaterial3D.new()
	_material.albedo_color = BASE_COLOR
	_material.metallic = 0.35
	_material.roughness = 0.45
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh = MeshInstance3D.new()
	_mesh.name = "Visual"
	_mesh.material_override = _material
	add_child(_mesh)


func _refresh_visual() -> void:
	if _material == null:
		return
	var color := BASE_COLOR
	var emission := Color.BLACK
	var energy := 0.0
	if is_selected:
		color = SELECTED_COLOR
		emission = Color(1.0, 0.4, 0.05)
		energy = 1.0
	elif is_hovered:
		color = HOVER_COLOR
		emission = Color(0.2, 0.6, 1.0)
		energy = 0.4
	_material.albedo_color = color
	_material.emission_enabled = energy > 0.0
	_material.emission = emission
	_material.emission_energy_multiplier = energy
