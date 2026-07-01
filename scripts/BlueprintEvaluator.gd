## BlueprintEvaluator.gd
## Evaluates how closely the player's construction matches a "Ghost Blueprint"
## using 3D point-sampling coverage.
##
## DESIGN PHILOSOPHY:
##   Instead of requiring one player piece per ghost piece (1:1), this evaluator
##   checks what percentage of each ghost volume is FILLED by player parts.
##   Multiple small parts can together satisfy one ghost piece — just like
##   building a chair seat from several planks side by side.
##
## HOW IT WORKS:
##   1. For each ghost Area3D piece, generate a grid of sample points inside
##      its collision shape.
##   2. For each sample point, geometrically check if it falls inside ANY
##      player part's collision shape (Box, Sphere, Cylinder).
##   3. Coverage = filled_points / total_points.
##   4. A ghost piece is "matched" if coverage >= coverage_threshold.
##   5. Final score = average coverage across all ghost pieces.
##
## This approach is physics-engine-independent (pure math, no raycasts),
## so it works even when collision layers are temporarily disabled.
class_name BlueprintEvaluator
extends Node

# ── Tunable Tolerance Thresholds ─────────────────────────────────────────────

## Number of sample points per axis inside each ghost piece.
## Higher = more accurate but slower. 5 → 125 points, 4 → 64 points.
@export_range(3, 8) var samples_per_axis: int = 5

## Minimum coverage ratio (0.0–1.0) for a ghost piece to count as "matched".
## Set to 0.25 to match the 25% pass requirement.
@export_range(0.0, 1.0) var coverage_threshold: float = 0.25

## Margin added to player shapes when checking if they cover ghost points.
## Makes the blueprint evaluation more forgiving for slightly misaligned parts.
@export var forgiveness_margin: float = 0.05

## If true, print per-piece debug info to the console.
@export var debug_logging: bool = false

# ── Internal State ───────────────────────────────────────────────────────────

## Root node containing all ghost Area3D pieces.
var _ghost_root: Node3D = null

## Cached list of ghost Area3D nodes found under _ghost_root.
var _ghost_pieces: Array[Area3D] = []

## Invisible ghost block to check for over-building outside the ghost bounds.
var _spill_bounds_area: Area3D = null

# ── Public API ───────────────────────────────────────────────────────────────

## Assign the root node that contains all ghost Area3D blueprint pieces.
## Call this once after spawning the ghost model.
func set_ghost_root(root: Node3D) -> void:
	_ghost_root = root
	_ghost_pieces.clear()
	_spill_bounds_area = null
	_collect_ghost_pieces(root)
	if debug_logging:
		print("[BlueprintEvaluator] Found %d ghost pieces under '%s'" % [_ghost_pieces.size(), root.name])


## Run a full evaluation of the player's construction against the ghost blueprint.
##
## `player_parts_root` — the node whose children are the player's placed JunkParts
## (typically your AssemblyPivot).
##
## Returns:
##   {
##     "percentage": int (0–100),
##     "matched_count": int,
##     "total_ghost_pieces": int,
##     "pieces": Array[Dictionary]   ← per-piece breakdown
##   }
##
## Each entry in "pieces":
##   {
##     "ghost_label": String,
##     "matched": bool,
##     "coverage": float (0.0–1.0),
##     "filled_points": int,
##     "total_points": int,
##     "overlapping_parts": int       ← how many player parts contribute
##   }
func evaluate(player_parts_root: Node3D) -> Dictionary:
	if _ghost_pieces.is_empty():
		return _empty_result()

	# Collect all placed player parts (JunkPart RigidBody3D nodes)
	var player_parts: Array[RigidBody3D] = []
	_collect_player_parts(player_parts_root, player_parts)

	if player_parts.is_empty():
		return _empty_result()

	# Collect collision shape data for all player parts (cached for performance)
	var part_shapes: Array[Dictionary] = []
	for part in player_parts:
		var shapes := _extract_part_shapes(part)
		for s in shapes:
			part_shapes.append(s)

	# Evaluate each ghost piece
	var results: Array[Dictionary] = []
	var matched_count: int = 0
	var total_coverage: float = 0.0

	for ghost in _ghost_pieces:
		var piece_result := _evaluate_ghost_coverage(ghost, part_shapes)
		results.append(piece_result)
		total_coverage += piece_result["coverage"]
		if piece_result["matched"]:
			matched_count += 1

	var total := _ghost_pieces.size()
	# Score is average coverage across all ghost pieces, expressed as percentage
	var avg_coverage: float = total_coverage / float(max(total, 1))
	
	var spill_ratio: float = 0.0
	if _spill_bounds_area != null:
		spill_ratio = _evaluate_spill(_spill_bounds_area, part_shapes)
		if debug_logging:
			print("[BlueprintEvaluator] Spill ratio: %.1f%%" % (spill_ratio * 100.0))
			
	var pct: int = int(avg_coverage * 100.0)

	return {
		"percentage": pct,
		"spill_ratio": spill_ratio,
		"matched_count": matched_count,
		"total_ghost_pieces": total,
		"pieces": results
	}


## Convenience: returns just the percentage score (0–100).
func evaluate_percentage(player_parts_root: Node3D) -> int:
	return evaluate(player_parts_root)["percentage"]


## Show or hide the ghost blueprint visually.
func set_ghost_visible(visible: bool) -> void:
	if _ghost_root:
		_set_subtree_visible(_ghost_root, visible)


## Remove all ghost pieces and clear state.
func clear_ghost() -> void:
	if _ghost_root and is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
	_ghost_pieces.clear()
	_spill_bounds_area = null


# ── Ghost Piece Discovery ───────────────────────────────────────────────────

func _collect_ghost_pieces(node: Node) -> void:
	if node is Area3D:
		if node.has_meta("is_spill_bounds"):
			_spill_bounds_area = node as Area3D
		else:
			_ghost_pieces.append(node as Area3D)
	for child in node.get_children():
		_collect_ghost_pieces(child)


# ── Player Part Discovery ───────────────────────────────────────────────────

func _collect_player_parts(node: Node, result: Array[RigidBody3D]) -> void:
	for child in node.get_children():
		if child is JunkPart:
			result.append(child as RigidBody3D)


# ── Extract Collision Shapes from a Player Part ─────────────────────────────

## Returns an array of shape descriptors:
##   { "type": "box"|"sphere"|"cylinder"|"convex",
##     "global_transform": Transform3D,
##     "shape": Shape3D }
func _extract_part_shapes(part: RigidBody3D) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	for child in part.get_children():
		if child is CollisionShape3D and child.shape:
			shapes.append({
				"type": _shape_type_str(child.shape),
				"global_transform": child.global_transform,
				"inverse_transform": child.global_transform.affine_inverse(),
				"shape": child.shape
			})
	return shapes


func _shape_type_str(shape: Shape3D) -> String:
	if shape is BoxShape3D:
		return "box"
	if shape is SphereShape3D:
		return "sphere"
	if shape is CylinderShape3D:
		return "cylinder"
	return "other"


# ── Coverage Evaluation for a Single Ghost Piece ────────────────────────────

func _evaluate_ghost_coverage(ghost: Area3D, part_shapes: Array[Dictionary]) -> Dictionary:
	var label: String = ghost.get_meta("ghost_label", ghost.name)

	# Find the ghost's collision shape to sample inside
	var ghost_col := _find_first_collision_shape(ghost)
	if ghost_col == null or ghost_col.shape == null:
		return {
			"ghost_label": label, "matched": false, "coverage": 0.0,
			"filled_points": 0, "total_points": 0, "overlapping_parts": 0
		}

	# Generate sample points in world space inside the ghost's collision shape
	var sample_points: Array[Vector3] = _generate_sample_points(ghost_col)
	var total_points: int = sample_points.size()
	if total_points == 0:
		return {
			"ghost_label": label, "matched": false, "coverage": 0.0,
			"filled_points": 0, "total_points": 0, "overlapping_parts": 0
		}

	# Check each sample point against all player part shapes
	var filled_points: int = 0
	var contributing_shapes: Dictionary = {}  # track unique part shapes that contribute

	for point in sample_points:
		for i in range(part_shapes.size()):
			var ps: Dictionary = part_shapes[i]
			# Transform world point into the collision shape's local space
			var local_point: Vector3 = ps["inverse_transform"] * point
			if _is_point_in_shape(local_point, ps["shape"], forgiveness_margin):
				filled_points += 1
				contributing_shapes[i] = true
				break  # point is filled, no need to check more shapes

	var coverage: float = float(filled_points) / float(total_points)
	var matched: bool = coverage >= coverage_threshold

	if debug_logging:
		print("[BlueprintEvaluator] %s: %d/%d points filled (%.0f%%) - %s" % [
			label, filled_points, total_points, coverage * 100.0,
			"[V] MATCHED" if matched else "[X] NOT MATCHED"
		])

	return {
		"ghost_label": label,
		"matched": matched,
		"coverage": coverage,
		"filled_points": filled_points,
		"total_points": total_points,
		"overlapping_parts": contributing_shapes.size()
	}

func _evaluate_spill(spill_area: Area3D, part_shapes: Array[Dictionary]) -> float:
	var col := _find_first_collision_shape(spill_area)
	if not col: return 0.0
	var sample_points := _generate_sample_points(col)
	var total_points := sample_points.size()
	if total_points == 0: return 0.0
	
	var spilled_points := 0
	for point in sample_points:
		var inside_ghost := false
		for ghost in _ghost_pieces:
			var gc = _find_first_collision_shape(ghost)
			if gc:
				var local = gc.global_transform.affine_inverse() * point
				if _is_point_in_shape(local, gc.shape):
					inside_ghost = true
					break
		
		if not inside_ghost:
			var inside_part := false
			for ps in part_shapes:
				var local = ps["inverse_transform"] * point
				if _is_point_in_shape(local, ps["shape"]):
					inside_part = true
					break
			if inside_part:
				spilled_points += 1
				
	return float(spilled_points) / float(total_points)

# ── Sample Point Generation ─────────────────────────────────────────────────

## Generate a 3D grid of evenly-spaced sample points inside the ghost's
## collision shape, transformed to world space.
func _generate_sample_points(col_shape: CollisionShape3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var shape: Shape3D = col_shape.shape
	var xform: Transform3D = col_shape.global_transform
	var n: int = samples_per_axis

	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		for xi in range(n):
			for yi in range(n):
				for zi in range(n):
					var local := Vector3(
						lerpf(-half.x, half.x, (float(xi) + 0.5) / float(n)),
						lerpf(-half.y, half.y, (float(yi) + 0.5) / float(n)),
						lerpf(-half.z, half.z, (float(zi) + 0.5) / float(n))
					)
					points.append(xform * local)

	elif shape is SphereShape3D:
		var r: float = (shape as SphereShape3D).radius
		# Sample in a cube, discard points outside the sphere
		for xi in range(n):
			for yi in range(n):
				for zi in range(n):
					var local := Vector3(
						lerpf(-r, r, (float(xi) + 0.5) / float(n)),
						lerpf(-r, r, (float(yi) + 0.5) / float(n)),
						lerpf(-r, r, (float(zi) + 0.5) / float(n))
					)
					if local.length() <= r:
						points.append(xform * local)

	elif shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		var r: float = cyl.radius
		var h: float = cyl.height * 0.5
		for xi in range(n):
			for yi in range(n):
				for zi in range(n):
					var local := Vector3(
						lerpf(-r, r, (float(xi) + 0.5) / float(n)),
						lerpf(-h, h, (float(yi) + 0.5) / float(n)),
						lerpf(-r, r, (float(zi) + 0.5) / float(n))
					)
					if Vector2(local.x, local.z).length() <= r:
						points.append(xform * local)

	elif shape is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if pts.size() > 0:
			var aabb := AABB(pts[0], Vector3.ZERO)
			for i in range(1, pts.size()):
				aabb = aabb.expand(pts[i])
			var half: Vector3 = aabb.size * 0.5
			var center: Vector3 = aabb.get_center()
			for xi in range(n):
				for yi in range(n):
					for zi in range(n):
						var local := Vector3(
							lerpf(-half.x, half.x, (float(xi) + 0.5) / float(n)),
							lerpf(-half.y, half.y, (float(yi) + 0.5) / float(n)),
							lerpf(-half.z, half.z, (float(zi) + 0.5) / float(n))
						) + center
						points.append(xform * local)

	else:
		# Fallback: treat as a tiny box
		var fallback_size := Vector3(0.05, 0.05, 0.05)
		var half := fallback_size * 0.5
		for xi in range(n):
			for yi in range(n):
				for zi in range(n):
					var local := Vector3(
						lerpf(-half.x, half.x, (float(xi) + 0.5) / float(n)),
						lerpf(-half.y, half.y, (float(yi) + 0.5) / float(n)),
						lerpf(-half.z, half.z, (float(zi) + 0.5) / float(n))
					)
					points.append(xform * local)

	return points


# ── Point-in-Shape Tests (Pure Math) ────────────────────────────────────────

## Check if a point (already in the shape's LOCAL space) is inside the shape.
func _is_point_in_shape(local_point: Vector3, shape: Shape3D, margin: float = 0.0) -> bool:
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5 + Vector3.ONE * margin
		return (
			absf(local_point.x) <= half.x and
			absf(local_point.y) <= half.y and
			absf(local_point.z) <= half.z
		)

	if shape is SphereShape3D:
		return local_point.length() <= (shape as SphereShape3D).radius + margin

	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return (
			absf(local_point.y) <= (cyl.height * 0.5) + margin and
			Vector2(local_point.x, local_point.z).length() <= cyl.radius + margin
		)

	if shape is ConvexPolygonShape3D:
		# Approximate with AABB of the convex hull points
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if pts.size() < 4:
			return false
		var aabb := AABB(pts[0], Vector3.ZERO)
		for i in range(1, pts.size()):
			aabb = aabb.expand(pts[i])
		if margin > 0.0:
			aabb = aabb.grow(margin)
		return aabb.has_point(local_point)

	return false


# ── Helpers ──────────────────────────────────────────────────────────────────

func _find_first_collision_shape(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
		var found := _find_first_collision_shape(child)
		if found:
			return found
	return null


func _set_subtree_visible(node: Node3D, vis: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = vis
	for child in node.get_children():
		if child is Node3D:
			_set_subtree_visible(child as Node3D, vis)


func _empty_result() -> Dictionary:
	return {
		"percentage": 0,
		"matched_count": 0,
		"total_ghost_pieces": 0,
		"pieces": []
	}
