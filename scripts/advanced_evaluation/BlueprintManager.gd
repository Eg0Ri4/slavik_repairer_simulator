extends Node
class_name BlueprintManager

signal blueprint_completed(final_score: float)
signal score_updated(current_score: float)

@export var ghost_root: Node3D
@export var player_parts_root: Node3D
@export var target_threshold: float = 0.85 # 85% required

var _ghost_pieces: Array[GhostPiece] = []
var _eval_pending: bool = false

func _ready() -> void:
	if ghost_root:
		_collect_ghost_pieces(ghost_root)

func _collect_ghost_pieces(node: Node) -> void:
	if node is GhostPiece:
		_ghost_pieces.append(node)
	for child in node.get_children():
		_collect_ghost_pieces(child)

## Hook 1: Called when a player adds/removes a part
func on_part_hierarchy_changed() -> void:
	_request_evaluation()

## Hook 2: Called when a player drives a nail or connects parts
func on_connection_made() -> void:
	_request_evaluation()

## Hook 3: Connect this to the 'sleeping_state_changed' of player RigidBody3Ds
func on_part_sleeping_changed(part: RigidBody3D) -> void:
	if part.sleeping:
		_request_evaluation()

func _request_evaluation() -> void:
	if not _eval_pending:
		_eval_pending = true
		call_deferred("_perform_evaluation")

func _perform_evaluation() -> void:
	_eval_pending = false
	if _ghost_pieces.is_empty(): return
	
	var all_player_parts: Array[RigidBody3D] = []
	_collect_rigid_bodies(player_parts_root, all_player_parts)
	
	var total_score: float = 0.0
	for piece in _ghost_pieces:
		total_score += piece.evaluate_piece(all_player_parts)
		
	var avg_score = total_score / float(_ghost_pieces.size())
	score_updated.emit(avg_score)
	
	if avg_score >= target_threshold:
		blueprint_completed.emit(avg_score)

func _collect_rigid_bodies(node: Node, result: Array[RigidBody3D]) -> void:
	if node is RigidBody3D:
		result.append(node)
	for child in node.get_children():
		_collect_rigid_bodies(child, result)
