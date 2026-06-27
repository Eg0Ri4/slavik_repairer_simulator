## EvaluationSystem.gd
## Evaluates the assembly against the current OrderData using two modes:
## 1. Legacy Spatial Tag system (distance-based scoring)
## 2. 2D Blueprint Silhouette Raycast Grid (alignment scoring)
class_name EvaluationSystem
extends Node

# ── Silhouette grid configuration ────────────────────────────────────────────
const GRID_COLS: int = 12
const GRID_ROWS: int = 12
## Points awarded per valid ray hit inside the blueprint
const MATCH_POINTS: int = 10
## Points subtracted per ray that hits structure outside blueprint bounds
const OVERFLOW_PENALTY: int = 5
## Points subtracted per required blueprint cell that passes through empty space
const EMPTY_PENALTY: int = 8

# ── Legacy Evaluate (Spatial Tag) ────────────────────────────────────────────
func evaluate(assembly_pivot: Node3D, order: OrderData) -> Dictionary:
	var total_score: int = 0
	var max_score: int = 0
	var results: Array[Dictionary] = []

	for req in order.requirements:
		var required_tag: String = req.get("required_tag", "")
		var target_local: Vector3 = req.get("target_position", Vector3.ZERO)
		var points: int = req.get("points", 100)
		max_score += points

		var target_world: Vector3 = assembly_pivot.to_global(target_local)
		var best_part: Node3D = null
		var best_dist: float = INF

		for child in assembly_pivot.get_children():
			if not child is JunkPart:
				continue
			var part := child as Node3D
			if required_tag in part.tags:
				var dist: float = child.global_position.distance_to(target_world)
				if dist < best_dist:
					best_dist = dist
					best_part = part

		var req_result: Dictionary = {
			"tag": required_tag,
			"found": best_part != null,
			"distance": best_dist if best_part else -1.0,
			"points_possible": points,
			"points_earned": 0,
			"target_world": target_world
		}

		if best_part != null:
			if best_dist <= order.tolerance:
				req_result["points_earned"] = points
				total_score += points
			else:
				var falloff: float = clamp(1.0 - (best_dist / (order.tolerance * 4.0)), 0.0, 1.0)
				var partial: int = int(points * falloff)
				req_result["points_earned"] = partial
				total_score += partial

		results.append(req_result)

	return {
		"total_score": total_score,
		"max_score": max_score,
		"percentage": int((float(total_score) / float(max(max_score, 1))) * 100),
		"requirements": results
	}

# ── 2D Blueprint Silhouette Evaluation ───────────────────────────────────────

func evaluate_silhouette(camera: Camera3D, order: OrderData, assembly_pivot: Node3D) -> Dictionary:
	var pct: float = evaluate_assembly(order, camera)
	var passed: bool = pct >= order.pass_tolerance

	var detail: String = "Grid: %dx%d\nScore: %d%%\n%s" % [
		GRID_COLS, GRID_ROWS,
		int(pct),
		"✅ PASSED!" if passed else "❌ Keep tweaking..."
	]

	return {
		"percentage": int(pct),
		"passed": passed,
		"matches": 0,
		"overflows": 0,
		"empties": 0,
		"detail": detail
	}


func evaluate_assembly(active_order: OrderData, camera: Camera3D) -> float:
	if active_order.blueprint_silhouette == null:
		return 0.0

	var tex: Texture2D = active_order.blueprint_silhouette
	var img: Image = tex.get_image()
	if img == null:
		return 0.0

	if img.is_compressed():
		img.decompress()

	var tex_w: float = float(img.get_width())
	var tex_h: float = float(img.get_height())

	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size

	# 1. Generate an Automated Screen Sampling Grid
	# Read the visual boundaries / aspect ratio of the blueprint silhouette
	var scale_factor: float = min(viewport_size.x * 0.6 / tex_w, viewport_size.y * 0.6 / tex_h)
	var sil_w: float = tex_w * scale_factor
	var sil_h: float = tex_h * scale_factor
	var offset_x: float = (viewport_size.x - sil_w) * 0.5
	var offset_y: float = (viewport_size.y - sil_h) * 0.5

	var space_state = camera.get_world_3d().direct_space_state
	var required_tags: Array[String] = []
	required_tags.append_array(active_order.required_component_tags)

	var matches: int = 0
	var overflows: int = 0
	var empties: int = 0
	var total_required: int = 0

	# Nested loop to create a coordinate sampling matrix
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var u: float = (float(col) + 0.5) / float(GRID_COLS)
			var v: float = (float(row) + 0.5) / float(GRID_ROWS)

			var grid_screen_pos: Vector2 = Vector2(offset_x + u * sil_w, offset_y + v * sil_h)

			var px_x: int = clampi(int(u * tex_w), 0, int(tex_w) - 1)
			var px_y: int = clampi(int(v * tex_h), 0, int(tex_h) - 1)
			var pixel: Color = img.get_pixel(px_x, px_y)

			var is_inside_blueprint: bool = pixel.a > 0.5

			# 2. Project 2D-to-3D Viewport Raycasts
			var from = camera.project_ray_origin(grid_screen_pos)
			var to = from + camera.project_ray_normal(grid_screen_pos) * 100.0
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.collision_mask = 2 # JunkPart layer
			var result = space_state.intersect_ray(query)

			if is_inside_blueprint:
				total_required += 1
				if result and result.collider is JunkPart:
					var part = result.collider as Node3D
					var tag_match: bool = false
					for tag in part.tags:
						if tag in required_tags:
							tag_match = true
							break
					if tag_match:
						matches += 1
					else:
						empties += 1
				else:
					empties += 1
			else:
				if result and result.collider is JunkPart:
					overflows += 1

	if total_required == 0:
		return 0.0

	var raw_score: float = float(matches * MATCH_POINTS - overflows * OVERFLOW_PENALTY - empties * EMPTY_PENALTY)
	var max_possible: float = float(total_required * MATCH_POINTS)
	var percentage: float = max(raw_score / max_possible * 100.0, 0.0)

	return clamp(percentage, 0.0, 100.0)

func grade_label(percentage: int) -> String:
	match true:
		_ when percentage >= 90:
			return "GENIUS ENGINEER!"
		_ when percentage >= 70:
			return "Pretty Good Work"
		_ when percentage >= 50:
			return "Needs Some Tape"
		_ when percentage >= 25:
			return "What Even IS This?"
		_:
			return "Trust Me I'm an Engineer 🔧"
