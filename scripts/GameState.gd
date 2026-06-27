## GameState - Autoload singleton for global game state
extends Node

## GamePhase Enum
enum GamePhase { MENU, PLAYING }
var current_phase: GamePhase = GamePhase.MENU

func is_playing() -> bool:
	return current_phase == GamePhase.PLAYING

func set_phase(phase: GamePhase) -> void:
	current_phase = phase
	phase_changed.emit(phase)

## Current tool: "tape", "nail", "crowbar", or "none"
var active_tool: String = "none"

## The part currently being held/dragged
var held_part: RigidBody3D = null

## Camera state
var camera_state: String = "TABLE_VIEW"  # or "UNDER_TABLE_VIEW"

## All parts attached to the assembly
var assembly_parts: Array[Node3D] = []

## Current order being worked on
var current_order: OrderData = null

# ── Compound Cluster State ───────────────────────────────────────────────────
## CRITICAL: These MUST be initialized here at declaration so they exist
## regardless of how scenes are launched from the editor.
## Secondary parts in the cluster (excludes the primary held_part).
var held_cluster: Array[Node3D] = []
## Transform offset of each cluster member relative to the primary part at pick-up time.
## Keyed by the JunkPart instance (object identity).
var cluster_offsets: Dictionary = {}   # JunkPart → Transform3D
## Joints connecting cluster members — disabled during movement, re-enabled on drop.
var cluster_joints: Array[Joint3D] = []

## Signals
signal phase_changed(new_phase: GamePhase)
signal tool_changed(new_tool: String)
signal part_picked_up(part: RigidBody3D)
signal part_placed()
signal camera_state_changed(new_state: String)
signal nail_event(event_name: String, data: Variant)

func set_active_tool(tool_name: String) -> void:
	active_tool = tool_name
	tool_changed.emit(tool_name)

func pick_up_part(part: RigidBody3D) -> void:
	held_part = part
	part_picked_up.emit(part)

func place_part() -> void:
	held_part = null
	part_placed.emit()

## Store the cluster (secondary parts + joints) for compound movement.
## `primary` is the part the player clicked — it's stored in held_part separately.
## `secondary_parts` are the other connected parts (excluding primary).
## `joints` are the Joint3D nodes connecting cluster members.
func pick_up_cluster(primary: Node3D, secondary_parts: Array[Node3D], joints: Array[Joint3D]) -> void:
	held_cluster = secondary_parts
	cluster_joints = joints
	cluster_offsets.clear()

	var primary_inv: Transform3D = primary.global_transform.affine_inverse()
	for part: Node3D in secondary_parts:
		# Store each part's transform relative to the primary
		cluster_offsets[part] = primary_inv * part.global_transform

## Clear all cluster state. Called when the assembly is dropped.
func drop_cluster() -> void:
	held_cluster.clear()
	cluster_offsets.clear()
	cluster_joints.clear()

func set_camera_state(new_state: String) -> void:
	camera_state = new_state
	camera_state_changed.emit(new_state)

func register_assembly_part(part: Node3D) -> void:
	if part not in assembly_parts:
		assembly_parts.append(part)

func clear_assembly() -> void:
	assembly_parts.clear()
