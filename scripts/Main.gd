## Main.gd
## Root script for the "Trust Me, I'm an Engineer" 3D scene.
## Builds the entire scene tree in _ready() to avoid complex .tscn serialization.
extends Node3D

# ── Child node references (populated in _ready) ──────────────────────────────
var camera_controller: Node3D
var assembly_pivot: Node3D
var table: Node3D
var attachment_system: AttachmentSystem
var evaluation_system: EvaluationSystem
var nail_tool: NailTool
var tape_tool: TapeTool

# Under-table boxes
var boxes: Array[JunkBox] = []

# UI references
var ui_layer: CanvasLayer
var tool_tape_btn: Button
var tool_nail_btn: Button
var tool_crowbar_btn: Button
var tool_clear_btn: Button
var trust_me_btn: Button
var result_label: Label
var held_label: Label
var view_toggle_btn: Button
var order_desc_label: Label
var part_name_label: Label
var instructions_label: Label
var nail_status_label: Label

# Hover highlight state
var _hovered_box: JunkBox = null

# Active order
var _order: OrderData

var _table_y: float = 0.3

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	camera_controller = $CameraController
	assembly_pivot = $AssemblyPivot
	table = get_node_or_null("GarageAndTable")
	boxes = [$BoxA, $BoxB, $BoxC]

	var table_static = get_node_or_null("TableStaticBody")
	if table_static:
		var col_shape = table_static.get_node_or_null("CollisionShape3D")
		if col_shape and col_shape.shape is BoxShape3D:
			var shape_size = (col_shape.shape as BoxShape3D).size
			_table_y = col_shape.global_position.y + (shape_size.y * 0.5 * col_shape.global_transform.basis.get_scale().y)
			if assembly_pivot:
				assembly_pivot.global_position.y = _table_y

	_build_systems()
	_build_ui()
	_setup_order()

	GameState.camera_state_changed.connect(_on_camera_state_changed)
	GameState.part_picked_up.connect(_on_part_picked_up)
	GameState.part_placed.connect(_on_part_placed)

func _build_systems() -> void:
	attachment_system = AttachmentSystem.new()
	attachment_system.name = "AttachmentSystem"
	add_child(attachment_system)

	evaluation_system = EvaluationSystem.new()
	evaluation_system.name = "EvaluationSystem"
	add_child(evaluation_system)

	nail_tool = NailTool.new()
	nail_tool.name = "NailTool"
	nail_tool.assembly_pivot = assembly_pivot
	add_child(nail_tool)

	nail_tool.nail_placed.connect(_on_nail_placed)
	nail_tool.nail_strike_performed.connect(_on_nail_strike)
	nail_tool.nail_fully_driven.connect(_on_nail_driven)
	nail_tool.nail_placement_blocked.connect(_on_nail_placement_blocked)

	tape_tool = TapeTool.new()
	tape_tool.name = "TapeTool"
	tape_tool.assembly_pivot = assembly_pivot
	tape_tool.attachment_system = attachment_system
	add_child(tape_tool)
	
	tape_tool.tape_started.connect(_on_tape_started)
	tape_tool.tape_finished.connect(_on_tape_finished)
	tape_tool.tape_canceled.connect(_on_tape_canceled)
	tape_tool.tape_placement_blocked.connect(_on_tape_placement_blocked)

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	# ── Order Panel ───────────────────────────────────────────────────────────
	var panel := _make_panel(Vector2(10, 10), Vector2(320, 215))
	ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "OrderVBox"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var order_title := Label.new()
	order_title.name = "OrderTitle"
	order_title.text = "📋 REPAIR ORDER"
	order_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(order_title)

	order_desc_label = Label.new()
	order_desc_label.name = "OrderDesc"
	order_desc_label.text = "Loading order..."
	order_desc_label.add_theme_font_size_override("font_size", 13)
	order_desc_label.custom_minimum_size = Vector2(295, 60)
	order_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(order_desc_label)

	part_name_label = Label.new()
	part_name_label.name = "PartName"
	part_name_label.text = "Holding: nothing"
	part_name_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	part_name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(part_name_label)

	instructions_label = Label.new()
	instructions_label.name = "Instructions"
	instructions_label.text = "Hold RMB: inspect-rotate part (Skyrim)\nNo part + RMB drag: orbit assembly\nLMB part on table: pick it back up\nClick box: grab part  ·  LMB: place\nQ/E: yaw  R/F: pitch  T/G: roll\nShift+drag: free-rotate held part"
	instructions_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	instructions_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(instructions_label)

	# ── Tool selector ─────────────────────────────────────────────────────────
	var tool_panel := _make_panel(Vector2(10, 235), Vector2(320, 115))
	ui_layer.add_child(tool_panel)

	var tool_vbox := VBoxContainer.new()
	tool_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tool_vbox.add_theme_constant_override("separation", 6)
	tool_panel.add_child(tool_vbox)

	var tool_title := Label.new()
	tool_title.text = "🔧 ATTACHMENT TOOL"
	tool_title.add_theme_font_size_override("font_size", 14)
	tool_vbox.add_child(tool_title)

	var tool_hbox := HBoxContainer.new()
	tool_hbox.add_theme_constant_override("separation", 8)
	tool_vbox.add_child(tool_hbox)

	tool_tape_btn = _make_button("📎 TAPE (Wobbly)", Vector2.ZERO, Vector2(140, 32))
	tool_tape_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_tape_btn.pressed.connect(_on_tape_pressed)
	tool_hbox.add_child(tool_tape_btn)

	tool_nail_btn = _make_button("🔨 NAIL", Vector2.ZERO, Vector2(90, 32))
	tool_nail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_nail_btn.pressed.connect(_on_nail_pressed)
	tool_hbox.add_child(tool_nail_btn)

	tool_crowbar_btn = _make_button("🪝 CROWBAR", Vector2.ZERO, Vector2(100, 32))
	tool_crowbar_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_crowbar_btn.pressed.connect(_on_crowbar_pressed)
	tool_hbox.add_child(tool_crowbar_btn)

	tool_clear_btn = _make_button("❌ CLEAR", Vector2.ZERO, Vector2(80, 32))
	tool_clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_clear_btn.pressed.connect(_on_clear_pressed)
	tool_hbox.add_child(tool_clear_btn)

	nail_status_label = Label.new()
	nail_status_label.name = "NailStatus"
	nail_status_label.text = ""
	nail_status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	nail_status_label.add_theme_font_size_override("font_size", 12)
	tool_vbox.add_child(nail_status_label)

	_update_tool_buttons()

	# ── View toggle ───────────────────────────────────────────────────────────
	view_toggle_btn = _make_button("🔽 LOOK UNDER TABLE (Tab)", Vector2(10, 330), Vector2(320, 40))
	view_toggle_btn.pressed.connect(_on_view_toggle_pressed)
	ui_layer.add_child(view_toggle_btn)

	# ── TRUST ME button ───────────────────────────────────────────────────────
	trust_me_btn = _make_button("⚡ TRUST ME, I'M AN ENGINEER ⚡", Vector2(10, 380), Vector2(320, 50))
	trust_me_btn.add_theme_font_size_override("font_size", 15)
	trust_me_btn.add_theme_color_override("font_color", Color(1, 1, 0))
	trust_me_btn.pressed.connect(_on_trust_me_pressed)
	ui_layer.add_child(trust_me_btn)

	# ── Result display ────────────────────────────────────────────────────────
	var result_panel := _make_panel(Vector2(10, 440), Vector2(320, 135))
	result_panel.name = "ResultPanel"
	ui_layer.add_child(result_panel)

	var result_vbox := VBoxContainer.new()
	result_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(result_vbox)

	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.text = "Press 'TRUST ME' to evaluate your repair!"
	result_label.add_theme_font_size_override("font_size", 13)
	result_label.custom_minimum_size = Vector2(300, 110)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_vbox.add_child(result_label)

	# ── Reset button ──────────────────────────────────────────────────────────
	var reset_btn := _make_button("🗑 CLEAR ASSEMBLY", Vector2(10, 585), Vector2(320, 36))
	reset_btn.pressed.connect(_on_reset_pressed)
	ui_layer.add_child(reset_btn)

# ── Order setup ──────────────────────────────────────────────────────────────
func _setup_order() -> void:
	_order = OrderData.new()
	_order.order_name = "Broken Workshop Fan"
	_order.description = "The workshop fan stopped working! Needs:\n• A BLADE near the top\n• A MOTOR in the center\n• A FRAME at the base"
	_order.requirements = [
		{"required_tag": "blade",  "target_position": Vector3(0.0,  0.30, 0.0), "points": 100},
		{"required_tag": "motor",  "target_position": Vector3(0.0,  0.00, 0.0), "points": 150},
		{"required_tag": "frame",  "target_position": Vector3(0.0, -0.20, 0.0), "points": 80},
	]
	_order.tolerance = 0.5
	GameState.current_order = _order

	if order_desc_label:
		order_desc_label.text = _order.description

# ── Input handling ────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_TAB:
			_on_view_toggle_pressed()
		elif event.keycode == KEY_ESCAPE:
			GameState.set_active_tool("none")
			_update_tool_buttons()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(event.position)

func _handle_left_click(mouse_pos: Vector2) -> void:
	match GameState.camera_state:
		"UNDER_TABLE_VIEW":
			var box := _raycast_for_box(mouse_pos)
			if box:
				_extract_from_box(box)

		"TABLE_VIEW":
			if GameState.held_part != null:
				# Already holding something — place it
				_place_held_part(mouse_pos)
			else:
				# ── Priority 1: nail tool intercept ──────────────────────────
				if (GameState.active_tool == "nail" or GameState.active_tool == "crowbar") and nail_tool.handle_click(mouse_pos):
					return
					
				# ── Priority 1.5: tape tool intercept ────────────────────────
				if GameState.active_tool == "tape" and tape_tool.handle_click(mouse_pos):
					return

				# ── Priority 2: pick up an existing loose JunkPart ───────────
				var existing := _raycast_for_part(mouse_pos)
				if existing:
					_pick_up_existing_part(existing)
					return

				# ── Priority 3: grab a new part from a JunkBox ───────────────
				var box := _raycast_for_box(mouse_pos)
				if box:
					_extract_from_box(box)

# ── Raycast helpers ───────────────────────────────────────────────────────────

## Raycast against placed/loose JunkParts (collision layer 2).
## Returns the JunkPart if it is not already held. Jointed parts are
## allowed — the compound movement system will pick up the whole cluster.
func _raycast_for_part(mouse_pos: Vector2) -> JunkPart:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null

	var origin    := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 2   # layer 2 = JunkPart objects
	var result := space.intersect_ray(query)

	if not result:
		return null

	var collider = result.collider
	if not (collider is JunkPart):
		return null

	var part := collider as JunkPart

	# Don't re-grab something already in the air
	if part.is_held:
		return null

	return part

func _raycast_for_box(mouse_pos: Vector2) -> JunkBox:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null

	var origin    := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 4   # box layer
	var result := space.intersect_ray(query)

	if result and result.collider is JunkBox:
		return result.collider as JunkBox
	return null

# ── Pick-up helpers ───────────────────────────────────────────────────────────

## Pick up a JunkPart that is already sitting in the scene (placed or loose).
## Discovers all transitively connected parts via joints (the "cluster") and
## picks them all up together for compound movement.
func _pick_up_existing_part(part: JunkPart) -> void:
	# ── Step 1: Discover the full connected cluster ─────────────────────
	var cluster: Array[JunkPart] = attachment_system.get_connected_cluster(part, assembly_pivot)

	# ── Check if any part in the cluster is attached to the base ────────
	if _is_cluster_attached_to_base(cluster):
		if part_name_label:
			part_name_label.text = "Cannot pick up: Attached to base"
		return

	# Build secondary list (everything except the primary clicked part)
	var secondary: Array[JunkPart] = []
	for p: JunkPart in cluster:
		if p != part:
			secondary.append(p)

	# ── Step 2: Discover joints connecting cluster members ──────────────
	var joints: Array[Joint3D] = attachment_system.get_joints_in_cluster(cluster, assembly_pivot)

	# Disable cluster joints so they don't fight our manual positioning.
	# We disable them rather than removing them so we can re-enable on drop.
	for joint: Joint3D in joints:
		joint.set("node_a", NodePath(""))
		joint.set("node_b", NodePath(""))

	# ── Step 3: Remove all cluster parts from assembly registry ─────────
	for p: JunkPart in cluster:
		GameState.assembly_parts.erase(p)

	# ── Step 4: Prepare secondary parts for compound movement ───────────
	for p: JunkPart in secondary:
		# Capture world transform before any reparenting
		var world_xform := p.global_transform

		# Reparent to scene root if needed (like pick_up_existing does for primary)
		if p.get_parent() != self:
			p.reparent(self, true)

		# Disable collisions and freeze — ghost mode during drag
		p.freeze = true
		p.collision_layer = 0
		p.collision_mask  = 0
		p.is_held = false  # only primary is "held" — secondary are passengers
		p.is_placed = false

		# Restore world transform (reparenting should preserve it, but be safe)
		p.global_transform = world_xform

	# ── Step 5: Also reparent nails that belong to cluster parts ────────
	var cluster_set: Dictionary = {}
	for p: JunkPart in cluster:
		cluster_set[p] = true
	for child in assembly_pivot.get_children():
		if child is Nail:
			var nail := child as Nail
			if nail._surface_body in cluster_set or nail._top_body in cluster_set:
				nail.reparent(self, true)

	# ── Step 6: Pick up the primary part ────────────────────────────────
	part.pick_up_existing()

	# ── Step 7: Register cluster state in GameState ─────────────────────
	GameState.pick_up_cluster(part, secondary, joints)
	GameState.pick_up_part(part)

func _is_cluster_attached_to_base(cluster: Array[JunkPart]) -> bool:
	var cluster_rids := {}
	for p in cluster:
		cluster_rids[p.get_rid()] = true
		
	for child in assembly_pivot.get_children():
		if child is Joint3D:
			var joint := child as Joint3D
			var body_a = joint.get_node_or_null(joint.node_a) if joint.node_a else null
			var body_b = joint.get_node_or_null(joint.node_b) if joint.node_b else null
			
			var a_in_cluster = body_a is JunkPart and body_a.get_rid() in cluster_rids
			var b_in_cluster = body_b is JunkPart and body_b.get_rid() in cluster_rids
			var a_is_static = body_a is StaticBody3D
			var b_is_static = body_b is StaticBody3D
			
			if (a_in_cluster and b_is_static) or (b_in_cluster and a_is_static):
				return true
	return false

func _extract_from_box(box: JunkBox) -> void:
	var item_data := box.extract_random_part()
	if item_data == null:
		return

	var part := JunkPart.new()
	part.setup(item_data)
	add_child(part)
	var spawn_pos := box.global_position
	spawn_pos.y = _table_y + 0.05
	part.global_position = spawn_pos
	part.pick_up()
	GameState.pick_up_part(part)

	var cc := get_node_or_null("CameraController") as Node3D
	if cc and cc.has_method("go_to_table_view"):
		cc.go_to_table_view()

func _place_held_part(mouse_pos: Vector2) -> void:
	var part := GameState.held_part
	if part == null:
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var saved_transform := cam.global_transform
	var using_target := false
	var tv_target = get_node_or_null("TableViewTarget")
	if tv_target:
		var target_camera_global = tv_target.global_transform * cam.transform
		cam.global_transform = target_camera_global
		using_target = true

	var origin    := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)

	if using_target:
		cam.global_transform = saved_transform

	var table_y := _table_y
	var drop_pos := Vector3.ZERO
	var hit_y    := table_y

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 3   # table (1) + placed parts (2)
	var result := space.intersect_ray(query)

	if result:
		drop_pos = result.position
		hit_y    = result.position.y
	else:
		if abs(direction.y) > 0.001:
			var t := (table_y - origin.y) / direction.y
			if t > 0:
				drop_pos = origin + direction * t
		hit_y = table_y

	drop_pos.y = hit_y + (part.item_data.size.y * 0.5 if part.item_data else 0.1)

	# ── Place the primary part ───────────────────────────────────────────
	part.place_at(drop_pos, assembly_pivot)

	# ── Place all secondary cluster parts ────────────────────────────────
	var secondary := GameState.held_cluster.duplicate()
	var cluster_joints := GameState.cluster_joints.duplicate()

	for p: JunkPart in secondary:
		if not is_instance_valid(p):
			continue
		# Capture current world transform (set by _update_cluster_transforms)
		var world_xform := p.global_transform

		# Reparent to assembly_pivot
		if p.get_parent() != assembly_pivot:
			p.reparent(assembly_pivot, true)

		# Restore placement state with full physics re-enable
		p.global_transform = world_xform
		p.is_held = false
		p.is_placed = true
		p.collision_layer = 2
		p.collision_mask = 3
		p.freeze = false   # let physics take over — settle naturally

		GameState.register_assembly_part(p)

	# ── Reparent nails back to assembly_pivot ────────────────────────────
	for child in get_children():
		if child is Nail:
			child.reparent(assembly_pivot, true)

	# ── Re-enable cluster joints with corrected node paths ──────────────
	for joint: Joint3D in cluster_joints:
		if not is_instance_valid(joint):
			continue
		# Reparent joint to assembly_pivot if needed
		if joint.get_parent() != assembly_pivot:
			joint.reparent(assembly_pivot, true)
		# We need to find which bodies this joint originally connected.
		# The joint was created by Nail._create_joint() or AttachmentSystem.
		# We stored references are gone (paths were cleared), but the joint's
		# position is at the midpoint of the two bodies it connects.
		# We'll find the two nearest cluster parts to the joint's position.
		var j_pos := joint.global_position
		var all_cluster: Array[JunkPart] = [part as JunkPart]
		all_cluster.append_array(secondary)
		var sorted_by_dist: Array[JunkPart] = []
		sorted_by_dist.append_array(all_cluster)
		sorted_by_dist.sort_custom(func(a: JunkPart, b: JunkPart) -> bool:
			return a.global_position.distance_to(j_pos) < b.global_position.distance_to(j_pos)
		)
		if sorted_by_dist.size() >= 2:
			# Use call_deferred for node path assignment so physics settles first
			_deferred_assign_joint_paths(joint, sorted_by_dist[0], sorted_by_dist[1])

	# ── Clean up cluster state ───────────────────────────────────────────
	GameState.drop_cluster()

	# ── Attach primary if other parts exist (for solo parts without cluster) ──
	_attach_part(part)
	GameState.place_part()


## Deferred joint path assignment — ensures nodes are settled in the tree
## before we call get_path_to, preventing "!is_inside_tree()" errors.
func _deferred_assign_joint_paths(joint: Joint3D, body_a: Node3D, body_b: Node3D) -> void:
	if not is_instance_valid(joint):
		return
	if not is_instance_valid(body_a) or not is_instance_valid(body_b):
		return
	_do_assign_joint_paths.call_deferred(joint, body_a, body_b)

func _do_assign_joint_paths(joint: Joint3D, body_a: Node3D, body_b: Node3D) -> void:
	if is_instance_valid(joint) and is_instance_valid(body_a) and is_instance_valid(body_b):
		if joint.is_inside_tree() and body_a.is_inside_tree() and body_b.is_inside_tree():
			joint.node_a = joint.get_path_to(body_a)
			joint.node_b = joint.get_path_to(body_b)


func _attach_part(part: JunkPart) -> void:
	if GameState.active_tool == "none" or GameState.active_tool == "tape" or GameState.active_tool == "nail" or GameState.active_tool == "crowbar":
		return

	var placed_count: int = 0
	for child in assembly_pivot.get_children():
		if child is JunkPart and child != part and child.is_placed:
			placed_count += 1

	if placed_count == 0:
		return

	attachment_system.attach(part, assembly_pivot)

# ── Mouse hover for boxes ─────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if GameState.camera_state == "UNDER_TABLE_VIEW":
		_update_box_hover()

func _update_box_hover() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var new_hovered := _raycast_for_box(mouse_pos)

	if new_hovered != _hovered_box:
		if _hovered_box:
			_hovered_box.highlight(false)
		if new_hovered:
			new_hovered.highlight(true)
		_hovered_box = new_hovered

# ── UI callbacks ──────────────────────────────────────────────────────────────
func _on_view_toggle_pressed() -> void:
	if GameState.held_part != null:
		return

	var cc := get_node_or_null("CameraController")
	if cc and cc.has_method("toggle_view"):
		cc.toggle_view()

func _on_tape_pressed() -> void:
	GameState.set_active_tool("none" if GameState.active_tool == "tape" else "tape")
	_update_tool_buttons()

func _on_nail_pressed() -> void:
	GameState.set_active_tool("none" if GameState.active_tool == "nail" else "nail")
	_update_tool_buttons()

func _on_crowbar_pressed() -> void:
	GameState.set_active_tool("none" if GameState.active_tool == "crowbar" else "crowbar")
	_update_tool_buttons()

func _on_clear_pressed() -> void:
	GameState.set_active_tool("none")
	_update_tool_buttons()

func _update_tool_buttons() -> void:
	if tool_tape_btn == null or tool_nail_btn == null or tool_crowbar_btn == null or tool_clear_btn == null:
		return
	var active        := GameState.active_tool
	var active_color  := Color(1.0, 0.9, 0.3)
	var inactive_color := Color(0.75, 0.75, 0.75)
	tool_tape_btn.modulate = active_color if active == "tape" else inactive_color
	tool_nail_btn.modulate = active_color if active == "nail" else inactive_color
	tool_crowbar_btn.modulate = active_color if active == "crowbar" else inactive_color
	tool_clear_btn.modulate = active_color if active == "none" else inactive_color

	if nail_status_label:
		if active == "nail":
			nail_status_label.text = "Click on a part to place nail, then click nail to hammer"
		elif active == "crowbar":
			nail_status_label.text = "Click on a nail to pull it out"
		else:
			nail_status_label.text = ""

func _on_trust_me_pressed() -> void:
	if _order == null or result_label == null:
		return

	var placed_count: int = 0
	for child in assembly_pivot.get_children():
		if child is JunkPart:
			placed_count += 1

	if placed_count == 0:
		result_label.text = "❌ Nothing is attached yet!\nGrab some junk from the boxes!"
		return

	var eval_result := evaluation_system.evaluate(assembly_pivot, _order)
	var pct: int    = eval_result["percentage"]
	var grade: String = evaluation_system.grade_label(pct)
	var score: int  = eval_result["total_score"]
	var max_s: int  = eval_result["max_score"]

	var detail: String = ""
	for req in eval_result["requirements"]:
		var tag: String    = req["tag"]
		var earned: int    = req["points_earned"]
		var possible: int  = req["points_possible"]
		var found: bool    = req["found"]
		var icon: String   = "✅" if earned == possible else ("⚠️" if earned > 0 else "❌")
		if not found:
			detail += "%s [%s]: Not found (0/%d pts)\n" % [icon, tag, possible]
		else:
			var dist: float = req["distance"]
			detail += "%s [%s]: %.2fm away (%d/%d pts)\n" % [icon, tag, dist, earned, possible]

	result_label.text = "━━━ EVALUATION ━━━\n%s\nScore: %d / %d (%d%%)\n\n%s" % [
		grade, score, max_s, pct, detail
	]

func _on_reset_pressed() -> void:
	# Free any cluster members currently held (reparented under Main)
	for part: JunkPart in GameState.held_cluster:
		if is_instance_valid(part):
			part.queue_free()
	for joint: Joint3D in GameState.cluster_joints:
		if is_instance_valid(joint):
			joint.queue_free()
	GameState.drop_cluster()

	for child in assembly_pivot.get_children():
		if child is JunkPart or child is Joint3D or child is Nail:
			child.queue_free()

	# Also free nails/parts reparented under Main during pick-up
	for child in get_children():
		if child is Nail:
			child.queue_free()

	if GameState.held_part:
		GameState.held_part.queue_free()
		GameState.place_part()

	GameState.clear_assembly()

	if result_label:
		result_label.text = "Assembly cleared. Grab some parts from the boxes!"
	if part_name_label:
		part_name_label.text = "Holding: nothing"

# ── Nail tool signal handlers ─────────────────────────────────────────────────
func _on_nail_placed(nail: Nail) -> void:
	if nail_status_label:
		nail_status_label.text = "🔨 Nail placed! Click it to hammer in (%d%%)" % int(nail.get_progress() * 100)

func _on_nail_strike(progress: float) -> void:
	if nail_status_label:
		var pct := int(progress * 100)
		if GameState.active_tool == "crowbar":
			if pct <= 0:
				nail_status_label.text = "🪝 Nail removed!"
			else:
				nail_status_label.text = "🪝 Pulling out... %d%%" % pct
		else:
			if pct >= 100:
				nail_status_label.text = "✅ Nail fully driven! Objects fastened."
			else:
				nail_status_label.text = "🔨 Hammering... %d%%" % pct

func _on_nail_driven(_nail: Nail) -> void:
	if nail_status_label:
		nail_status_label.text = "✅ Nail fastened! Place another or switch tools."

func _on_nail_placement_blocked(reason: String) -> void:
	if nail_status_label:
		nail_status_label.text = "⚠️ %s" % reason

# ── Tape tool signal handlers ─────────────────────────────────────────────────
func _on_tape_started() -> void:
	if nail_status_label:
		nail_status_label.text = "📍 Tape start set! Click the end point."

func _on_tape_finished() -> void:
	if nail_status_label:
		nail_status_label.text = "✅ Taped! Place another or switch tools."

func _on_tape_canceled() -> void:
	if nail_status_label:
		nail_status_label.text = "❌ Tape canceled."
		
func _on_tape_placement_blocked(reason: String) -> void:
	if nail_status_label:
		nail_status_label.text = "⚠️ %s" % reason

# ── GameState signal handlers ─────────────────────────────────────────────────
func _on_camera_state_changed(new_state: String) -> void:
	if view_toggle_btn == null:
		return
	if new_state == "TABLE_VIEW":
		view_toggle_btn.text = "🔽 LOOK UNDER TABLE (Tab)"
	else:
		view_toggle_btn.text = "🔼 BACK TO TABLE (Tab)"

func _on_part_picked_up(part: RigidBody3D) -> void:
	if part_name_label and part is JunkPart:
		var jp := part as JunkPart
		part_name_label.text = "Holding: %s [%s]" % [
			jp.item_data.item_name if jp.item_data else "???",
			", ".join(jp.tags)
		]

func _on_part_placed() -> void:
	if part_name_label:
		part_name_label.text = "Holding: nothing"

# ── UI Helpers ────────────────────────────────────────────────────────────────
func _make_panel(pos: Vector2, sz: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.custom_minimum_size = sz
	panel.size = sz

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.88)
	style.border_color = Color(0.4, 0.35, 0.2, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	return panel

func _make_button(txt: String, pos: Vector2, sz: Vector2) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.custom_minimum_size = sz
	btn.size = sz

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.22, 0.18, 0.12, 0.95)
	style_normal.border_color = Color(0.55, 0.45, 0.25)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.35, 0.28, 0.16, 0.95)
	style_hover.border_color = Color(0.8, 0.7, 0.3)
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.18, 0.15, 0.10, 0.95)
	style_pressed.border_color = Color(1.0, 0.9, 0.2)
	style_pressed.set_border_width_all(2)
	style_pressed.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	return btn
