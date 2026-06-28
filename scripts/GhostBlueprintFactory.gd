## GhostBlueprintFactory.gd
## Utility class that converts a .glb / .gltf PackedScene into a "Ghost Blueprint"
## node tree suitable for BlueprintEvaluator.
##
## USAGE:
##   var factory = GhostBlueprintFactory.new()
##   var ghost_root = factory.create_ghost_from_scene("res://assets/models/chair.glb")
##   add_child(ghost_root)
##   blueprint_evaluator.set_ghost_root(ghost_root)
##
## HOW IT WORKS:
##   1. Instantiates the .glb scene.
##   2. Walks every MeshInstance3D in the tree.
##   3. For each mesh, creates an Area3D with a BoxShape3D collision shape
##      matching the mesh's AABB (axis-aligned bounding box).
##   4. Applies a semi-transparent green material so the player can see the target.
##   5. Strips out the original mesh visuals and replaces them with ghost versions.
##
## The resulting node tree:
##   GhostRoot (Node3D)
##   ├── GhostPiece_MeshName1 (Area3D)        ← ghost_label = "MeshName1"
##   │   ├── CollisionShape3D (BoxShape3D)
##   │   └── GhostVisual (MeshInstance3D)      ← transparent green box
##   ├── GhostPiece_MeshName2 (Area3D)
##   │   ├── CollisionShape3D (BoxShape3D)
##   │   └── GhostVisual (MeshInstance3D)
##   └── ...
class_name GhostBlueprintFactory
extends RefCounted

## Color and opacity for ghost visuals
const GHOST_COLOR: Color = Color(0.2, 0.9, 0.3, 0.25)

## Collision layer for ghost Area3D (should NOT overlap with anything)
const GHOST_COLLISION_LAYER: int = 0

## Collision mask: detect player parts (layer 2)
const GHOST_COLLISION_MASK: int = 2


## Create a ghost blueprint from a .glb/.gltf scene file path.
## Returns a Node3D root containing Area3D ghost pieces.
func create_ghost_from_path(model_path: String, target_scale: float = 0.1) -> Node3D:
	var scene := ResourceLoader.load(model_path) as PackedScene
	if scene == null:
		push_error("[GhostBlueprintFactory] Failed to load model: %s" % model_path)
		return null
	return create_ghost_from_scene(scene, target_scale)


## Create a ghost blueprint from an already-loaded PackedScene.
## `target_scale` controls the final size — same value as JunkPart uses
## (default 0.4 means the biggest dimension becomes 40cm).
func create_ghost_from_scene(scene: PackedScene, target_scale: float = 0.4) -> Node3D:
	# Instantiate the original model to read mesh data
	var source: Node3D = scene.instantiate()

	# Find all meshes in the source
	var meshes: Array[MeshInstance3D] = []
	_find_all_meshes(source, meshes)

	if meshes.is_empty():
		push_error("[GhostBlueprintFactory] No MeshInstance3D nodes found in scene")
		source.queue_free()
		return null

	# Compute total AABB for scaling (same logic as JunkPart.setup)
	var total_aabb := AABB()
	var has_aabb := false
	for mi in meshes:
		if mi.mesh:
			var local_aabb := mi.get_aabb()
			var xform := _get_relative_transform(source, mi)
			var corners := _aabb_corners(local_aabb)
			for corner in corners:
				var world_corner: Vector3 = xform * corner
				if not has_aabb:
					total_aabb = AABB(world_corner, Vector3.ZERO)
					has_aabb = true
				else:
					total_aabb = total_aabb.expand(world_corner)

	# Calculate scale factor to match JunkPart sizing
	var max_dim: float = max(total_aabb.size.x, max(total_aabb.size.y, total_aabb.size.z))
	var scale_factor: float = target_scale / max_dim if max_dim > 0.001 else 1.0
	var model_center: Vector3 = total_aabb.get_center()

	# Build the ghost root as a RigidBody3D so it can rest on the table
	var ghost_root := RigidBody3D.new()
	ghost_root.name = "ActiveGhost"
	ghost_root.collision_layer = 0 # Ignore everything
	ghost_root.collision_mask = 1  # Collide ONLY with table (layer 1)
	ghost_root.mass = 10.0 # Make it heavy enough to drop quickly

	# Create the ghost material (shared across all pieces)
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = GHOST_COLOR
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.no_depth_test = true  # always visible even behind solid objects
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from both sides

	# Convert each mesh into a ghost Area3D piece
	var piece_index: int = 0
	for mi in meshes:
		if mi.mesh == null:
			continue

		var mesh_aabb := mi.get_aabb()
		var rel_xform := _get_relative_transform(source, mi)

		# Ghost piece center in model space, then scaled + centered
		var piece_center: Vector3 = rel_xform * mesh_aabb.get_center()
		piece_center = (piece_center - model_center) * scale_factor
		var piece_size: Vector3 = mesh_aabb.size * rel_xform.basis.get_scale() * scale_factor

		# Create Area3D
		var area := Area3D.new()
		var piece_name: String = mi.name if not mi.name.is_empty() else "Piece_%d" % piece_index
		area.name = "Ghost_%s" % piece_name
		area.set_meta("ghost_label", piece_name)
		area.collision_layer = GHOST_COLLISION_LAYER
		area.collision_mask = GHOST_COLLISION_MASK
		area.monitoring = true
		area.monitorable = false
		area.position = piece_center

		# Visual ghost mesh (using the actual 3D model)
		var visual := MeshInstance3D.new()
		visual.name = "GhostVisual"
		visual.mesh = mi.mesh
		visual.transform.basis = rel_xform.basis * scale_factor
		var target_origin := (rel_xform.origin - model_center) * scale_factor
		visual.transform.origin = target_origin - piece_center
		
		if visual.mesh:
			for s in range(visual.mesh.get_surface_count()):
				visual.set_surface_override_material(s, ghost_mat)
				
		area.add_child(visual)

		# Auto-generate accurate convex collider using Godot's built-in tool!
		var shape = mi.mesh.create_convex_shape(true, true)
		if shape:
			var col := CollisionShape3D.new()
			col.shape = shape
			# The shape shares the same origin and scale as the mesh itself!
			col.transform = visual.transform
			area.add_child(col)

			# Add a duplicate collision shape directly to the RigidBody3D so it physically hits the table correctly
			var phys_col := CollisionShape3D.new()
			phys_col.shape = shape
			# It needs to be relative to the RigidBody3D, so we just use the calculated target_origin and basis directly
			phys_col.transform.basis = rel_xform.basis * scale_factor
			phys_col.transform.origin = target_origin
			ghost_root.add_child(phys_col)

		ghost_root.add_child(area)
		piece_index += 1

	# Create the invisible SpillBounds block rectangular around the normal ghost
	# We scale it slightly (1.5x) so it captures junk parts that are glued near the edges too
	var spill_area := Area3D.new()
	spill_area.name = "Ghost_SpillBounds"
	spill_area.set_meta("is_spill_bounds", true)
	spill_area.collision_layer = GHOST_COLLISION_LAYER
	spill_area.collision_mask = GHOST_COLLISION_MASK
	spill_area.monitoring = true
	spill_area.monitorable = false
	
	var spill_col := CollisionShape3D.new()
	var spill_box := BoxShape3D.new()
	spill_box.size = total_aabb.size * scale_factor * 1.5
	spill_col.shape = spill_box
	spill_area.add_child(spill_col)
	ghost_root.add_child(spill_area)

	# Clean up the source instance
	source.queue_free()

	return ghost_root


## Create a ghost from manually defined piece dictionaries.
## Each dict: {"label": String, "position": Vector3, "size": Vector3, "rotation": Vector3 (euler degrees)}
## This is useful when you want full manual control over the blueprint layout.
func create_ghost_from_definitions(pieces: Array[Dictionary]) -> Node3D:
	var ghost_root := Node3D.new()
	ghost_root.name = "GhostBlueprint"

	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = GHOST_COLOR
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.no_depth_test = true
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for i in range(pieces.size()):
		var def: Dictionary = pieces[i]
		var label: String = def.get("label", "Piece_%d" % i)
		var pos: Vector3 = def.get("position", Vector3.ZERO)
		var size: Vector3 = def.get("size", Vector3(0.1, 0.1, 0.1))
		var rot_deg: Vector3 = def.get("rotation", Vector3.ZERO)

		var area := Area3D.new()
		area.name = "Ghost_%s" % label
		area.set_meta("ghost_label", label)
		area.collision_layer = GHOST_COLLISION_LAYER
		area.collision_mask = GHOST_COLLISION_MASK
		area.monitoring = true
		area.monitorable = false
		area.position = pos
		area.rotation_degrees = rot_deg

		var col := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		col.shape = box_shape
		area.add_child(col)

		var visual := MeshInstance3D.new()
		visual.name = "GhostVisual"
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		box_mesh.surface_set_material(0, ghost_mat)
		visual.mesh = box_mesh
		area.add_child(visual)

		ghost_root.add_child(area)

	return ghost_root


# ── Internal Helpers ─────────────────────────────────────────────────────────

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
		Vector3(pos.x, pos.y, pos.z),
		Vector3(pos.x, pos.y, end.z),
		Vector3(pos.x, end.y, pos.z),
		Vector3(pos.x, end.y, end.z),
		Vector3(end.x, pos.y, pos.z),
		Vector3(end.x, pos.y, end.z),
		Vector3(end.x, end.y, pos.z),
		Vector3(end.x, end.y, end.z),
	]
