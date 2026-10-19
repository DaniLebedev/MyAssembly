class_name EditorGrid
extends Node3D
## Объёмная сетка-ориентир: шейдерная плоскость XZ и цветные оси X/Y/Z.

@export var grid_step := 0.5:
	set(value):
		grid_step = clampf(value, 0.05, 5.0)
		_apply_settings()
@export var major_every := 10
@export var half_extent := 150.0
@export var fade_start := 40.0
@export var fade_end := 110.0
@export var horizontal_axis_length := 3.2
@export var vertical_axis_length := 3.0

const GRID_SHADER := preload("res://shaders/editor_grid.gdshader")
const COLOR_X := Color(1.0, 0.32, 0.3)
const COLOR_Y := Color(0.42, 1.0, 0.55)
const COLOR_Z := Color(0.38, 0.64, 1.0)

var _material: ShaderMaterial


func _ready() -> void:
	_build_plane()
	_build_axes()
	_apply_settings()


func _build_plane() -> void:
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(half_extent * 2.0, half_extent * 2.0)

	_material = ShaderMaterial.new()
	_material.shader = GRID_SHADER

	var plane := MeshInstance3D.new()
	plane.name = "GridPlane"
	plane.mesh = plane_mesh
	plane.material_override = _material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plane)


func _build_axes() -> void:
	var axes := Node3D.new()
	axes.name = "Axes"
	axes.position.y = 0.015
	add_child(axes)

	_add_axis(axes, Vector3.RIGHT, horizontal_axis_length, COLOR_X, "X", true)
	_add_axis(axes, Vector3.UP, vertical_axis_length, COLOR_Y, "Y", false)
	_add_axis(axes, Vector3.BACK, horizontal_axis_length, COLOR_Z, "Z", true)

	_add_axis_label(axes, Vector3(2.7, 0.3, 0.0), COLOR_X, "X")
	_add_axis_label(axes, Vector3(0.0, vertical_axis_length + 0.5, 0.0), COLOR_Y, "Y")
	_add_axis_label(axes, Vector3(0.0, 0.3, 2.7), COLOR_Z, "Z")


func _add_axis(
	parent: Node3D,
	direction: Vector3,
	length: float,
	color: Color,
	label_text: String,
	two_sided: bool
) -> void:
	var axis := Node3D.new()
	axis.name = "Axis%s" % label_text
	axis.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	parent.add_child(axis)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.016
	line_mesh.bottom_radius = 0.016
	line_mesh.height = length * (2.0 if two_sided else 1.0)
	line_mesh.radial_segments = 8
	line_mesh.rings = 1

	var line := MeshInstance3D.new()
	line.mesh = line_mesh
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.position.y = 0.0 if two_sided else length * 0.5
	axis.add_child(line)

	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.0
	arrow_mesh.bottom_radius = 0.07
	arrow_mesh.height = 0.3
	arrow_mesh.radial_segments = 12
	arrow_mesh.rings = 1

	var arrow := MeshInstance3D.new()
	arrow.mesh = arrow_mesh
	arrow.material_override = material
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.position.y = length + 0.15
	axis.add_child(arrow)


func _add_axis_label(parent: Node3D, position: Vector3, color: Color, label_text: String) -> void:
	var label := Label3D.new()
	label.text = label_text
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 12
	label.outline_modulate = Color(0.02, 0.03, 0.05, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = true
	label.no_depth_test = true
	label.position = position
	parent.add_child(label)


func _apply_settings() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("cell_size", grid_step)
	_material.set_shader_parameter("major_every", float(major_every))
	_material.set_shader_parameter("fade_start", fade_start)
	_material.set_shader_parameter("fade_end", fade_end)
