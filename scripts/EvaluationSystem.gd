## EvaluationSystem.gd
## Evaluates the assembly against the current OrderData.
## Uses a Spatial Tag system: checks distance of each tagged part to its target.
class_name EvaluationSystem
extends Node

func evaluate(assembly_pivot: Node3D, order: OrderData) -> Dictionary:
	var total_score: int = 0
	var max_score: int = 0
	var results: Array[Dictionary] = []

	for req in order.requirements:
		var required_tag: String = req.get("required_tag", "")
		var target_local: Vector3 = req.get("target_position", Vector3.ZERO)
		var points: int = req.get("points", 100)
		max_score += points

		# Convert target to world space (relative to pivot)
		var target_world: Vector3 = assembly_pivot.to_global(target_local)

		# Find the closest part with the matching tag
		var best_part: JunkPart = null
		var best_dist: float = INF

		for child in assembly_pivot.get_children():
			if not child is JunkPart:
				continue
			var part := child as JunkPart
			if required_tag in part.tags:
				var dist: float = child.global_position.distance_to(target_world)
				if dist < best_dist:
					best_dist = dist
					best_part = part

		# Score this requirement
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
				# Partial credit: distance-based falloff
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
