## JunkPart.gd
## A RigidBody3D that can carry ItemData tags, follow the cursor,
## be attached to the AssemblyPivot via joints, and be evaluated.
class_name JunkPart
extends RigidBody3D

# ── Data ─────────────────────────────────────────────────────────────────────
var item_data: ItemData = null
var tags: Array = []
var is_held: bool = false
var is_placed: bool = false

# The visual mesh child
var _mesh_node: Node3D = null

# ── Placement state ──────────────────────────────────────────────────────────
var _follow_plane_y: float = 0.07   # height of table surface in world space

# ── Rotation state ───────────────────────────────────────────────────────────
## Accumulated rotation stored as a Basis to avoid gimbal lock.
var _rotation_basis := Basis.IDENTITY

## Rotation step for keyboard inputs (radians).
const ROTATION_STEP: float = deg_to_rad(15.0)

## Mouse rotation sensitivity for Shift+drag (degrees per pixel).
const MOUSE_ROT_SENSITIVITY: float = 0.4

## Mouse rotation sensitivity for RMB Skyrim-style inspect (radians per pixel).
const RMB_ROT_SPEED: float = 0.005

## Whether the Shift key is currently held (for legacy Shift+drag mouse rotation mode).
var _shift_held: bool = false

## Whether RMB is currently held for Skyrim-style item inspection rotation.
var _rmb_held: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	freeze = true
	collision_layer = 2
	collision_mask = 3   # table + parts (1 + 2 = 3)

func _physics_process(_delta: float) -> void:
	if is_held:
		_follow_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if not is_held:
		return

	# ── RMB: Skyrim-style inspect rotation ───────────────────────────────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_held = event.pressed
			if _rmb_held:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _rmb_held:
		var motion := event as InputEventMouseMotion
		var yaw   := Basis(Vector3.UP,    -motion.relative.x * RMB_ROT_SPEED)
		var pitch := Basis(Vector3.RIGHT, -motion.relative.y * RMB_ROT_SPEED)
		_rotation_basis = yaw * _rotation_basis * pitch
		# Immediately propagate rotation to cluster members
		_update_cluster_transforms()
		get_viewport().set_input_as_handled()
		return

	# ── Shift key tracking ───────────────────────────────────────────────────
	if event is InputEventKey:
		if event.keycode == KEY_SHIFT:
			if event.pressed and not event.is_echo():
				_shift_held = true
			elif not event.pressed:
				_shift_held = false

		elif event.pressed and not event.is_echo():
			match event.keycode:
				KEY_Q:
					_rotation_basis = Basis(Vector3.UP, -ROTATION_STEP) * _rotation_basis
					_update_cluster_transforms()
					get_viewport().set_input_as_handled()
				KEY_E:
					_rotation_basis = Basis(Vector3.UP,  ROTATION_STEP) * _rotation_basis
					_update_cluster_transforms()
					get_viewport().set_input_as_handled()
				KEY_R:
					_rotation_basis = _rotation_basis * Basis(Vector3.RIGHT, -ROTATION_STEP)
					_update_cluster_transforms()
					get_viewport().set_input_as_handled()
				KEY_F:
					_rotation_basis = _rotation_basis * Basis(Vector3.RIGHT,  ROTATION_STEP)
					_update_cluster_transforms()
					get_viewport().set_input_as_handled()
				KEY_T:
					_rotation_basis = _rotation_basis * Basis(Vector3.FORWARD, -ROTATION_STEP)
					_update_cluster_transforms()
					get_viewport().set_input_as_handled()
				KEY_G:
					_rotation_basis = _rotation_basis * Basis(Vector3.FORWARD,  ROTATION_STEP)
					_update_cluster_transforms()
					get_viewport().set_input_as_handled()

	# ── Shift + mouse drag: free Y/X rotation ────────────────────────────────
	if event is InputEventMouseMotion and _shift_held and not _rmb_held:
		var motion := event as InputEventMouseMotion
		var yaw   := Basis(Vector3.UP,    deg_to_rad( motion.relative.x * MOUSE_ROT_SENSITIVITY))
		var pitch := Basis(Vector3.RIGHT, deg_to_rad( motion.relative.y * MOUSE_ROT_SENSITIVITY))
		_rotation_basis = yaw * _rotation_basis * pitch
		_update_cluster_transforms()
		get_viewport().set_input_as_handled()

# ── Public API ───────────────────────────────────────────────────────────────
func setup(data: ItemData) -> void:
	item_data = data
	tags = data.tags.duplicate()

	_mesh_node = _build_mesh(data)
	add_child(_mesh_node)

	var col: CollisionShape3D = CollisionShape3D.new()
	match data.shape_type:
		"cylinder":
			var cyl := CylinderShape3D.new()
			cyl.radius = data.size.x * 0.5
			cyl.height = data.size.y
			col.shape = cyl
		"sphere":
			var sph := SphereShape3D.new()
			sph.radius = data.size.x * 0.5
			col.shape = sph
		_:  # "box"
			var box := BoxShape3D.new()
			box.size = data.size
			col.shape = box
	add_child(col)

## Called when spawning a brand-new part from a JunkBox.
## Resets rotation to identity so the part starts clean.
func pick_up() -> void:
	is_held = true
	is_placed = false
	freeze = true
	_rotation_basis = Basis.IDENTITY
	_shift_held = false
	_rmb_held = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	collision_layer = 0
	collision_mask = 0

## Called when picking up an existing loose part already in the scene.
## Preserves the part's current orientation so it doesn't snap to a
## different angle the moment the player grabs it.
func pick_up_existing() -> void:
	# Capture current world rotation into _rotation_basis before any state change,
	# so _follow_mouse() will apply it unchanged on the first frame.
	_rotation_basis = global_transform.basis.orthonormalized()

	# De-parent from AssemblyPivot (or wherever it lives) back to the scene root,
	# preserving world position so the object doesn't teleport.
	var scene_root := get_tree().root.get_node_or_null("Main")
	if scene_root and get_parent() != scene_root:
		reparent(scene_root, true)

	is_held = true
	is_placed = false
	freeze = true
	_shift_held = false
	_rmb_held = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Disable collisions while dragging so raycasts pass through
	collision_layer = 0
	collision_mask = 0

func place_at(world_pos: Vector3, pivot: Node3D) -> void:
	is_held = false
	is_placed = true

	if _rmb_held:
		_rmb_held = false
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	global_position = world_pos

	if get_parent() != pivot:
		reparent(pivot, true)

	freeze = true
	collision_layer = 2
	collision_mask = 3

	GameState.register_assembly_part(self)

# ── Mouse-follow ─────────────────────────────────────────────────────────────
func _follow_mouse() -> void:
	if _rmb_held:
		transform.basis = _rotation_basis
		_update_cluster_transforms()
		return

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return

	var follow_y := _follow_plane_y
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node:
		var table_static = main_node.get_node_or_null("TableStaticBody")
		if table_static:
			var col_shape = table_static.get_node_or_null("CollisionShape3D")
			if col_shape and col_shape.shape is BoxShape3D:
				var shape_size = (col_shape.shape as BoxShape3D).size
				follow_y = col_shape.global_position.y + (shape_size.y * 0.5 * col_shape.global_transform.basis.get_scale().y)

	var mouse_pos: Vector2 = viewport.get_mouse_position()

	var saved_transform := camera.global_transform
	var using_target := false
	if main_node:
		var tv_target = main_node.get_node_or_null("TableViewTarget")
		if tv_target:
			var target_camera_global = tv_target.global_transform * camera.transform
			camera.global_transform = target_camera_global
			using_target = true

	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var direction: Vector3 = camera.project_ray_normal(mouse_pos)

	if using_target:
		camera.global_transform = saved_transform

	if abs(direction.y) < 0.001:
		return

	var t: float = (follow_y - origin.y) / direction.y
	var target: Vector3 = origin + direction * t
	target.y = follow_y + 0.05
	global_position = target

	transform.basis = _rotation_basis

	# ── Update all connected cluster members ─────────────────────────────
	_update_cluster_transforms()


## Repositions all secondary cluster members using their stored relative
## offset transforms applied to this primary part's current global_transform.
## This is called every frame in _follow_mouse() and also during RMB rotation
## so the cluster always moves and rotates as one rigid unit.
func _update_cluster_transforms() -> void:
	if GameState.held_cluster.is_empty():
		return

	var my_transform := global_transform
	for part: JunkPart in GameState.held_cluster:
		if not is_instance_valid(part):
			continue
		if part in GameState.cluster_offsets:
			var relative: Transform3D = GameState.cluster_offsets[part]
			part.global_transform = my_transform * relative

# ── Mesh builder ─────────────────────────────────────────────────────────────
func _build_mesh(data: ItemData) -> MeshInstance3D:
	var mi := MeshInstance3D.new()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.item_color
	mat.roughness = 0.7
	mat.metallic = 0.2

	match data.shape_type:
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = data.size.x * 0.5
			m.bottom_radius = data.size.x * 0.5
			m.height = data.size.y
			m.surface_set_material(0, mat)
			mi.mesh = m
		"sphere":
			var m := SphereMesh.new()
			m.radius = data.size.x * 0.5
			m.height = data.size.x
			m.surface_set_material(0, mat)
			mi.mesh = m
		_:
			var m := BoxMesh.new()
			m.size = data.size
			m.surface_set_material(0, mat)
			mi.mesh = m

	return mi
