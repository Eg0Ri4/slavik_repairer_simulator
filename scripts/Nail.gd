## Nail.gd
## A visual nail that can be struck repeatedly to drive it into a surface.
## Each strike() call tweens the nail deeper along its local -Y axis.
## When target depth is reached, the nail reparents to the surface body
## and creates a PinJoint3D between the two bodies it connects.
class_name Nail
extends RigidBody3D

# ── Configuration ────────────────────────────────────────────────────────────
## How far the nail sinks per full-power hit (meters).
@export var sink_per_hit: float = 0.015
## Total depth the nail must travel to be considered fully driven (meters).
@export var target_depth: float = 0.06
## Tween duration for each sink animation (seconds).
@export var sink_tween_duration: float = 0.12
## Number of strikes needed at full power = target_depth / sink_per_hit.

# ── Signals ──────────────────────────────────────────────────────────────────
## Emitted after each successful strike, with progress 0.0 → 1.0.
signal nail_struck(progress: float)
## Emitted once the nail reaches target depth and is fastened.
signal nail_fastened()
signal nail_unfastened()

# ── Internal state ───────────────────────────────────────────────────────────
var _current_depth: float = 0.0
var _is_fastened: bool = false
var _is_animating: bool = false
var _is_dropped: bool = false
var _joint: Generic6DOFJoint3D = null
var _grace_timer_ref: SceneTreeTimer = null

## The body the nail is being driven INTO (the surface).
var _surface_body: Node3D = null
## The body on TOP that the nail is fastening (optional — set if nailing two parts).
var _top_body: Node3D = null

# Visual nodes (built in _ready)
var _shaft_mesh: MeshInstance3D = null
var _head_mesh: MeshInstance3D = null
var _tip_mesh: MeshInstance3D = null
var _head_area: Area3D = null

# Nail dimensions
const SHAFT_RADIUS: float = 0.004
const SHAFT_HEIGHT: float = 0.06
const HEAD_RADIUS: float = 0.008
const HEAD_HEIGHT: float = 0.004
const TIP_HEIGHT: float = 0.012

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	freeze = true
	collision_layer = 0
	collision_mask = 0
	_build_visual()
	_build_head_area()
	_build_collision()
	
	# Grace period: if not struck within 5 seconds, the nail drops loose.
	_grace_timer_ref = get_tree().create_timer(5.0)
	_grace_timer_ref.timeout.connect(_on_grace_timeout)

func _on_grace_timeout() -> void:
	if not is_instance_valid(self): return
	if _current_depth == 0.0 and not _is_fastened:
		_drop()


## Call after instantiating to tell the nail which bodies it connects.
func setup(surface_body: Node3D, top_body: Node3D = null) -> void:
	_surface_body = surface_body
	_top_body = top_body


# ── Strike API ───────────────────────────────────────────────────────────────
## Call this when the player hits the nail. power: 0.0–1.0 (default 1.0).
func strike(power: float = 1.0) -> void:
	if _is_fastened or _is_animating or _is_dropped:
		return

	# Cancel the grace timer on first strike
	if _grace_timer_ref:
		if _grace_timer_ref.timeout.is_connected(_on_grace_timeout):
			_grace_timer_ref.timeout.disconnect(_on_grace_timeout)
		_grace_timer_ref = null

	_is_animating = true

	var sink_amount: float = sink_per_hit * clampf(power, 0.3, 1.0)
	_current_depth += sink_amount
	_current_depth = minf(_current_depth, target_depth)

	# Tween the nail down its local -Y axis
	var sink_dir: Vector3 = -global_basis.y.normalized()
	var target_pos: Vector3 = global_position + sink_dir * sink_amount

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "global_position", target_pos, sink_tween_duration)

	# Slight wobble for realism
	var wobble_deg := randf_range(-1.0, 1.0)
	tw.parallel().tween_property(
		self, "rotation_degrees",
		rotation_degrees + Vector3(wobble_deg, 0.0, wobble_deg * 0.5),
		sink_tween_duration
	)

	tw.finished.connect(_on_sink_finished)

	# Emit progress
	var progress: float = _current_depth / target_depth
	nail_struck.emit(progress)


func _on_sink_finished() -> void:
	_is_animating = false
	if _current_depth >= target_depth and not _is_fastened:
		_is_fastened = true
		_create_joint()


# ── Crowbar Pull API ─────────────────────────────────────────────────────────
## Pull the nail outward (decrement depth). Called by NailTool when CROWBAR active.
func pull(power: float = 1.0) -> void:
	if _is_animating or _is_dropped:
		return

	# If the nail's visuals are merged into the surface body, restore them early 
	# so they can actually move with the tween animation!
	var my_nodes = get_meta("merged_nodes", [])
	if my_nodes.size() > 0:
		for child in my_nodes:
			if is_instance_valid(child):
				child.reparent(self, true)
		set_meta("merged_nodes", [])

	_is_animating = true

	var pull_amount: float = sink_per_hit * clampf(power, 0.3, 1.0)
	_current_depth -= pull_amount
	_current_depth = maxf(_current_depth, 0.0)

	# Tween the nail up its local Y axis (out of the surface)
	var pull_dir: Vector3 = global_basis.y.normalized()
	var target_pos: Vector3 = global_position + pull_dir * pull_amount

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "global_position", target_pos, sink_tween_duration)

	var wobble_deg := randf_range(-2.0, 2.0)
	tw.parallel().tween_property(
		self, "rotation_degrees",
		rotation_degrees + Vector3(wobble_deg, 0.0, wobble_deg * 0.5),
		sink_tween_duration
	)

	tw.finished.connect(_on_pull_finished)

	var progress: float = _current_depth / target_depth
	nail_struck.emit(progress)

func _on_pull_finished() -> void:
	_is_animating = false
	if _current_depth <= 0.0:
		_unfasten()

func _unfasten() -> void:
	if _is_fastened:
		_is_fastened = false
		_undo_merge()
		nail_unfastened.emit()
	_drop()

func _undo_merge() -> void:
	# 1. Restore the nail's own nodes
	var my_nodes = get_meta("merged_nodes", [])
	for child in my_nodes:
		if is_instance_valid(child):
			child.reparent(self, true)
			
	if _surface_body is RigidBody3D:
		_surface_body.mass -= mass

	# 2. Restore the top body
	if _top_body and is_instance_valid(_top_body):
		var top_nodes = _top_body.get_meta("merged_nodes", [])
		for child in top_nodes:
			if is_instance_valid(child):
				child.reparent(_top_body, true)
				
		if _surface_body is RigidBody3D and _top_body is RigidBody3D:
			_surface_body.mass -= _top_body.mass
			
		# Wake the top body back up and put it alongside the surface body
		if _surface_body and is_instance_valid(_surface_body) and _surface_body.get_parent():
			_top_body.reparent(_surface_body.get_parent(), true)
		else:
			_top_body.reparent(get_tree().current_scene, true)
			
		_top_body.process_mode = Node.PROCESS_MODE_INHERIT
		
		# Put it back in GameState
		var GameState = get_tree().root.get_node_or_null("Main/GameState")
		if GameState == null:
			GameState = get_node("/root/GameState")
		if GameState and GameState.has_method("register_assembly_part"):
			GameState.register_assembly_part(_top_body)
		elif GameState and "assembly_parts" in GameState:
			if not GameState.assembly_parts.has(_top_body):
				GameState.assembly_parts.append(_top_body)
				
		# Note: We cannot easily 'un-absorb' tags from JunkPart's merged_subparts 
		# without tracking exact indices, but typically removing it restores physics interaction, 
		# which is what the user expects from the crowbar.

func _break_joint() -> void:
	pass

func _drop() -> void:
	_is_dropped = true
	if get_parent() and get_parent().name != "Main":
		var scene_root = get_tree().current_scene
		if scene_root:
			var t = global_transform
			reparent(scene_root, true)
			global_transform = t
			
	freeze = false
	collision_layer = 2 # placed parts layer
	collision_mask = 3  # table + parts
	
	_start_decay_timer()

func _start_decay_timer() -> void:
	# Dropped nails decay and are freed after 10 seconds
	var t = get_tree().create_timer(10.0)
	t.timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)


# ── Monolithic Object Merging ────────────────────────────────────────────────
func _create_joint() -> void:
	if not (_surface_body is RigidBody3D or _surface_body is StaticBody3D):
		return

	# 1. Store state and reparent the nail's visuals
	set_meta("merged_nodes", [])
	var my_nodes = []
	# We iterate backwards or safely since we modify the tree
	for child in get_children():
		if child is Node3D and child != _head_area:
			my_nodes.append(child)
			
	for child in my_nodes:
		child.reparent(_surface_body, true)
		var arr = get_meta("merged_nodes")
		arr.append(child)
			
	if _surface_body is RigidBody3D:
		_surface_body.mass += mass # The nail's mass

	# 2. If there is a valid second body to merge, do it now
	if _top_body is RigidBody3D or _top_body is StaticBody3D:
		_top_body.set_meta("merged_nodes", [])
		var top_nodes = []
		for child in _top_body.get_children():
			if child is Node3D:
				top_nodes.append(child)
				
		for child in top_nodes:
			child.reparent(_surface_body, true)
			var arr = _top_body.get_meta("merged_nodes")
			arr.append(child)
				
		if _surface_body is RigidBody3D and _top_body is RigidBody3D:
			_surface_body.mass += _top_body.mass
			
		# Disable the empty top body and make it a passenger
		_top_body.process_mode = Node.PROCESS_MODE_DISABLED
		_top_body.reparent(_surface_body, true)
		
		# We must remove it from GameState so it isn't considered an independent part
		var GameState = get_tree().root.get_node_or_null("Main/GameState")
		if GameState == null:
			GameState = get_node("/root/GameState")
		if GameState and GameState.has_method("unregister_assembly_part"):
			GameState.unregister_assembly_part(_top_body)
		elif GameState and "assembly_parts" in GameState:
			GameState.assembly_parts.erase(_top_body)

	# 3. Make the nail itself a passenger
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# We DO NOT disable process_mode so the head area can still be clicked by the crowbar!
	reparent(_surface_body, true)

	_is_fastened = true
	nail_fastened.emit()
	# WE DO NOT queue_free() ANYMORE! The nail and top_body remain as dormant children.

func _do_assign_joint_paths(joint: Joint3D, body_a: Node3D, body_b: Node3D) -> void:
	pass # Deprecated, replaced by monolithic merge


# ── Queries ──────────────────────────────────────────────────────────────────
func is_fastened() -> bool:
	return _is_fastened


func get_progress() -> float:
	return _current_depth / target_depth if target_depth > 0.0 else 1.0


func get_head_area() -> Area3D:
	return _head_area


# ── Visual construction ─────────────────────────────────────────────────────
func _build_visual() -> void:
	# Material for the nail (metallic grey)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.72)
	mat.metallic = 0.85
	mat.roughness = 0.3

	# Shaft (cylinder, centered on origin, extends downward)
	_shaft_mesh = MeshInstance3D.new()
	_shaft_mesh.name = "NailShaft"
	var cyl := CylinderMesh.new()
	cyl.top_radius = SHAFT_RADIUS
	cyl.bottom_radius = SHAFT_RADIUS
	cyl.height = SHAFT_HEIGHT
	cyl.radial_segments = 8
	cyl.surface_set_material(0, mat)
	_shaft_mesh.mesh = cyl
	# Position shaft so its top is near the head
	_shaft_mesh.position = Vector3(0, -SHAFT_HEIGHT * 0.5, 0)
	add_child(_shaft_mesh)

	# Head (flat disc at the top)
	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "NailHead"
	var head_cyl := CylinderMesh.new()
	head_cyl.top_radius = HEAD_RADIUS
	head_cyl.bottom_radius = HEAD_RADIUS
	head_cyl.height = HEAD_HEIGHT
	head_cyl.radial_segments = 12
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.6, 0.6, 0.62)
	head_mat.metallic = 0.9
	head_mat.roughness = 0.25
	head_cyl.surface_set_material(0, head_mat)
	_head_mesh.mesh = head_cyl
	_head_mesh.position = Vector3(0, HEAD_HEIGHT * 0.5, 0)
	add_child(_head_mesh)

	# Tip (cone at the bottom)
	_tip_mesh = MeshInstance3D.new()
	_tip_mesh.name = "NailTip"
	var tip := CylinderMesh.new()
	tip.top_radius = SHAFT_RADIUS
	tip.bottom_radius = 0.0
	tip.height = TIP_HEIGHT
	tip.radial_segments = 8
	tip.surface_set_material(0, mat)
	_tip_mesh.mesh = tip
	_tip_mesh.position = Vector3(0, -SHAFT_HEIGHT - TIP_HEIGHT * 0.5, 0)
	add_child(_tip_mesh)


func _build_head_area() -> void:
	# Area3D around the nail head for raycast/click detection
	_head_area = Area3D.new()
	_head_area.name = "NailHeadArea"
	# Use layer 8 (bit 3) for nail heads — distinct from table/parts/boxes
	_head_area.collision_layer = 8
	_head_area.collision_mask = 0
	_head_area.monitorable = true

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.015  # slightly larger than the head for easy clicking
	col.shape = sphere
	col.position = Vector3(0, HEAD_HEIGHT * 0.5, 0)
	_head_area.add_child(col)
	add_child(_head_area)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = SHAFT_RADIUS
	cyl.height = SHAFT_HEIGHT + TIP_HEIGHT + HEAD_HEIGHT
	col.shape = cyl
	col.position = Vector3(0, -SHAFT_HEIGHT * 0.5, 0)
	add_child(col)
