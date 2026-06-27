with open("scripts/Main.gd", "r") as f:
    content = f.read()

# 1. Connect tape_removed in _build_systems
orig_sys = "nail_tool.nail_placement_blocked.connect(_on_nail_placement_blocked)"
new_sys = orig_sys + "\n\tnail_tool.tape_removed.connect(_on_tape_removed)"
content = content.replace(orig_sys, new_sys)

# 2. Update _on_nail_placed to connect nail_unfastened
orig_placed = """func _on_nail_placed(nail: Nail) -> void:
	if nail_status_label:
		nail_status_label.text = "🔨 Nail placed! Click it to hammer in (%d%%)" % int(nail.get_progress() * 100)"""

new_placed = """func _on_nail_placed(nail: Nail) -> void:
	if not nail.nail_unfastened.is_connected(_on_nail_removed):
		nail.nail_unfastened.connect(_on_nail_removed)
	if nail_status_label:
		nail_status_label.text = "🔨 Nail placed! Click it to hammer in (%d%%)" % int(nail.get_progress() * 100)"""
content = content.replace(orig_placed, new_placed)

# 3. Add _on_nail_removed, _on_tape_removed, and _recalculate_assembly_collisions
collision_funcs = """
func _on_nail_removed() -> void:
	call_deferred("_recalculate_assembly_collisions")

func _on_tape_removed() -> void:
	call_deferred("_recalculate_assembly_collisions")

func _recalculate_assembly_collisions() -> void:
	if not assembly_pivot:
		return
		
	var all_parts: Array[PhysicsBody3D] = []
	for child in assembly_pivot.get_children():
		if child is JunkPart:
			all_parts.append(child as PhysicsBody3D)
			
	# 1. Clear all exceptions between assembly parts
	for i in range(all_parts.size()):
		for j in range(i + 1, all_parts.size()):
			all_parts[i].remove_collision_exception_with(all_parts[j])
			all_parts[j].remove_collision_exception_with(all_parts[i])
			
	# 2. Re-apply for actual connected clusters
	var visited: Array[Node3D] = []
	for part in all_parts:
		if part in visited:
			continue
		var cluster: Array[Node3D] = attachment_system.get_connected_cluster(part, assembly_pivot)
		for c in cluster:
			if not c in visited:
				visited.append(c)
				
		for i in range(cluster.size()):
			for j in range(i + 1, cluster.size()):
				var a := cluster[i] as PhysicsBody3D
				var b := cluster[j] as PhysicsBody3D
				if a and b:
					a.add_collision_exception_with(b)
					b.add_collision_exception_with(a)
"""

content += collision_funcs

# 4. Replace manual collision logic in _on_nail_driven
orig_driven = """	# ── Make the ENTIRE nailed cluster ignore internal collisions ─────────
	var root_body: Node3D = null
	if nail._surface_body is JunkPart:
		root_body = nail._surface_body as Node3D
	elif nail._top_body is JunkPart:
		root_body = nail._top_body as Node3D

	if root_body and assembly_pivot:
		var cluster: Array[Node3D] = attachment_system.get_connected_cluster(root_body, assembly_pivot)
		for i in range(cluster.size()):
			for j in range(i + 1, cluster.size()):
				var a: PhysicsBody3D = cluster[i] as PhysicsBody3D
				var b: PhysicsBody3D = cluster[j] as PhysicsBody3D
				a.add_collision_exception_with(b)
				b.add_collision_exception_with(a)"""

new_driven = """	call_deferred("_recalculate_assembly_collisions")"""
content = content.replace(orig_driven, new_driven)

# 5. Add to _on_tape_finished
orig_tape_fin = """func _on_tape_finished() -> void:
	if nail_status_label:
		nail_status_label.text = "✅ Taped! Place another or switch tools.\""""
new_tape_fin = """func _on_tape_finished() -> void:
	if nail_status_label:
		nail_status_label.text = "✅ Taped! Place another or switch tools."
	call_deferred("_recalculate_assembly_collisions")"""
content = content.replace(orig_tape_fin, new_tape_fin)

with open("scripts/Main.gd", "w") as f:
    f.write(content)
print("Main.gd patched for collision handling")
