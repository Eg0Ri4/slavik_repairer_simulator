@tool
## JunkBox.gd
## A clickable box under the table that spawns random junk parts.
class_name JunkBox
extends StaticBody3D

@export var box_color: Color = Color(0.55, 0.35, 0.15)
@export var box_label: String = "Box A"
@export_dir var mesh_folder_path: String = ""

# Predefined pool of items this box can produce
var _item_pool: Array[ItemData] = []
var _mesh_files: Array[String] = []

var _highlight_mat: StandardMaterial3D
var _normal_mat: StandardMaterial3D
var _mesh_inst: MeshInstance3D

signal part_extracted(part_data: ItemData)

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0

	# Clean up previous editor generated nodes to avoid duplicates
	for child in get_children():
		if child.name in ["BoxMeshInstance", "BoxLabel3D", "BoxCollisionShape"]:
			child.queue_free()

	# Build visual box
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "BoxMeshInstance"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.4, 0.35, 0.35)
	_mesh_inst.mesh = box_mesh

	_normal_mat = StandardMaterial3D.new()
	_normal_mat.albedo_color = box_color
	_normal_mat.roughness = 0.9

	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.albedo_color = box_color.lightened(0.35)
	_highlight_mat.roughness = 0.9
	_highlight_mat.emission_enabled = true
	_highlight_mat.emission = box_color.lightened(0.2)
	_highlight_mat.emission_energy_multiplier = 0.5

	box_mesh.surface_set_material(0, _normal_mat)
	add_child(_mesh_inst)

	# Label above box
	var label3d := Label3D.new()
	label3d.name = "BoxLabel3D"
	label3d.text = box_label
	label3d.font_size = 18
	label3d.position = Vector3(0, 0.25, 0)
	label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label3d)

	# Collision shape
	var col := CollisionShape3D.new()
	col.name = "BoxCollisionShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.35, 0.35)
	col.shape = shape
	add_child(col)

	if not Engine.is_editor_hint():
		_scan_mesh_folder()
		_populate_pool()

func _scan_mesh_folder() -> void:
	_mesh_files.clear()
	if mesh_folder_path.is_empty():
		return
	var dir = DirAccess.open(mesh_folder_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var ext = file_name.get_extension().to_lower()
				if ext in ["glb", "gltf", "obj", "tscn", "scn"] and not file_name.ends_with(".import"):
					_mesh_files.append(mesh_folder_path.path_join(file_name))
			file_name = dir.get_next()

func _populate_pool() -> void:
	# Create several predefined ItemData resources at runtime
	var defs: Array[Dictionary] = [
		{"name": "Rusty Blade",    "tags": ["blade"],  "color": Color(0.7, 0.5, 0.3),  "size": Vector3(0.18, 0.05, 0.25), "shape": "box"},
		{"name": "Old Motor",      "tags": ["motor"],  "color": Color(0.4, 0.4, 0.45), "size": Vector3(0.15, 0.15, 0.15), "shape": "cylinder"},
		{"name": "Metal Frame",    "tags": ["frame"],  "color": Color(0.5, 0.6, 0.5),  "size": Vector3(0.28, 0.06, 0.28), "shape": "box"},
		{"name": "Rubber Gasket",  "tags": ["seal"],   "color": Color(0.2, 0.2, 0.2),  "size": Vector3(0.12, 0.03, 0.12), "shape": "cylinder"},
		{"name": "Coil Spring",    "tags": ["spring"], "color": Color(0.7, 0.7, 0.2),  "size": Vector3(0.08, 0.18, 0.08), "shape": "cylinder"},
		{"name": "Cracked Gear",   "tags": ["gear"],   "color": Color(0.55, 0.5, 0.4), "size": Vector3(0.16, 0.04, 0.16), "shape": "cylinder"},
		{"name": "Bent Pipe",      "tags": ["pipe"],   "color": Color(0.45, 0.55, 0.6),"size": Vector3(0.06, 0.25, 0.06), "shape": "cylinder"},
		{"name": "Scrap Plate",    "tags": ["frame"],  "color": Color(0.6, 0.62, 0.58),"size": Vector3(0.30, 0.04, 0.22), "shape": "box"},
		{"name": "Widget Ball",    "tags": ["gear"],   "color": Color(0.8, 0.3, 0.3),  "size": Vector3(0.12, 0.12, 0.12), "shape": "sphere"},
		{"name": "Fan Blade",      "tags": ["blade"],  "color": Color(0.5, 0.7, 0.9),  "size": Vector3(0.22, 0.04, 0.10), "shape": "box"},
	]
	for d in defs:
		var item := ItemData.new()
		item.item_name = d["name"]
		item.tags = d["tags"]
		item.item_color = d["color"]
		item.size = d["size"]
		item.shape_type = d["shape"]
		_item_pool.append(item)

func highlight(on: bool) -> void:
	if _mesh_inst and _mesh_inst.mesh:
		if on:
			_mesh_inst.mesh.surface_set_material(0, _highlight_mat)
		else:
			_mesh_inst.mesh.surface_set_material(0, _normal_mat)

func extract_random_part() -> Dictionary:
	if _item_pool.is_empty():
		return {}
	var idx: int = randi() % _item_pool.size()
	var data: ItemData = _item_pool[idx]
	
	var model_path: String = ""
	if _mesh_files.size() > 0:
		model_path = _mesh_files[randi() % _mesh_files.size()]
		
	part_extracted.emit(data)
	return {"data": data, "model_path": model_path}
