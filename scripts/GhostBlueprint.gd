@tool
## GhostBlueprint.gd
## A @tool Node3D you can place and move in the Godot 3D editor.
## Assign a .glb model via the Inspector and it renders as a transparent
## green ghost you can position visually. At runtime, it auto-generates
## Area3D collision pieces for BlueprintEvaluator.
class_name GhostBlueprint
extends Node3D

## The 3D model (.glb / .gltf / .tscn) to use as the ghost blueprint.
## Assign this in the Inspector — the ghost preview appears immediately.
@export var ghost_model: PackedScene = null:
	set(value):
		ghost_model = value
		_rebuild_preview()

## Color and opacity of the ghost in the editor and at runtime.
@export var ghost_color: Color = Color(0.2, 0.9, 0.3, 0.25):
	set(value):
		ghost_color = value
		_rebuild_preview()

## Scale applied to the model (same as JunkPart's target_dim / max_dim logic).
## Set to 0 for auto-scale to match JunkPart sizing (target_dim = 0.1).
@export var model_scale: float = 0.0:
	set(value):
		model_scale = value
		_rebuild_preview()

## Offset to adjust where the ghost is projected within the blueprint
@export var projection_offset: Vector3 = Vector3.ZERO:
	set(value):
		projection_offset = value
		if _preview_node:
			_rebuild_preview()

# Internal references
var _preview_node: Node3D = null
var _ghost_areas: Array[Area3D] = []
var _ghost_material: StandardMaterial3D = null


func _ready() -> void:
	_rebuild_preview()
	if not Engine.is_editor_hint():
		# At runtime, generate Area3D collision pieces for the evaluator
		_build_runtime_areas()


func _rebuild_preview() -> void:
	# Clean up old preview
	if _preview_node and is_instance_valid(_preview_node):
		_preview_node.queue_free()
		_preview_node = null

	if ghost_model == null:
		return

	# Instantiate the model
	_preview_node = ghost_model.instantiate()
	_preview_node.name = "GhostPreview"
	add_child(_preview_node, false, Node.INTERNAL_MODE_BACK)
	
	# Make the blueprint act as a single object so clicking the preview selects the GhostBlueprint
	set_meta("_edit_group_", true)

	# Calculate auto-scale if needed
	var scale_factor := _compute_scale_factor(_preview_node)
	_preview_node.scale = Vector3.ONE * scale_factor

	# Center the model and apply projection offset
	var center := _compute_center(_preview_node, scale_factor)
	_preview_node.position = -center + projection_offset

	# Apply ghost material to all meshes
	_ghost_material = _make_ghost_material()
	_apply_ghost_material(_preview_node, _ghost_material)


## Build Area3D collision pieces at runtime for BlueprintEvaluator.
## These are children of this GhostBlueprint node, so they inherit its
## position/rotation/scale that you set in the editor.
func _build_runtime_areas() -> void:
	_ghost_areas.clear()

	if _preview_node == null:
		return

	var meshes: Array[MeshInstance3D] = []
	_find_all_meshes(_preview_node, meshes)

	for mi in meshes:
		if mi.mesh == null:
			continue

		var aabb := mi.get_aabb()
		var rel_xform := _get_relative_transform(_preview_node, mi)

		# Account for the preview node's own scale and offset
		var piece_center: Vector3 = _preview_node.transform * (rel_xform * aabb.get_center())
		var piece_size: Vector3 = aabb.size * rel_xform.basis.get_scale() * _preview_node.scale

		# Create Area3D for this mesh piece
		var area := Area3D.new()
		var piece_name: String = mi.name if not mi.name.is_empty() else "Piece"
		area.name = "GhostArea_%s" % piece_name
		area.set_meta("ghost_label", piece_name)
		area.collision_layer = 0   # ghosts don't block anything
		area.collision_mask = 2    # detect player parts (layer 2)
		area.monitoring = true
		area.monitorable = false
		area.position = piece_center

		# Collision shape matching the mesh AABB
		var col := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = piece_size
		col.shape = box_shape
		area.add_child(col)

		add_child(area)
		_ghost_areas.append(area)


## Get all Area3D ghost pieces (for BlueprintEvaluator.set_ghost_root).
func get_ghost_areas() -> Array[Area3D]:
	return _ghost_areas


# ── Scale & Center Helpers ───────────────────────────────────────────────────

func _compute_scale_factor(node: Node3D) -> float:
	if model_scale > 0.001:
		return model_scale

	# Auto-scale: same logic as JunkPart (target_dim = 0.1 / max_dim)
	var total_aabb := _compute_total_aabb(node)
	var max_dim: float = max(total_aabb.size.x, max(total_aabb.size.y, total_aabb.size.z))
	if max_dim > 0.001:
		return 0.1 / max_dim
	return 1.0


func _compute_center(node: Node3D, sf: float) -> Vector3:
	var total_aabb := _compute_total_aabb(node)
	return total_aabb.get_center() * sf


func _compute_total_aabb(node: Node3D) -> AABB:
	var total := AABB()
	var has_aabb := false
	var meshes: Array[MeshInstance3D] = []
	_find_all_meshes(node, meshes)

	for mi in meshes:
		if mi.mesh:
			var local_aabb := mi.get_aabb()
			var xform := _get_relative_transform(node, mi)
			for corner in _aabb_corners(local_aabb):
				var world_corner: Vector3 = xform * corner
				if not has_aabb:
					total = AABB(world_corner, Vector3.ZERO)
					has_aabb = true
				else:
					total = total.expand(world_corner)
	return total


# ── Material ─────────────────────────────────────────────────────────────────

func _make_ghost_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ghost_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _apply_ghost_material(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			mi.material_override = mat
	for child in node.get_children():
		_apply_ghost_material(child, mat)


# ── Tree Traversal Helpers ───────────────────────────────────────────────────

func _find_all_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_all_meshes(child, result)


func _get_relative_transform(root: Node3D, child: Node3D) -> Transform3D:
	if child == root:
		return Transform3D.IDENTITY
	var xform := child.transform
	var parent: Node = child.get_parent()
	while parent != root and parent != null:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var pos := aabb.position
	var end := aabb.position + aabb.size
	return [
		Vector3(pos.x, pos.y, pos.z), Vector3(pos.x, pos.y, end.z),
		Vector3(pos.x, end.y, pos.z), Vector3(pos.x, end.y, end.z),
		Vector3(end.x, pos.y, pos.z), Vector3(end.x, pos.y, end.z),
		Vector3(end.x, end.y, pos.z), Vector3(end.x, end.y, end.z),
	]
