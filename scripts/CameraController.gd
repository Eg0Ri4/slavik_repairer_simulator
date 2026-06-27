## CameraController.gd
## Две Camera3D как дочерние ноды: MenuCamera (current=true) и GameCamera.
## CameraController-нода сама НЕ двигается — твиним transform самих камер.
## Supports TABLE_VIEW, UNDER_TABLE_VIEW, and EVAL_VIEW (orthographic).
extends Node3D

const MENU_CAM_NAME := "MenuCamera"
const GAME_CAM_NAME := "GameCamera"

@export var gameplay_tween_duration : float = 1.5
@export var view_tween_duration     : float = 0.8
@export var pivot_sensitivity       : float = 0.5

@export var under_table_position : Vector3 = Vector3(0.448, -0.316, -1.389)
@export var under_table_rotation : Vector3 = Vector3(-7.0, -3.64, -41.9)

## Orthographic evaluation view: camera looks straight down at the workbench.
@export var eval_ortho_position : Vector3 = Vector3(0.0, 2.0, 0.0)
@export var eval_ortho_rotation : Vector3 = Vector3(-90.0, 0.0, 0.0)
@export var eval_ortho_size     : float = 1.5

var _menu_cam  : Camera3D = null
var _game_cam  : Camera3D = null
var _pivot     : Node3D   = null
var _menu_ctrl : Node     = null

var _is_tweening : bool    = false
var _current_tween: Tween  = null
var _rmb_down    : bool    = false
var _last_mouse  : Vector2 = Vector2.ZERO

var _game_cam_local_pos : Vector3
var _game_cam_local_rot : Vector3
## Store original projection so we can restore it after evaluation
var _game_cam_was_perspective: bool = true
var _game_cam_original_fov: float = 60.0

func _ready() -> void:
	_menu_cam = get_node_or_null(MENU_CAM_NAME)
	_game_cam = get_node_or_null(GAME_CAM_NAME)

	if _menu_cam == null:
		push_error("CameraController: нет дочерней ноды '%s'" % MENU_CAM_NAME)
		return
	if _game_cam == null:
		push_error("CameraController: нет дочерней ноды '%s'" % GAME_CAM_NAME)
		return

	# Запоминаем родную позицию GameCamera (TABLE_VIEW) — берём из сцены
	_game_cam_local_pos = _game_cam.position
	_game_cam_local_rot = _game_cam.rotation_degrees
	_game_cam_original_fov = _game_cam.fov

	_pivot = get_node_or_null("../AssemblyPivot")

	_menu_cam.current = true
	_game_cam.current = false
	GameState.set_camera_state("MENU_VIEW")

	# Ищем MenuController с задержкой (ui_layer добавляется в _ready Main.gd)
	call_deferred("_connect_menu_controller")

func _connect_menu_controller() -> void:
	var main := get_parent()
	if main == null:
		return
	_menu_ctrl = _find_by_signal(main, "game_started")
	if _menu_ctrl:
		if not _menu_ctrl.game_started.is_connected(_on_game_started):
			_menu_ctrl.game_started.connect(_on_game_started)
		if not _menu_ctrl.returned_to_menu.is_connected(_on_returned_to_menu):
			_menu_ctrl.returned_to_menu.connect(_on_returned_to_menu)
	else:
		push_warning("CameraController: MenuController не найден, повтор через 0.5с")
		await get_tree().create_timer(0.5).timeout
		_connect_menu_controller()

func _find_by_signal(root: Node, sig: String) -> Node:
	for child in root.get_children():
		if child.has_signal(sig):
			return child
		var found := _find_by_signal(child, sig)
		if found:
			return found
	return null

# ── Input ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if _is_tweening or not GameState.is_playing():
		return
	if GameState.camera_state != "TABLE_VIEW" or GameState.held_part != null:
		_rmb_down = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_rmb_down = event.pressed
		if event.pressed:
			_last_mouse = event.position
	elif event is InputEventMouseMotion and _rmb_down:
		pass # Orbit assembly disabled per user request

# ── game_started ─────────────────────────────────────────────────────────────
func _on_game_started() -> void:
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_is_tweening = true
	GameState.set_camera_state("TRANSITIONING")

	# GameCamera стартует с позиции MenuCamera
	# Если мы уже в GameCamera (перебили tween возврата), не сбрасываем позицию
	if not _game_cam.current:
		_game_cam.position         = _menu_cam.position
		_game_cam.rotation_degrees = _menu_cam.rotation_degrees
		_game_cam.current          = true
		_menu_cam.current          = false

	var tw := create_tween()
	_current_tween = tw
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(_game_cam, "position",         _game_cam_local_pos, gameplay_tween_duration)
	tw.tween_property(_game_cam, "rotation_degrees", _game_cam_local_rot, gameplay_tween_duration)
	tw.finished.connect(func() -> void:
		_is_tweening = false
		if GameState.is_playing():
			GameState.set_camera_state("TABLE_VIEW")
			if _menu_ctrl and _menu_ctrl.has_method("show_gameplay_hud"):
				_menu_ctrl.show_gameplay_hud()
	, CONNECT_ONE_SHOT)

# ── returned_to_menu ─────────────────────────────────────────────────────────
func _on_returned_to_menu() -> void:
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_is_tweening = true
	GameState.set_camera_state("TRANSITIONING")

	var tw := create_tween()
	_current_tween = tw
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(_game_cam, "position",         _menu_cam.position,         gameplay_tween_duration)
	tw.tween_property(_game_cam, "rotation_degrees", _menu_cam.rotation_degrees, gameplay_tween_duration)
	tw.finished.connect(func() -> void:
		_is_tweening = false
		_menu_cam.current          = true
		_game_cam.current          = false
		# Восстанавливаем родную позицию (для следующего старта)
		_game_cam.position         = _game_cam_local_pos
		_game_cam.rotation_degrees = _game_cam_local_rot
		if not GameState.is_playing():
			GameState.set_camera_state("MENU_VIEW")
	, CONNECT_ONE_SHOT)

# ── TABLE_VIEW / UNDER_TABLE_VIEW ────────────────────────────────────────────
func go_to_table_view() -> void:
	if GameState.camera_state == "TABLE_VIEW":
		return
	_tween_view("TABLE_VIEW")

func go_to_under_table_view() -> void:
	if GameState.camera_state == "UNDER_TABLE_VIEW":
		return
	_tween_view("UNDER_TABLE_VIEW")

func toggle_view() -> void:
	if GameState.camera_state == "TABLE_VIEW":
		go_to_under_table_view()
	else:
		go_to_table_view()

func _tween_view(new_state: String) -> void:
	if _game_cam == null or not GameState.is_playing():
		return
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_is_tweening = true
	GameState.set_camera_state(new_state)

	var tgt_pos : Vector3
	var tgt_rot : Vector3
	if new_state == "TABLE_VIEW":
		tgt_pos = _game_cam_local_pos
		tgt_rot = _game_cam_local_rot
	else:
		tgt_pos = under_table_position
		tgt_rot = under_table_rotation

	var tw := create_tween()
	_current_tween = tw
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_game_cam, "position",         tgt_pos, view_tween_duration)
	tw.tween_property(_game_cam, "rotation_degrees", tgt_rot, view_tween_duration)
	tw.finished.connect(func() -> void: _is_tweening = false, CONNECT_ONE_SHOT)


# ── Orthographic Evaluation View ─────────────────────────────────────────────

## Switches to an orthographic projection facing straight down at the workbench.
## Used by the silhouette evaluation system. Returns the Camera3D for raycasting.
func enter_eval_view() -> Camera3D:
	if _game_cam == null:
		return null
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	# Store the current projection state so we can restore later
	_game_cam_was_perspective = (_game_cam.projection == Camera3D.PROJECTION_PERSPECTIVE)

	# Switch to orthographic projection
	_game_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_game_cam.size = eval_ortho_size

	# Position camera looking straight down at the workbench center
	_game_cam.position = eval_ortho_position
	_game_cam.rotation_degrees = eval_ortho_rotation

	_game_cam.current = true
	GameState.set_camera_state("EVAL_VIEW")

	return _game_cam

## Restores the camera back to its previous perspective TABLE_VIEW state.
func exit_eval_view() -> void:
	if _game_cam == null:
		return

	# Restore perspective projection
	_game_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_game_cam.fov = _game_cam_original_fov

	# Tween back to table view
	_game_cam.position = _game_cam_local_pos
	_game_cam.rotation_degrees = _game_cam_local_rot
	GameState.set_camera_state("TABLE_VIEW")
