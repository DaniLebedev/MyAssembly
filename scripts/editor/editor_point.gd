class_name EditorPoint
extends EditorEntity
## Точка стыковки — базовый объект редактора.

const PICK_RADIUS := 0.2
const BASE_COLOR := Color(0.7, 0.84, 1.0)
const HOVER_COLOR := Color(0.55, 0.82, 1.0)
const SELECTED_COLOR := Color(1.0, 0.62, 0.16)

var point_id: int = 0

var _mesh: MeshInstance3D
var _halo: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("editor_points")
	_ensure_visuals()
	_refresh_visual()


static func snap_to_grid(value: Vector3, step: float) -> Vector3:
	var safe_step := maxf(step, 0.001)
	return Vector3(
		snappedf(value.x, safe_step),
		snappedf(value.y, safe_step),
		snappedf(value.z, safe_step)
	)


func get_editor_points() -> Array[EditorPoint]:
	var result: Array[EditorPoint] = []
	result.append(self)
	return result


func _ensure_visuals() -> void:
	if _mesh != null:
		return

	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 24
	sphere.rings = 12

	_material = StandardMaterial3D.new()
	_material.albedo_color = BASE_COLOR
	_material.metallic = 0.25
	_material.roughness = 0.28

	_mesh = MeshInstance3D.new()
	_mesh.name = "Visual"
	_mesh.mesh = sphere
	_mesh.material_override = _material
	add_child(_mesh)

	var halo_sphere := SphereMesh.new()
	halo_sphere.radius = 0.19
	halo_sphere.height = 0.38
	halo_sphere.radial_segments = 24
	halo_sphere.rings = 12

	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.albedo_color = Color(1.0, 0.5, 0.08, 0.22)
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_halo = MeshInstance3D.new()
	_halo.name = "SelectionHalo"
	_halo.mesh = halo_sphere
	_halo.material_override = halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.visible = false
	add_child(_halo)


func _refresh_visual() -> void:
	if _mesh == null:
		return

	var color := BASE_COLOR
	var emission := Color(0.12, 0.3, 0.55)
	var energy := 0.3

	if is_selected:
		color = SELECTED_COLOR
		emission = Color(1.0, 0.38, 0.05)
		energy = 1.8
	elif is_hovered:
		color = HOVER_COLOR
		emission = Color(0.2, 0.6, 1.0)
		energy = 0.6

	_material.albedo_color = color
	_material.emission_enabled = energy > 0.0
	_material.emission = emission
	_material.emission_energy_multiplier = energy
	_mesh.scale = Vector3.ONE * (1.22 if is_selected else 1.0)
	_halo.visible = is_selected
