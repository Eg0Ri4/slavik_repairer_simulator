## AttachmentSystem.gd
## Handles spawning PinJoint3D (Bolts) or Generic6DOFJoint3D (Tape)
## between a newly placed part and the nearest existing assembly part.
##
## IMPORTANT: Joint node paths must be assigned AFTER the joint is
## added to the scene tree (Godot 4 requirement for get_path_to).
class_name AttachmentSystem
extends Node

func attach(new_part: Node3D, assembly_pivot: Node3D) -> Joint3D:
	var nearest: Node3D = _find_nearest_placed(new_part, assembly_pivot)
	return _create_bolt_joint(new_part, nearest, assembly_pivot)

func create_manual_tape_joint(body1: Node3D, pos1: Vector3, norm1: Vector3, body2: Node3D, pos2: Vector3, norm2: Vector3, pivot: Node3D) -> Joint3D:
	var joint := Generic6DOFJoint3D.new()

	# Tape is a completely rigid connection.
	for axis in range(3):
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT if axis == 0 else (Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT if axis == 1 else Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), true) # actually, Godot flags are per axis but accessible via set_flag_x/y/z
	
	# Actually, to make it clean:
	# Linear limits (lock all axes at distance 0)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	
	# Angular limits (lock all rotations at angle 0)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)

	# ── Add joint to tree FIRST, then assign paths (lifecycle safety) ────
	pivot.add_child(joint)
	joint.global_position = (pos1 + pos2) * 0.5
	
	_assign_paths_deferred.call_deferred(joint, body2, body1)

	# ── Procedural Visual Mesh with Segmentation and V-Ends ──────────────
	var mesh_inst = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.7)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	mesh_inst.mesh = mesh
	
	pivot.add_child(mesh_inst)
	# CRITICAL FIX: The vertices we calculate are in global coordinates.
	# By forcing the mesh_inst global_transform to IDENTITY before adding vertices,
	# local space == global space. Then reparent() preserves it properly!
	mesh_inst.global_transform = Transform3D.IDENTITY
	
	var space := pivot.get_world_3d().direct_space_state
	var segments := 12
	var width := 0.04
	
	var pts := PackedVector3Array()
	var normals := PackedVector3Array()
	
	# Sample intermediate points via raycasts to conform to surface
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		var base_pos = pos1.lerp(pos2, t)
		var inter_norm = norm1.lerp(norm2, t).normalized()
		
		var ray_start = base_pos + inter_norm * 0.1
		var ray_end = base_pos - inter_norm * 0.1
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 3
		var hit = space.intersect_ray(query)
		
		var pt = base_pos
		var n = inter_norm
		if hit:
			pt = hit["position"]
			n = hit["normal"]
			
		# Tiny normal offset (0.005m) to keep tape flush against mesh textures
		pts.append(pt + n * 0.005)
		normals.append(n)
		
	# Draw mesh with V-notched terminal segments
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for i in range(segments):
		var p0 = pts[i]
		var p1 = pts[i+1]
		var n0 = normals[i]
		var n1 = normals[i+1]
		
		var f0 = (p1 - p0).normalized()
		if f0.length_squared() < 0.001: f0 = Vector3.FORWARD
		var r0 = f0.cross(n0).normalized()
		
		var f1 = f0
		if i < segments - 1:
			var p2 = pts[i+2]
			f1 = (p2 - p1).normalized()
			if f1.length_squared() < 0.001: f1 = f0
		var r1 = f1.cross(n1).normalized()
		
		var left0 = p0 - r0 * (width * 0.5)
		var right0 = p0 + r0 * (width * 0.5)
		var left1 = p1 - r1 * (width * 0.5)
		var right1 = p1 + r1 * (width * 0.5)
		
		# V-notched torn edge at start (P1 terminal)
		if i == 0:
			var mid0 = p0 + f0 * 0.015
			mesh.surface_add_vertex(left0)
			mesh.surface_add_vertex(mid0)
			mesh.surface_add_vertex(left1)
			
			mesh.surface_add_vertex(left1)
			mesh.surface_add_vertex(mid0)
			mesh.surface_add_vertex(right1)
			
			mesh.surface_add_vertex(right1)
			mesh.surface_add_vertex(mid0)
			mesh.surface_add_vertex(right0)
		# V-notched torn edge at end (P2 terminal)
		elif i == segments - 1:
			var mid1 = p1 - f1 * 0.015
			mesh.surface_add_vertex(left0)
			mesh.surface_add_vertex(right0)
			mesh.surface_add_vertex(mid1)
			
			mesh.surface_add_vertex(left0)
			mesh.surface_add_vertex(mid1)
			mesh.surface_add_vertex(left1)
			
			mesh.surface_add_vertex(right0)
			mesh.surface_add_vertex(right1)
			mesh.surface_add_vertex(mid1)
		else:
			# Regular flat quad segment
			mesh.surface_add_vertex(left0)
			mesh.surface_add_vertex(right0)
			mesh.surface_add_vertex(left1)
			
			mesh.surface_add_vertex(left1)
			mesh.surface_add_vertex(right0)
			mesh.surface_add_vertex(right1)
			
	mesh.surface_end()
	
	mesh_inst.reparent(body1, true)
	
	# Add an Area3D so the crowbar can click the tape
	var area = Area3D.new()
	area.collision_layer = 8 # Same as nail heads
	area.collision_mask = 0
	area.monitorable = true
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	var tape_dist = pos1.distance_to(pos2)
	box.size = Vector3(0.08, 0.08, tape_dist)
	col.shape = box
	area.add_child(col)
	mesh_inst.add_child(area)
	
	# Align area with the tape
	area.global_position = (pos1 + pos2) * 0.5
	if tape_dist > 0.001:
		area.look_at(pos2, Vector3.UP if abs((pos2 - pos1).normalized().y) < 0.99 else Vector3.RIGHT)
		
	# Store references so the crowbar knows what to delete
	area.set_meta("is_tape", true)
	area.set_meta("tape_joint", joint)
	area.set_meta("tape_mesh", mesh_inst)
	
	return joint

# ── Joint factories ──────────────────────────────────────────────────────────
func _create_bolt_joint(new_part: Node3D, anchor: Node3D, pivot: Node3D) -> Joint3D:
	var joint := PinJoint3D.new()
	_setup_joint(joint, new_part, anchor, pivot)
	return joint

func _setup_joint(joint: Joint3D, new_part: Node3D, anchor: Node3D, pivot: Node3D) -> void:
	# CRITICAL: add to scene tree FIRST, then assign node paths and transforms
	pivot.add_child(joint)

	# Position the joint at the midpoint between the two bodies
	var joint_pos: Vector3 = new_part.global_position
	if anchor:
		joint_pos = (new_part.global_position + anchor.global_position) * 0.5
	joint.global_position = joint_pos

	# Now we can safely call get_path_to (nodes must share a common ancestor)
	_assign_paths_deferred.call_deferred(joint, new_part, anchor)

func _assign_paths_deferred(joint: Joint3D, new_part: Node3D, anchor: Node3D) -> void:
	if not is_instance_valid(joint) or not is_instance_valid(new_part) or not joint.is_inside_tree() or not new_part.is_inside_tree():
		return
	if anchor and is_instance_valid(anchor) and anchor.is_inside_tree():
		joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(new_part)


# ── Cluster Discovery ────────────────────────────────────────────────────────

## Perform a BFS/flood-fill through all Joint3D nodes under `search_root` to
## find every JunkPart that is transitively connected to `root_part` via joints.
## Returns an Array[Node3D] that always includes `root_part` as the first element.
## If `root_part` has no joints, returns [root_part] (a single-element cluster).
func get_connected_cluster(root_part: Node3D, search_root: Node3D) -> Array[Node3D]:
	# Collect all Joint3D nodes and build an adjacency map:  RID → Array[RID]
	# We key by RID to avoid identity issues and get O(1) lookups.
	var body_to_parts: Dictionary = {}   # RID → JunkPart
	var adjacency: Dictionary = {}       # RID → Array[RID]

	# Pre-index all JunkParts by RID for fast lookup
	_collect_parts_recursive(search_root, body_to_parts)

	# Also include parts that live directly under the scene root (e.g. loose parts
	# that were reparented out of the pivot during a prior pick-up).
	var scene_root := root_part.get_tree().root.get_node_or_null("Main")
	if scene_root and scene_root != search_root:
		_collect_parts_recursive(scene_root, body_to_parts)

	# Walk all Joint3D nodes to build edges
	_collect_joints_recursive(search_root, body_to_parts, adjacency)
	if scene_root and scene_root != search_root:
		_collect_joints_recursive(scene_root, body_to_parts, adjacency)

	# BFS from root_part
	var root_rid: RID = root_part.get_rid()
	var visited: Dictionary = {}   # RID → true
	var queue: Array[RID] = [root_rid]
	visited[root_rid] = true

	while queue.size() > 0:
		var current_rid: RID = queue.pop_front()
		if current_rid in adjacency:
			for neighbor_rid: RID in adjacency[current_rid]:
				if neighbor_rid not in visited:
					visited[neighbor_rid] = true
					queue.push_back(neighbor_rid)

	# Build result — root_part first, then the rest
	var cluster: Array[Node3D] = [root_part]
	for rid: RID in visited:
		if rid != root_rid and rid in body_to_parts:
			cluster.append(body_to_parts[rid] as Node3D)

	return cluster


## Return all Joint3D nodes that connect members of the given cluster.
## Useful for temporarily disabling/enabling joints during compound movement.
func get_joints_in_cluster(cluster: Array[Node3D], search_root: Node3D) -> Array[Joint3D]:
	var cluster_rids: Dictionary = {}
	for part: Node3D in cluster:
		cluster_rids[part.get_rid()] = true

	var joints: Array[Joint3D] = []
	_find_cluster_joints_recursive(search_root, cluster_rids, joints)

	var scene_root := search_root.get_tree().root.get_node_or_null("Main")
	if scene_root and scene_root != search_root:
		_find_cluster_joints_recursive(scene_root, cluster_rids, joints)

	return joints


# ── Internal: recursive collectors ───────────────────────────────────────────

func _collect_parts_recursive(node: Node, body_to_parts: Dictionary) -> void:
	if node is JunkPart:
		body_to_parts[node.get_rid()] = node
	for child in node.get_children():
		if child is JunkPart:
			body_to_parts[child.get_rid()] = child
		# Don't recurse deeply — parts are direct children of pivot / scene root


func _collect_joints_recursive(node: Node, body_to_parts: Dictionary, adjacency: Dictionary) -> void:
	for child in node.get_children():
		if child is Joint3D:
			var joint := child as Joint3D
			if joint.is_queued_for_deletion():
				continue
			var body_a: PhysicsBody3D = joint.get_node_or_null(joint.node_a) if joint.node_a else null
			var body_b: PhysicsBody3D = joint.get_node_or_null(joint.node_b) if joint.node_b else null

			if body_a is JunkPart and body_b is JunkPart:
				var rid_a: RID = body_a.get_rid()
				var rid_b: RID = body_b.get_rid()

				if rid_a not in adjacency:
					adjacency[rid_a] = [] as Array[RID]
				(adjacency[rid_a] as Array[RID]).append(rid_b)

				if rid_b not in adjacency:
					adjacency[rid_b] = [] as Array[RID]
				(adjacency[rid_b] as Array[RID]).append(rid_a)

		# Also check children of JunkParts (joints can be children of parts)
		if child is JunkPart:
			_collect_joints_recursive(child, body_to_parts, adjacency)


func _find_cluster_joints_recursive(node: Node, cluster_rids: Dictionary, joints: Array[Joint3D]) -> void:
	for child in node.get_children():
		if child is Joint3D:
			var joint := child as Joint3D
			if joint.is_queued_for_deletion():
				continue
			var body_a: PhysicsBody3D = joint.get_node_or_null(joint.node_a) if joint.node_a else null
			var body_b: PhysicsBody3D = joint.get_node_or_null(joint.node_b) if joint.node_b else null

			var a_in := body_a is JunkPart and body_a.get_rid() in cluster_rids
			var b_in := body_b is JunkPart and body_b.get_rid() in cluster_rids
			if a_in and b_in:
				joints.append(joint)

		if child is JunkPart:
			_find_cluster_joints_recursive(child, cluster_rids, joints)


# ── Helpers ──────────────────────────────────────────────────────────────────
func _find_nearest_placed(new_part: Node3D, pivot: Node3D) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for child in pivot.get_children():
		if child is JunkPart and child != new_part and child.is_placed:
			var d: float = child.global_position.distance_to(new_part.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = child

	return nearest
