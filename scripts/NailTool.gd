## NailTool.gd
## Manages nail placement and hammering interaction.
## When active_tool == "nail":
##   - Left-click on a placed part → places a new Nail at the hit point
##   - Left-click on an existing nail head → strikes it (drives it deeper)
##
## Integrates with GameState for tool switching and Main.gd for UI.
class_name NailTool
extends Node3D

# ── Configuration ────────────────────────────────────────────────────────────
## The raycast distance for detecting surfaces and nails.
@export var ray_distance: float = 20.0

# ── Signals ──────────────────────────────────────────────────────────────────
## Emitted when a nail is placed (for UI feedback).
signal nail_placed(nail: Nail)
## Emitted when a nail strike occurs, with progress 0.0–1.0.
signal nail_strike_performed(progress: float)
## Emitted when a nail is fully driven.
signal nail_fully_driven(nail: Nail)
## Emitted when nail placement is blocked.
signal nail_placement_blocked(reason: String)

# ── State ────────────────────────────────────────────────────────────────────
## Reference to the assembly pivot (set by Main.gd on setup).
var assembly_pivot: Node3D = null

## The nail currently being hammered (for feedback).
var _active_nail: Nail = null

## Cooldown to prevent double-click issues.
var _strike_cooldown: float = 0.0
const STRIKE_COOLDOWN_TIME: float = 0.25


func _physics_process(delta: float) -> void:
	if _strike_cooldown > 0.0:
		_strike_cooldown -= delta


## Called by Main.gd when a left-click occurs and active_tool == "nail".
## Returns true if the click was consumed (hit a nail or placed one).
func handle_click(mouse_pos: Vector2) -> bool:
	if GameState.active_tool != "nail":
		return false

	# Don't act if we're on cooldown
	if _strike_cooldown > 0.0:
		return true

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false

	var origin := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)
	var space := get_world_3d().direct_space_state

	# ── Step 1: Check if we clicked an existing nail head ────────────────
	var nail_hit = _raycast_for_nail(origin, direction, space)
	if nail_hit:
		if not nail_hit.is_fastened():
			_strike_nail(nail_hit)
		else:
			nail_placement_blocked.emit("Nail is already fully driven!")
		return true

	# ── Step 2: Check if we clicked a placed part surface ────────────────
	var surface_result = _raycast_for_surface(origin, direction, space)
	if surface_result:
		_place_nail(surface_result)
		return true

	return false


# ── Nail striking ────────────────────────────────────────────────────────────
func _strike_nail(nail: Nail) -> void:
	_strike_cooldown = STRIKE_COOLDOWN_TIME
	_active_nail = nail
	nail.strike(1.0)
	nail_strike_performed.emit(nail.get_progress())

	if nail.is_fastened():
		nail_fully_driven.emit(nail)
		_active_nail = null


# ── Nail placement ───────────────────────────────────────────────────────────
func _place_nail(hit_result: Dictionary) -> void:
	_strike_cooldown = STRIKE_COOLDOWN_TIME

	var hit_point: Vector3 = hit_result["position"]
	var hit_normal: Vector3 = hit_result["normal"]
	var hit_collider: Object = hit_result["collider"]

	# Only place nails on placed JunkParts
	if not (hit_collider is JunkPart):
		return
	var surface_part := hit_collider as JunkPart
	if not surface_part.is_placed:
		return

	# Check if another nail is already placed too close to this spot
	if _is_nail_too_close(hit_point):
		nail_placement_blocked.emit("Too close to another nail!")
		return

	# Create the nail
	var nail := Nail.new()
	nail.name = "Nail_%d" % (randi() % 99999)

	# Find the nearest OTHER placed part to connect to (if any)
	var top_body: Node3D = _find_nearest_other_part(surface_part, hit_point)
	nail.setup(surface_part, top_body)

	# Add to the assembly pivot
	if assembly_pivot:
		assembly_pivot.add_child(nail)
	else:
		get_tree().current_scene.add_child(nail)

	# Position the nail outward along the surface normal to prevent clipping.
	# We use the nail's target_depth so it starts standing out from the surface
	# and ends up with the head flush when fully driven.
	var nail_offset: float = nail.target_depth
	var finalized_position: Vector3 = hit_point + hit_normal * nail_offset
	nail.global_position = finalized_position

	# Orient the nail so its local Y points along the surface normal
	# (nail drives INTO the surface, so its -Y points into the surface)
	nail.global_transform = _align_to_normal(nail.global_transform, hit_normal)

	# Connect signals for feedback
	nail.nail_fastened.connect(func() -> void: nail_fully_driven.emit(nail))

	nail_placed.emit(nail)
	_active_nail = nail


## Build a transform that aligns local +Y with the given normal.
func _align_to_normal(xform: Transform3D, normal: Vector3) -> Transform3D:
	var up := normal.normalized()
	# Pick a reference that isn't parallel to the normal
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var right := up.cross(ref).normalized()
	var forward := right.cross(up).normalized()
	xform.basis = Basis(right, up, forward)
	return xform


# ── Raycasting helpers ───────────────────────────────────────────────────────
func _raycast_for_nail(origin: Vector3, direction: Vector3, space: PhysicsDirectSpaceState3D) -> Nail:
	# Query layer 8 (nail heads — Area3D). We need to use intersect_ray with
	# collide_with_areas = true.
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * ray_distance
	)
	query.collision_mask = 8  # nail head layer
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var result = space.intersect_ray(query)

	if result and result.collider is Area3D:
		var area := result.collider as Area3D
		var parent := area.get_parent()
		if parent is Nail:
			return parent as Nail

	return null


func _raycast_for_surface(origin: Vector3, direction: Vector3, space: PhysicsDirectSpaceState3D) -> Variant:
	# Query layers 1 (table) + 2 (placed parts) = mask 3
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * ray_distance
	)
	query.collision_mask = 2  # only placed parts, not the table itself
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result := space.intersect_ray(query)

	if result:
		return result
	return null


func _find_nearest_other_part(exclude: JunkPart, near_pos: Vector3) -> JunkPart:
	if assembly_pivot == null:
		return null

	var nearest: JunkPart = null
	var nearest_dist: float = INF

	for child in assembly_pivot.get_children():
		if child is JunkPart and child != exclude and child.is_placed:
			var d: float = child.global_position.distance_to(near_pos)
			if d < nearest_dist:
				nearest_dist = d
				nearest = child

	# Only connect if reasonably close (within 0.5m)
	if nearest and nearest_dist < 0.5:
		return nearest
	return null


func _is_nail_too_close(hit_point: Vector3, min_distance: float = 0.015) -> bool:
	var nodes_to_check: Array[Node] = []
	if assembly_pivot:
		nodes_to_check = assembly_pivot.get_children()
	elif get_tree() and get_tree().current_scene:
		nodes_to_check = get_tree().current_scene.get_children()

	for child in nodes_to_check:
		if child is Nail:
			var nail_node := child as Nail
			# Calculate the nail's entry point on the surface
			var nail_basis_y: Vector3 = nail_node.global_basis.y.normalized()
			var remaining_depth: float = nail_node.target_depth * (1.0 - nail_node.get_progress())
			var entry_point: Vector3 = nail_node.global_position - nail_basis_y * remaining_depth

			if entry_point.distance_to(hit_point) < min_distance:
				return true

	return false
