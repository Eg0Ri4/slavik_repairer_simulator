extends Area3D
class_name GhostPiece

signal state_changed(old_state, new_state)

enum PieceState { UNMATCHED, MISALIGNED, MATCHED }

var current_state: PieceState = PieceState.UNMATCHED
var current_score: float = 0.0 # 0.0 to 1.0

@export var orientation_tolerance: float = 0.8 # Dot product threshold
@export var position_tolerance: float = 0.2

var mesh_instance: MeshInstance3D
var shader_material: ShaderMaterial

func _ready() -> void:
	# Set up material
	mesh_instance = _find_mesh(self)
	if mesh_instance:
		if mesh_instance.material_override and mesh_instance.material_override is ShaderMaterial:
			shader_material = mesh_instance.material_override
		else:
			shader_material = ShaderMaterial.new()
			shader_material.shader = preload("res://scripts/advanced_evaluation/GhostFeedback.gdshader")
			mesh_instance.material_override = shader_material

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var m = _find_mesh(child)
		if m: return m
	return null

## Called by BlueprintManager when a physics state settles
func evaluate_piece(player_parts: Array[RigidBody3D]) -> float:
	var best_score := 0.0
	var best_state := PieceState.UNMATCHED
	
	# Find my own box extents (assuming a BoxShape3D child)
	var my_col = _find_col(self)
	var my_extents := Vector3.ONE
	if my_col and my_col.shape is BoxShape3D:
		my_extents = (my_col.shape as BoxShape3D).size

	for part in player_parts:
		if not overlaps_body(part):
			continue
			
		# 1. Proportion Normalization
		var part_col = _find_col(part)
		var part_extents := Vector3.ONE
		if part_col and part_col.shape is BoxShape3D:
			part_extents = (part_col.shape as BoxShape3D).size
			
		# Scale compensation factor (how much larger/smaller the player part is)
		var volume_ratio = part_extents.length() / max(my_extents.length(), 0.001)
		var scaled_pos_tolerance = position_tolerance * clamp(volume_ratio, 0.8, 1.5)
		
		# 2. Position Validation
		var dist = global_position.distance_to(part.global_position)
		if dist > scaled_pos_tolerance:
			if PieceState.MISALIGNED > best_state:
				best_state = PieceState.MISALIGNED
			continue
			
		# 3. Orientation Validation (Dot product)
		# We check alignment along all 3 local axes. Since parts can be flipped 180 deg, we use abs()
		var dot_x = abs(global_transform.basis.x.normalized().dot(part.global_transform.basis.x.normalized()))
		var dot_y = abs(global_transform.basis.y.normalized().dot(part.global_transform.basis.y.normalized()))
		var dot_z = abs(global_transform.basis.z.normalized().dot(part.global_transform.basis.z.normalized()))
		
		var avg_alignment = (dot_x + dot_y + dot_z) / 3.0
		
		if avg_alignment >= orientation_tolerance:
			best_score = avg_alignment
			best_state = PieceState.MATCHED
			break # Found a perfect match!
		else:
			best_score = max(best_score, avg_alignment * 0.5)
			if PieceState.MISALIGNED > best_state:
				best_state = PieceState.MISALIGNED

	_set_state(best_state)
	current_score = best_score if best_state == PieceState.MATCHED else 0.0
	return current_score

func _find_col(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		if child is CollisionShape3D: return child
		var c = _find_col(child)
		if c: return c
	return null

func _set_state(new_state: PieceState) -> void:
	if current_state == new_state: return
	var old_state = current_state
	current_state = new_state
	
	if shader_material:
		var tween = create_tween().set_parallel(true)
		match current_state:
			PieceState.UNMATCHED:
				tween.tween_property(shader_material, "shader_parameter/weight_misaligned", 0.0, 0.5)
				tween.tween_property(shader_material, "shader_parameter/weight_matched", 0.0, 0.5)
				shader_material.set_shader_parameter("enable_pulse", false)
			PieceState.MISALIGNED:
				tween.tween_property(shader_material, "shader_parameter/weight_misaligned", 1.0, 0.5)
				tween.tween_property(shader_material, "shader_parameter/weight_matched", 0.0, 0.5)
				shader_material.set_shader_parameter("enable_pulse", false)
			PieceState.MATCHED:
				tween.tween_property(shader_material, "shader_parameter/weight_misaligned", 0.0, 0.5)
				tween.tween_property(shader_material, "shader_parameter/weight_matched", 1.0, 0.5)
				shader_material.set_shader_parameter("enable_pulse", true)

	state_changed.emit(old_state, new_state)
