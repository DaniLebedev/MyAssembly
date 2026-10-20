class_name EditorBeam
extends EditorEntity
## Балка между двумя точками. Геометрия перестраивается при движении точек.

const RADIUS := 0.055
const BASE_COLOR := Color(0.66, 0.73, 0.82)
const HOVER_COLOR := Color(0.55, 0.82, 1.0)
const SELECTED_COLOR := Color(1.0, 0.56, 0.12)

var point_a: EditorPoint
var point_b: EditorPoint

var _mesh: MeshInstance3D
var _material: StandardMaterial3D


static func create(a: EditorPoint, b: EditorPoint) -> EditorBeam:
	var beam := EditorBeam.new()
	beam.point_a = a
	beam.point_b = b
	return beam


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


func refresh_geometry() -> void:
	if point_a == null or point_b == null or _mesh == null:
		return
	var a := point_a.global_position
	var b := point_b.global_position
	_mesh.visible = a.distance_squared_to(b) > 0.000001
	global_transform = EditorGeometry.beam_transform(a, b)


func _ensure_visuals() -> void:
	if _mesh != null:
		return

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS
	cylinder.bottom_radius = RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 12
	cylinder.rings = 1

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = BASE_COLOR

	_mesh = MeshInstance3D.new()
	_mesh.name = "Visual"
	_mesh.mesh = cylinder
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		energy = 1.3
	elif is_hovered:
		color = HOVER_COLOR
		emission = Color(0.2, 0.6, 1.0)
		energy = 0.5
	_material.albedo_color = color
	_material.emission_enabled = energy > 0.0
	_material.emission = emission
	_material.emission_energy_multiplier = energy
