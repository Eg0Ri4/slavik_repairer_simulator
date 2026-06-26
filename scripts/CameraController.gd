## CameraController.gd
## Handles smooth camera transitions between TABLE_VIEW and UNDER_TABLE_VIEW.
## Also handles mouse-drag rotation of the AssemblyPivot in TABLE_VIEW.
extends Node3D

# ── Inspector-configurable positions ────────────────────────────────────────
@export var table_position: Vector3 = Vector3(0.0, 1.8, 1.8)
@export var table_rotation_deg: Vector3 = Vector3(-45.0, 0.0, 0.0)

@export var under_table_position: Vector3 = Vector3(0.0, -0.7, 1.2)
@export var under_table_rotation_deg: Vector3 = Vector3(-20.0, 0.0, 0.0)

@export var tween_duration: float = 0.8

# ── Pivot rotation settings ──────────────────────────────────────────────────
@export var pivot_sensitivity: float = 0.5   # degrees per pixel of drag

# ── Internal refs ────────────────────────────────────────────────────────────
var _camera: Camera3D
var _assembly_pivot: Node3D
var _is_tweening: bool = false

# Right-mouse drag state
var _rmbDown: bool = false
var _lastMousePos: Vector2 = Vector2.ZERO

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Camera is a child of this controller
	_camera = get_node_or_null("Camera3D")
	if _camera == null:
		push_error("CameraController: no Camera3D child found!")
		return

	# Find AssemblyPivot in the scene tree
	_assembly_pivot = get_tree().get_first_node_in_group("assembly_pivot")

	# Start at TABLE_VIEW
	_apply_state_instant("TABLE_VIEW")

func _input(event: InputEvent) -> void:
	if _is_tweening:
		return

	# ── Right-drag to rotate assembly (TABLE_VIEW only) ──────────────────
	if GameState.camera_state == "TABLE_VIEW":
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_rmbDown = event.pressed
				if event.pressed:
					_lastMousePos = event.position
		elif event is InputEventMouseMotion and _rmbDown:
			if _assembly_pivot:
				var delta: Vector2 = event.position - _lastMousePos
				_lastMousePos = event.position
				# Yaw (horizontal drag → Y rotation)
				_assembly_pivot.rotate_y(deg_to_rad(-delta.x * pivot_sensitivity))
				# Pitch (vertical drag → X rotation, clamped)
				_assembly_pivot.rotate_x(deg_to_rad(-delta.y * pivot_sensitivity * 0.5))

# ── Public API ───────────────────────────────────────────────────────────────
func go_to_table_view() -> void:
	if GameState.camera_state == "TABLE_VIEW":
		return
	_tween_to("TABLE_VIEW")

func go_to_under_table_view() -> void:
	if GameState.camera_state == "UNDER_TABLE_VIEW":
		return
	_tween_to("UNDER_TABLE_VIEW")

func toggle_view() -> void:
	if GameState.camera_state == "TABLE_VIEW":
		go_to_under_table_view()
	else:
		go_to_table_view()

# ── Internal helpers ─────────────────────────────────────────────────────────
func _apply_state_instant(state: String) -> void:
	GameState.set_camera_state(state)
	if state == "TABLE_VIEW":
		position = table_position
		rotation_degrees = table_rotation_deg
	else:
		position = under_table_position
		rotation_degrees = under_table_rotation_deg

func _tween_to(new_state: String) -> void:
	if _is_tweening:
		return
	_is_tweening = true
	GameState.set_camera_state(new_state)

	var target_pos: Vector3
	var target_rot: Vector3

	if new_state == "TABLE_VIEW":
		target_pos = table_position
		target_rot = table_rotation_deg
	else:
		target_pos = under_table_position
		target_rot = under_table_rotation_deg

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "position", target_pos, tween_duration)
	tw.tween_property(self, "rotation_degrees", target_rot, tween_duration)
	tw.finished.connect(func() -> void: _is_tweening = false, CONNECT_ONE_SHOT)
