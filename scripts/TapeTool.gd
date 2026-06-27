## TapeTool.gd
## Manages 2-click procedural wobbly tape placement.
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
	_preview_mesh = MeshInstance3D.new()
	var m = BoxMesh.new()
	m.size = Vector3(0.04, 0.005, 1.0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.75, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.flags_unshaded = true
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

func _process(_delta: float) -> void:
	if GameState.active_tool != "tape" and _is_placing:
		cancel()
	
	if _is_placing and is_instance_valid(_start_body):
		var cam := get_viewport().get_camera_3d()
		if cam:
			var mouse_pos = get_viewport().get_mouse_position()
			var origin = cam.project_ray_origin(mouse_pos)
			var direction = cam.project_ray_normal(mouse_pos)
			var space = get_world_3d().direct_space_state
			var hit = _raycast_for_surface(origin, direction, space)
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
	
	var end_pos = hit["position"]
	var end_normal = hit["normal"]
	
	if end_pos.distance_to(_start_pos) < 0.02:
		tape_placement_blocked.emit("Tape too short!")
		cancel()
		return
		
	if attachment_system:
		attachment_system.create_manual_tape_joint(_start_body, _start_pos, _start_normal, end_body, end_pos, end_normal, assembly_pivot)
	
	_is_placing = false
	_start_body = null
	_preview_mesh.visible = false
	tape_finished.emit()

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

func _raycast_for_surface(origin: Vector3, direction: Vector3, space: PhysicsDirectSpaceState3D) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * ray_distance)
	query.collision_mask = 3  # table + placed parts
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result := space.intersect_ray(query)
	if result:
		return result
	return null
