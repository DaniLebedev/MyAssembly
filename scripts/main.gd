extends Node3D
## Точка входа редактора: демо-каркас и связывание UI с контроллером.

const DEMO_POSITIONS := [
	Vector3(-1.5, 0.5, -1.5),
	Vector3(1.5, 0.5, -1.5),
	Vector3(1.5, 0.5, 1.5),
	Vector3(-1.5, 0.5, 1.5),
	Vector3(-1.5, 2.0, -1.5),
	Vector3(1.5, 2.0, -1.5),
	Vector3(1.5, 2.0, 1.5),
	Vector3(-1.5, 2.0, 1.5),
]

@onready var _points_root: Node3D = $Points
@onready var _grid: EditorGrid = $Grid
@onready var _editor: EditorController = $Editor
@onready var _hud: Control = %HUD
@onready var _selection_box: SelectionBoxOverlay = %SelectionBox
@onready var _context_hint: Label = %ContextHint
@onready var _selection_value: Label = %SelectionValue
@onready var _points_value: Label = %PointsValue
@onready var _parts_value: Label = %PartsValue
@onready var _grid_value: Label = %GridValue
@onready var _undo_value: Label = %UndoValue
@onready var _redo_value: Label = %RedoValue


func _ready() -> void:
	_make_click_through(_hud)
	_spawn_demo_points()

	_editor.selection_changed.connect(_refresh_hud)
	_editor.history_changed.connect(_refresh_hud)
	_editor.context_changed.connect(_refresh_hud)
	_editor.marquee_changed.connect(_on_marquee_changed)
	_refresh_hud()


func _spawn_demo_points() -> void:
	if _points_root.get_child_count() > 0:
		return

	var index := 1
	for spawn_position in DEMO_POSITIONS:
		var point := EditorPoint.new()
		point.name = "Point%02d" % index
		point.point_id = index
		point.position = spawn_position
		_points_root.add_child(point)
		index += 1


func _refresh_hud() -> void:
	_selection_value.text = str(_editor.get_selected_count())
	_points_value.text = str(_editor.get_point_count())
	_parts_value.text = str(_editor.get_structure_count())
	_grid_value.text = "%.2f м" % _grid.grid_step

	_context_hint.text = _editor.get_context_hint()
	if _editor.is_modal_active():
		_context_hint.modulate = Color(0.55, 0.88, 1.0, 1.0)
	elif _editor.get_selected_count() > 0:
		_context_hint.modulate = Color(1.0, 0.7, 0.32, 1.0)
	else:
		_context_hint.modulate = Color(0.66, 0.74, 0.84, 1.0)

	var undo_name := _editor.get_undo_name()
	var redo_name := _editor.get_redo_name()
	_undo_value.text = undo_name if not undo_name.is_empty() else "—"
	_redo_value.text = redo_name if not redo_name.is_empty() else "—"
	_undo_value.modulate = Color.WHITE if not undo_name.is_empty() else Color(1, 1, 1, 0.42)
	_redo_value.modulate = Color.WHITE if not redo_name.is_empty() else Color(1, 1, 1, 0.42)


func _on_marquee_changed(active: bool, rect: Rect2) -> void:
	_selection_box.set_box(active, rect)


func _make_click_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_click_through(child)
