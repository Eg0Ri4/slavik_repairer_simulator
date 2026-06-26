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

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Freeze physics while held
	freeze = true
	collision_layer = 2
	collision_mask = 3   # table + parts (1 + 2 = 3)

func _physics_process(_delta: float) -> void:
	if is_held:
		_follow_mouse()

# ── Public API ───────────────────────────────────────────────────────────────
func setup(data: ItemData) -> void:
	item_data = data
	tags = data.tags.duplicate()

	# Build a simple CSG visual
	_mesh_node = _build_mesh(data)
	add_child(_mesh_node)

	# Collision shape matching shape_type
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

func pick_up() -> void:
	is_held = true
	is_placed = false
	freeze = true
	# Disable collisions while dragging so it doesn't block raycasts
	collision_layer = 0
	collision_mask = 0

func place_at(world_pos: Vector3, pivot: Node3D) -> void:
	is_held = false
	is_placed = true
	global_position = world_pos

	# Re-parent to the assembly pivot (reparent preserves global_transform)
	if get_parent() != pivot:
		reparent(pivot, true)

	# Restore physics but in frozen mode (joint will handle it)
	freeze = true
	collision_layer = 2
	collision_mask = 3   # table + parts (1 + 2 = 3)

	GameState.register_assembly_part(self)

# ── Mouse-follow ─────────────────────────────────────────────────────────────
func _follow_mouse() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return

	# Calculate current table surface height dynamically
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

	# Project using target table view camera transform if it exists, so the dragging
	# feels immediately and already on the table, without sliding around during transition.
	var saved_transform := camera.global_transform
	var using_target := false
	if main_node:
		var tv_target = main_node.get_node_or_null("TableViewTarget")
		if tv_target:
			# Target Camera3D transform is tv_target.global_transform * camera.transform
			var target_camera_global = tv_target.global_transform * camera.transform
			camera.global_transform = target_camera_global
			using_target = true

	# Project mouse onto the horizontal plane at follow_y
	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var direction: Vector3 = camera.project_ray_normal(mouse_pos)

	if using_target:
		camera.global_transform = saved_transform

	if abs(direction.y) < 0.001:
		return

	var t: float = (follow_y - origin.y) / direction.y
	var target: Vector3 = origin + direction * t
	# Small hover above surface
	target.y = follow_y + 0.05
	global_position = target

# ── Mesh builder (CSG-like using MeshInstance3D) ─────────────────────────────
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
