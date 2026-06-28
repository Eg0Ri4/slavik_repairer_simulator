## TapeTool.gd
## Manages 2-click procedural wobbly tape placement with ghost preview.
class_name TapeTool
extends Node3D

@export var ray_distance: float = 20.0

signal tape_started()
signal tape_finished()
signal tape_canceled()
signal tape_placement_blocked(reason: String)

var assembly_pivot: Node3D = null
var attachment_system: AttachmentSystem = null

var _is_placing: bool = false
var _start_body: Node3D = null
var _start_pos: Vector3 = Vector3.ZERO
var _start_normal: Vector3 = Vector3.UP
var _preview_mesh: MeshInstance3D = null

func _ready() -> void:
	# Build ghost preview mesh — visible during tape placement
	_preview_mesh = MeshInstance3D.new()
	var m = BoxMesh.new()
	m.size = Vector3(0.04, 0.005, 1.0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.75, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.surface_set_material(0, mat)
	_preview_mesh.mesh = m
	_preview_mesh.visible = false
	add_child(_preview_mesh)

func handle_click(mouse_pos: Vector2) -> bool:
	if GameState.active_tool != "tape":
		if _is_placing:
			cancel()
		return false

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false

	var origin := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)
	var space := get_world_3d().direct_space_state

	var hit = _raycast_for_surface(origin, direction, space)
	if hit:
		if not _is_placing:
			_start_tape(hit)
		else:
			_finish_tape(hit)
		return true
	else:
		if _is_placing:
			cancel()
			return true

	return false

func cancel() -> void:
	if _is_placing:
		_is_placing = false
		_start_body = null
		_preview_mesh.visible = false
		tape_canceled.emit()

## Update ghost preview every frame to track mouse raycast target (P2).
## The preview dynamically mirrors the rotation and scale to always
## point from P1 to the current mouse surface hit.
func _process(_delta: float) -> void:
	if GameState.active_tool != "tape" and _is_placing:
		cancel()

	# FIX 1: Guard against _start_body being freed mid-placement.
	# If the part gets deleted while we're placing tape, cancel cleanly.
	if _is_placing and not is_instance_valid(_start_body):
		cancel()
		return

	if _is_placing:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var mouse_pos = get_viewport().get_mouse_position()
			var origin = cam.project_ray_origin(mouse_pos)
			var direction = cam.project_ray_normal(mouse_pos)
			var space = get_world_3d().direct_space_state

			# FIX 2: Exclude the start body from the preview raycast so the
			# ray doesn't immediately re-hit the part we clicked on, which
			# caused the preview to snap to P1 instead of tracking the mouse.
			var hit = _raycast_for_surface(origin, direction, space, [_start_body])
			var end_pos = origin + direction * ray_distance
			if hit:
				end_pos = hit["position"]

			_update_preview(_start_pos, end_pos)

func _start_tape(hit: Dictionary) -> void:
	var collider = hit["collider"]
	if not (collider is JunkPart or collider is StaticBody3D):
		return

	_is_placing = true
	_start_body = collider
	_start_pos = hit["position"]
	_start_normal = hit["normal"]
	_preview_mesh.visible = true
	tape_started.emit()

func _finish_tape(hit: Dictionary) -> void:
	var end_body = hit["collider"]
	if not (end_body is JunkPart or end_body is StaticBody3D):
		cancel()
		return

	# FIX 3: Validate start body is still alive before finalizing.
	if not is_instance_valid(_start_body):
		cancel()
		return

	var end_pos = hit["position"]
	var end_normal = hit["normal"]

	if end_pos.distance_to(_start_pos) < 0.02:
		tape_placement_blocked.emit("Tape too short!")
		cancel()
		return

	# FIX 4: Don't allow taping a part to itself. Taping an object to
	# itself creates a degenerate joint that immediately breaks or causes
	# the physics body to jitter.
	if end_body == _start_body:
		tape_placement_blocked.emit("Cannot tape a part to itself!")
		cancel()
		return

	if attachment_system:
		attachment_system.create_manual_tape_joint(
			_start_body, _start_pos, _start_normal,
			end_body, end_pos, end_normal,
			assembly_pivot
		)

	_is_placing = false
	_start_body = null
	_preview_mesh.visible = false
	tape_finished.emit()

## Update preview mesh position, rotation, and scale to stretch from P1 to P2.
## Clamped so it never disappears or clips out of bounds.
func _update_preview(p1: Vector3, p2: Vector3) -> void:
	if not _preview_mesh: return
	_preview_mesh.visible = true
	var dist = p1.distance_to(p2)
	if dist < 0.001:
		dist = 0.001
		p2 = p1 + Vector3.FORWARD * dist
	_preview_mesh.scale = Vector3(1, 1, dist)
	_preview_mesh.global_position = (p1 + p2) * 0.5
	_preview_mesh.look_at(p2, Vector3.UP if abs((p2 - p1).normalized().y) < 0.99 else Vector3.RIGHT)

## Raycast against tape-eligible surfaces. Pass an exclusion list to skip
## specific bodies (e.g. the start body during preview so the ray doesn't
## re-hit the part we started on).
func _raycast_for_surface(origin: Vector3, direction: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array = []) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * ray_distance)
	query.collision_mask = 3  # table + placed parts
	query.collide_with_bodies = true
	query.collide_with_areas = false
	# FIX 5: Apply the exclusion list as RIDs so the physics engine skips
	# those bodies. Without this, the preview ray hits the start part's
	# collider every frame, making the tape appear to connect P1→P1.
	if exclude.size() > 0:
		var rids: Array[RID] = []
		for body in exclude:
			if is_instance_valid(body):
				rids.append(body.get_rid())
		query.exclude = rids
	var result := space.intersect_ray(query)
	if result:
		return result
	return null
