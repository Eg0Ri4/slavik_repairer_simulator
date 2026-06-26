## AttachmentSystem.gd
## Handles spawning PinJoint3D (Bolts) or Generic6DOFJoint3D (Tape)
## between a newly placed part and the nearest existing assembly part.
##
## IMPORTANT: Joint node paths must be assigned AFTER the joint is
## added to the scene tree (Godot 4 requirement for get_path_to).
class_name AttachmentSystem
extends Node

func attach(new_part: JunkPart, assembly_pivot: Node3D) -> Joint3D:
	# Find nearest existing placed part
	var nearest: JunkPart = _find_nearest_placed(new_part, assembly_pivot)

	var joint: Joint3D
	match GameState.active_tool:
		"bolts":
			joint = _create_bolt_joint(new_part, nearest, assembly_pivot)
		"tape":
			joint = _create_tape_joint(new_part, nearest, assembly_pivot)
		_:
			joint = _create_bolt_joint(new_part, nearest, assembly_pivot)

	return joint

# ── Joint factories ──────────────────────────────────────────────────────────
func _create_bolt_joint(new_part: JunkPart, anchor: JunkPart, pivot: Node3D) -> Joint3D:
	var joint := PinJoint3D.new()
	_setup_joint(joint, new_part, anchor, pivot)
	return joint

func _create_tape_joint(new_part: JunkPart, anchor: JunkPart, pivot: Node3D) -> Joint3D:
	var joint := Generic6DOFJoint3D.new()

	# Soft angular limits — gives a wobbly tape feel
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)

	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.3)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,  0.3)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.3)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,  0.3)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.15)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,  0.15)

	# Small linear "give"
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)

	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.02)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,  0.02)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.02)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,  0.02)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.02)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,  0.02)

	_setup_joint(joint, new_part, anchor, pivot)
	return joint

func _setup_joint(joint: Joint3D, new_part: JunkPart, anchor: JunkPart, pivot: Node3D) -> void:
	# Position the joint at the midpoint between the two bodies
	var joint_pos: Vector3 = new_part.global_position
	if anchor:
		joint_pos = (new_part.global_position + anchor.global_position) * 0.5
	joint.global_position = joint_pos

	# CRITICAL: add to scene tree FIRST, then assign node paths
	pivot.add_child(joint)

	# Now we can safely call get_path_to (nodes must share a common ancestor)
	if anchor:
		joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(new_part)

# ── Helpers ──────────────────────────────────────────────────────────────────
func _find_nearest_placed(new_part: JunkPart, pivot: Node3D) -> JunkPart:
	var nearest: JunkPart = null
	var nearest_dist: float = INF

	for child in pivot.get_children():
		if child is JunkPart and child != new_part and child.is_placed:
			var d: float = child.global_position.distance_to(new_part.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = child

	return nearest
