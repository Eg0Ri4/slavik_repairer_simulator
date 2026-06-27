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

## Stores data for parts that have been physically merged into this one.
## Each entry is a Dictionary: {"tags": Array[String], "local_transform": Transform3D}
var merged_subparts: Array[Dictionary] = []

# The visual mesh child
var _mesh_node: Node3D = null

# ── Placement state ──────────────────────────────────────────────────────────
var _follow_plane_y: float = 0.07   # height of table surface in world space

# ── Scroll-height state ──────────────────────────────────────────────────────
## Accumulated height offset from scroll wheel (added to the Y-axis position).
var _height_offset: float = 0.0

## How much each scroll tick raises/lowers the object (meters).
const SCROLL_HEIGHT_STEP: float = 0.05
## Maximum height above the table surface.
const SCROLL_HEIGHT_MAX: float = 1.5

# ── Rotation state ───────────────────────────────────────────────────────────
## Mouse rotation sensitivity for RMB Skyrim-style inspect (radians per pixel).
const RMB_ROT_SPEED: float = 0.005

## Whether RMB is currently held for Skyrim-style item inspection rotation.
var _rmb_held: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	freeze = true
	collision_layer = 2
	collision_mask = 3   # table + parts (1 + 2 = 3)
	# Moderate damping — parts settle naturally without sticking
	linear_damp = 0.5
	angular_damp = 1.0

func _physics_process(_delta: float) -> void:
	if is_held:
		_follow_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if not is_held:
		return

	# ── Mouse button events ──────────────────────────────────────────────────
	if event is InputEventMouseButton:
		# RMB: Skyrim-style inspect rotation toggle
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_held = event.pressed
			if _rmb_held:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

		# Scroll wheel: raise/lower object along Y-axis
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_height_offset = clampf(_height_offset + SCROLL_HEIGHT_STEP, 0.0, SCROLL_HEIGHT_MAX)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_height_offset = clampf(_height_offset - SCROLL_HEIGHT_STEP, 0.0, SCROLL_HEIGHT_MAX)
			get_viewport().set_input_as_handled()
			return

	# ── RMB mouse motion: Skyrim-style object-centered rotation ──────────────
	if event is InputEventMouseMotion and _rmb_held:
		var motion := event as InputEventMouseMotion
		# rotate_object_local spins the part around its own center of mass
		# on its local axes, giving smooth infinite non-locking rotation
		rotate_object_local(Vector3.UP, -motion.relative.x * RMB_ROT_SPEED)
		rotate_object_local(Vector3.RIGHT, -motion.relative.y * RMB_ROT_SPEED)
		# Propagate rotation to cluster members
		_update_cluster_transforms()
		get_viewport().set_input_as_handled()
		return

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

	# Set mass based on approximate volume for realistic physics
	var vol: float = data.size.x * data.size.y * data.size.z
	mass = clampf(vol * 800.0, 0.2, 10.0)  # ~density of wood/plastic

## Called when spawning a brand-new part from a JunkBox.
## Resets rotation to identity so the part starts clean.
func pick_up() -> void:
	is_held = true
	is_placed = false
	# Reset orientation for fresh parts
	global_transform.basis = Basis.IDENTITY
	_height_offset = 0.0
	_rmb_held = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_enter_held_physics()

## Called when picking up an existing loose part already in the scene.
## Preserves the part's current orientation so it doesn't snap to a
## different angle the moment the player grabs it.
func pick_up_existing() -> void:
	_height_offset = 0.0

	# De-parent from AssemblyPivot (or wherever it lives) back to the scene root,
	# preserving world position so the object doesn't teleport.
	var scene_root := get_tree().root.get_node_or_null("Main")
	if scene_root and get_parent() != scene_root:
		reparent(scene_root, true)

	is_held = true
	is_placed = false
	_rmb_held = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_enter_held_physics()

## Configure physics state for a held (dragged) object.
## Disables ALL collisions so the part can be dragged smoothly through space
## without clipping/stuttering against other objects or the table.
## The object is frozen so physics forces don't affect it during the drag.
func _enter_held_physics() -> void:
	freeze = true
	collision_layer = 0   # invisible to all collision queries
	collision_mask  = 0   # doesn't collide with anything

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

	_exit_held_physics()
	GameState.register_assembly_part(self)

## Restore physics state when the object is placed/dropped.
## Re-enables collisions and UNFREEZES the body so Godot's rigid body
## physics takes over — the object will fall, impact, and settle naturally.
func _exit_held_physics() -> void:
	collision_layer = 2   # back on the parts layer
	collision_mask  = 3   # collide with table (1) + other parts (2)
	# Moderate damping for natural settling without sticking
	linear_damp = 0.8
	angular_damp = 1.5
	freeze = false        # let physics take over — gravity, impacts, settling

# ── Mouse-follow ─────────────────────────────────────────────────────────────
func _follow_mouse() -> void:
	# During RMB rotation, lock position — only orientation changes
	if _rmb_held:
		_update_cluster_transforms()
		return

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return

	# ── Determine table surface Y ─────────────────────────────────────────
	var table_y := _follow_plane_y
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node:
		var table_static = main_node.get_node_or_null("TableStaticBody")
		if table_static:
			var col_shape = table_static.get_node_or_null("CollisionShape3D")
			if col_shape and col_shape.shape is BoxShape3D:
				var shape_size = (col_shape.shape as BoxShape3D).size
				table_y = col_shape.global_position.y + (shape_size.y * 0.5 * col_shape.global_transform.basis.get_scale().y)

	# ── Project mouse ray onto the table plane for XZ positioning ───────
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

	var t: float = (table_y - origin.y) / direction.y
	var target: Vector3 = origin + direction * t

	# ── Apply scroll-wheel height offset on the Y-axis ───────────────────
	var half_h: float = _get_half_height()
	target.y = table_y + half_h + _height_offset

	# ── Clamp so the object bottom never goes below the table surface ───
	if target.y - half_h < table_y:
		target.y = table_y + half_h

	# ── Set position directly (collisions are off during drag phase) ─────
	global_position = target

	# ── Update all connected cluster members ─────────────────────────────
	_update_cluster_transforms()


## Returns the half-height of this part's bounding box for Y-axis clamping.
func _get_half_height() -> float:
	if item_data:
		return item_data.size.y * 0.5
	return 0.05


## Repositions all secondary cluster members using their stored relative
## offset transforms applied to this primary part's current global_transform.
## Collisions are off during drag, so direct transform assignment is safe.
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

# ── Monolithic Merging ───────────────────────────────────────────────────────
## Absorbs another JunkPart's logical tags and subparts into this one, relative
## to this part's current coordinate space.
func absorb_part(other: JunkPart) -> void:
	# Calculate other part's transform relative to this part
	var relative_transform: Transform3D = global_transform.affine_inverse() * other.global_transform
	
	# Add the other part's own primary tags (if any)
	if other.tags.size() > 0:
		merged_subparts.append({
			"tags": other.tags.duplicate(),
			"local_transform": relative_transform
		})
	
	# Absorb any subparts the other part had already absorbed
	for sub in other.merged_subparts:
		merged_subparts.append({
			"tags": sub["tags"].duplicate(),
			"local_transform": relative_transform * sub["local_transform"]
		})
