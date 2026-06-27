## CameraController.gd
## Handles smooth camera transitions between TABLE_VIEW and UNDER_TABLE_VIEW.
## Also handles mouse-drag rotation of the AssemblyPivot in TABLE_VIEW,
## BUT only when no part is currently held (RMB is then owned by JunkPart for
## Skyrim-style inspect rotation).
extends Node3D

# ── Inspector-configurable positions ─────────────────────────────────────────
@export var table_view_target: Node3D
@export var under_table_view_target: Node3D

@export var table_position: Vector3 = Vector3(0.0, 1.4, 1.2)
@export var table_rotation_deg: Vector3 = Vector3(-45.0, 0.0, 0.0)

@export var under_table_position: Vector3 = Vector3(0.448, -0.316, -1.389)
@export var under_table_rotation_deg: Vector3 = Vector3(-7.0, -3.64, -41.9)

@export var tween_duration: float = 0.8

# ── Pivot rotation settings ───────────────────────────────────────────────────
@export var pivot_sensitivity: float = 0.5   # degrees per pixel of drag

# ── Internal refs ─────────────────────────────────────────────────────────────
var _camera: Camera3D
var _assembly_pivot: Node3D
var _is_tweening: bool = false

# Right-mouse drag state (assembly pivot orbit — only when no part is held)
var _rmbDown: bool = false
var _lastMousePos: Vector2 = Vector2.ZERO

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_camera = get_node_or_null("Camera3D")
	if _camera == null:
		push_error("CameraController: no Camera3D child found!")
		return

	_assembly_pivot = get_node_or_null("../AssemblyPivot")

	_apply_state_instant("TABLE_VIEW")

func _input(event: InputEvent) -> void:
	if _is_tweening:
		return

	# ── Right-drag to orbit the assembly — only when NOT holding a part ───────
	# When a part IS held, RMB is consumed by JunkPart for Skyrim-style rotation.
	if GameState.camera_state == "TABLE_VIEW" and GameState.held_part == null:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_rmbDown = event.pressed
				if event.pressed:
					_lastMousePos = event.position
				# Do NOT call set_input_as_handled here — let it fall through
				# so other nodes can still observe the mouse-button event if needed.

		elif event is InputEventMouseMotion and _rmbDown:
			if _assembly_pivot:
				var delta: Vector2 = event.position - _lastMousePos
				_lastMousePos = event.position
				# Yaw (horizontal drag → Y rotation)
				_assembly_pivot.rotate_y(deg_to_rad(-delta.x * pivot_sensitivity))
				# Pitch (vertical drag → X rotation, halved to feel less sensitive)
				_assembly_pivot.rotate_x(deg_to_rad(-delta.y * pivot_sensitivity * 0.5))
	else:
		# A part is held or we're in another view — cancel any in-progress orbit drag
		# so it doesn't resume unexpectedly when the part is dropped.
		_rmbDown = false

# ── Public API ────────────────────────────────────────────────────────────────
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

# ── Internal helpers ──────────────────────────────────────────────────────────
func _apply_state_instant(state: String) -> void:
	GameState.set_camera_state(state)
	if state == "TABLE_VIEW":
		if table_view_target:
			global_position = table_view_target.global_position
			global_rotation = table_view_target.global_rotation
		else:
			position = table_position
			rotation_degrees = table_rotation_deg
	else:
		if under_table_view_target:
			global_position = under_table_view_target.global_position
			global_rotation = under_table_view_target.global_rotation
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
	var use_global := false

	if new_state == "TABLE_VIEW":
		if table_view_target:
			target_pos = table_view_target.global_position
			target_rot = table_view_target.global_rotation_degrees
			use_global = true
		else:
			target_pos = table_position
			target_rot = table_rotation_deg
	else:
		if under_table_view_target:
			target_pos = under_table_view_target.global_position
			target_rot = under_table_view_target.global_rotation_degrees
			use_global = true
		else:
			target_pos = under_table_position
			target_rot = under_table_rotation_deg

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	if use_global:
		tw.tween_property(self, "global_position", target_pos, tween_duration)
		tw.tween_property(self, "global_rotation_degrees", target_rot, tween_duration)
	else:
		tw.tween_property(self, "position", target_pos, tween_duration)
		tw.tween_property(self, "rotation_degrees", target_rot, tween_duration)
	tw.finished.connect(func() -> void: _is_tweening = false, CONNECT_ONE_SHOT)
