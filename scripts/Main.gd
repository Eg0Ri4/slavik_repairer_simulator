## Main.gd
## Root script for the "Trust Me, I'm an Engineer" 3D scene.
## Builds the entire scene tree in _ready() to avoid complex .tscn serialization.
## Orchestrates UI initialization, raycasting, tools, and evaluation states.
extends Node3D

# ── Child node references (populated in _ready) ──────────────────────────────
var camera_controller: Node3D
var assembly_pivot: Node3D
var table: Node3D
var attachment_system: AttachmentSystem
var evaluation_system: EvaluationSystem
var blueprint_evaluator
var nail_tool: NailTool
var tape_tool: TapeTool

# Ghost blueprint for 3D overlap evaluation
var ghost_root: Node3D = null

# Under-table boxes
var boxes: Array[JunkBox] = []

# UI references
var ui_layer: CanvasLayer
var _hud_root: Control
var tool_tape_btn: Button
var tool_nail_btn: Button
var tool_crowbar_btn: Button
var tool_clear_btn: Button
var trust_me_btn: Button

var finish_btn: Button
var result_label: Label
var held_label: Label
var order_desc_label: Label
var order_title_label: Label
var part_name_label: Label
var instructions_label: Label
var nail_status_label: Label

# Silhouette overlay (shown during evaluation)
var _silhouette_overlay: TextureRect = null
var _eval_back_btn: Button = null

# Hover highlight state
var _hovered_box: JunkBox = null

# Active order
var _order: OrderData

var _table_y: float = 0.3

# Ghost rotation state
var _ghost_rmb_held: bool = false
const GHOST_ROT_SPEED: float = 0.005

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
	_setup_new_hud()

	GameState.camera_state_changed.connect(_on_camera_state_changed)
	GameState.part_picked_up.connect(_on_part_picked_up)
	GameState.part_placed.connect(_on_part_placed)
	GameState.phase_changed.connect(_on_phase_changed)
	
	_hud_root.visible = false

	
	GameState.set_phase(GameState.GamePhase.PLAYING)
	if _new_hud:
		_new_hud.visible = true

var _new_hud: HUDController = null
func _setup_new_hud() -> void:
	var hud_scene = preload("res://scenes/HUD.tscn")
	_new_hud = hud_scene.instantiate() as HUDController
	_new_hud.visible = false
	add_child(_new_hud)
	
	# Hijack the old UI text references so they write to the new HUD
	result_label = _new_hud.score_label
	part_name_label = _new_hud.holding_label
	
	_new_hud.submit_pressed.connect(_on_trust_me_pressed)
	_new_hud.clear_pressed.connect(_on_reset_pressed)
	_new_hud.skip_pressed.connect(_on_skip_pressed)
	
	# The new HUD handles its own Pause Menu directly now!
	
	_new_hud.tool_changed.connect(func(tool_state):
		match tool_state:
			HUDController.ToolState.HAND: GameState.set_active_tool("none")
			HUDController.ToolState.TAPE: GameState.set_active_tool("tape")
			HUDController.ToolState.NAIL: GameState.set_active_tool("nail")
			HUDController.ToolState.CROWBAR: GameState.set_active_tool("crowbar")
	)

func _on_phase_changed(phase: GameState.GamePhase) -> void:
	pass

func _build_systems() -> void:
	attachment_system = AttachmentSystem.new()
	attachment_system.name = "AttachmentSystem"
	add_child(attachment_system)

	evaluation_system = EvaluationSystem.new()
	evaluation_system.name = "EvaluationSystem"
	add_child(evaluation_system)

	var evaluator_script = load("res://scripts/BlueprintEvaluator.gd")
	blueprint_evaluator = evaluator_script.new()
	blueprint_evaluator.name = "BlueprintEvaluator"
	blueprint_evaluator.samples_per_axis = 5
	blueprint_evaluator.coverage_threshold = 0.4
	add_child(blueprint_evaluator)

	nail_tool = NailTool.new()
	nail_tool.name = "NailTool"
	nail_tool.assembly_pivot = assembly_pivot
	add_child(nail_tool)

	nail_tool.nail_placed.connect(_on_nail_placed)
	nail_tool.nail_strike_performed.connect(_on_nail_strike)
	nail_tool.nail_fully_driven.connect(_on_nail_driven)
	nail_tool.nail_placement_blocked.connect(_on_nail_placement_blocked)
	nail_tool.tape_removed.connect(_on_tape_removed)

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
	
	_hud_root = Control.new()
	_hud_root.name = "HudRoot"
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_hud_root)

	# ── Order Panel ───────────────────────────────────────────────────────────
	var panel := _make_panel(Vector2(10, 10), Vector2(320, 215))
	_hud_root.add_child(panel)

	order_title_label = Label.new()
	order_title_label.name = "OrderTitle"
	order_title_label.text = "📋 REPAIR ORDER"
	order_title_label.add_theme_font_size_override("font_size", 16)
	order_title_label.position = Vector2(10, 10)
	panel.add_child(order_title_label)

	order_desc_label = Label.new()
	order_desc_label.name = "OrderDesc"
	order_desc_label.text = "Loading order..."
	order_desc_label.add_theme_font_size_override("font_size", 13)
	order_desc_label.custom_minimum_size = Vector2(300, 60)
	order_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_desc_label.position = Vector2(10, 35)
	panel.add_child(order_desc_label)

	part_name_label = Label.new()
	part_name_label.name = "PartName"
	part_name_label.text = "Holding: nothing"
	part_name_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	part_name_label.add_theme_font_size_override("font_size", 14)
	part_name_label.position = Vector2(10, 100)
	panel.add_child(part_name_label)

	instructions_label = Label.new()
	instructions_label.name = "Instructions"
	instructions_label.text = "Hold RMB: rotate held part\nLMB part on table: pick it back up\nClick box: grab part  ·  LMB: place\nScroll: raise/lower held part"
	instructions_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	instructions_label.add_theme_font_size_override("font_size", 11)
	instructions_label.position = Vector2(10, 125)
	panel.add_child(instructions_label)

	# ── Tool selector ─────────────────────────────────────────────────────────
	var tool_panel := _make_panel(Vector2(10, 235), Vector2(320, 115))
	_hud_root.add_child(tool_panel)

	var tool_title := Label.new()
	tool_title.text = "🔧 ATTACHMENT TOOL"
	tool_title.add_theme_font_size_override("font_size", 14)
	tool_title.position = Vector2(10, 10)
	tool_panel.add_child(tool_title)

	var tool_hbox := HBoxContainer.new()
	tool_hbox.position = Vector2(10, 35)
	tool_hbox.size = Vector2(300, 32)
	tool_panel.add_child(tool_hbox)

	tool_tape_btn = _make_button("📎 TAPE", Vector2.ZERO, Vector2(80, 32))
	tool_tape_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_tape_btn.pressed.connect(_on_tape_pressed)
	tool_hbox.add_child(tool_tape_btn)

	tool_nail_btn = _make_button("🔨 NAIL", Vector2.ZERO, Vector2(80, 32))
	tool_nail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_nail_btn.pressed.connect(_on_nail_pressed)
	tool_hbox.add_child(tool_nail_btn)

	tool_crowbar_btn = _make_button("🪝 CROWBAR", Vector2.ZERO, Vector2(80, 32))
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
	nail_status_label.position = Vector2(10, 75)
	tool_panel.add_child(nail_status_label)

	_update_tool_buttons()

	# ── View toggle ───────────────────────────────────────────────────────────


	# ── TRUST ME button ───────────────────────────────────────────────────────
	trust_me_btn = _make_button("⚡ TRUST ME, I'M AN ENGINEER ⚡", Vector2(10, 410), Vector2(320, 50))
	trust_me_btn.add_theme_font_size_override("font_size", 15)
	trust_me_btn.add_theme_color_override("font_color", Color(1, 1, 0))
	trust_me_btn.pressed.connect(_on_trust_me_pressed)
	_hud_root.add_child(trust_me_btn)

	# ── Result display ────────────────────────────────────────────────────────
	var result_panel := _make_panel(Vector2(10, 470), Vector2(320, 135))
	result_panel.name = "ResultPanel"
	_hud_root.add_child(result_panel)

	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.text = "Press 'TRUST ME' to evaluate your repair!"
	result_label.add_theme_font_size_override("font_size", 13)
	result_label.custom_minimum_size = Vector2(300, 110)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.position = Vector2(10, 10)
	result_panel.add_child(result_label)

	# ── Reset button ──────────────────────────────────────────────────────────
	var reset_btn := _make_button("🗑 CLEAR ASSEMBLY", Vector2(10, 615), Vector2(155, 36))
	reset_btn.pressed.connect(_on_reset_pressed)
	_hud_root.add_child(reset_btn)

	var skip_btn := _make_button("⏭ SKIP ORDER", Vector2(175, 615), Vector2(155, 36))
	skip_btn.pressed.connect(_on_skip_pressed)
	_hud_root.add_child(skip_btn)

	# ── Silhouette overlay (hidden until evaluation) ──────────────────────────
	_silhouette_overlay = TextureRect.new()
	_silhouette_overlay.name = "SilhouetteOverlay"
	_silhouette_overlay.visible = false
	_silhouette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_silhouette_overlay.modulate = Color(1, 1, 1, 0.4)  # semi-transparent
	_silhouette_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_silhouette_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_silhouette_overlay.custom_minimum_size = Vector2(400, 400)
	ui_layer.add_child(_silhouette_overlay)

	# ── Back from eval button (hidden until evaluation) ───────────────────────
	_eval_back_btn = _make_button("↩ BACK TO WORKSPACE", Vector2(10, 10), Vector2(220, 40))
	_eval_back_btn.visible = false
	_eval_back_btn.pressed.connect(_exit_eval_view)
	ui_layer.add_child(_eval_back_btn)

# ── Order setup ──────────────────────────────────────────────────────────────
func _setup_order() -> void:
	_order = OrderData.new()
	_order.toy_name = "Broken Workshop Fan"
	_order.client_description = "The workshop fan stopped working! Needs:\n• A BLADE near the top\n• A MOTOR in the center\n• A FRAME at the base"
	_order.required_component_tags = ["blade", "motor", "frame"]
	_order.pass_tolerance = 80.0
	# Legacy requirements for spatial-tag evaluation fallback
	_order.requirements = [
		{"required_tag": "blade",  "target_position": Vector3(0.0,  0.30, 0.0), "points": 100},
		{"required_tag": "motor",  "target_position": Vector3(0.0,  0.00, 0.0), "points": 150},
		{"required_tag": "frame",  "target_position": Vector3(0.0, -0.20, 0.0), "points": 80},
	]
	_order.tolerance = 0.5
	GameState.current_order = _order

	# ── Ghost Blueprint (3D overlap evaluation) ─────────────────────────
	var ghost_blueprint = assembly_pivot.get_node_or_null("GhostBlueprint")
	
	var dir = DirAccess.open("res://scenes/ghosts")
	var ghost_files = []
	if dir:
		dir.list_dir_begin()
		var f = dir.get_next()
		while f != "":
			if f.ends_with(".tscn"):
				ghost_files.append(f)
			f = dir.get_next()
	
	if ghost_files.size() > 0:
		var random_ghost = ghost_files[randi() % ghost_files.size()]
		
		# Try to pick a different ghost than the current one
		if ghost_files.size() > 1 and _order != null:
			var current_toy_name = _order.toy_name.replace("Broken ", "")
			var loop_count = 0
			while random_ghost.replace("Ghost_", "").replace(".tscn", "").capitalize() == current_toy_name and loop_count < 10:
				random_ghost = ghost_files[randi() % ghost_files.size()]
				loop_count += 1
				
		var ghost_scene = load("res://scenes/ghosts/" + random_ghost)
		if ghost_scene:
			ghost_root = ghost_scene.instantiate()
			
			# Update order name to match
			var toy_name = random_ghost.replace("Ghost_", "").replace(".tscn", "").capitalize()
			_order.toy_name = "Broken " + toy_name
			_order.client_description = "We need a " + toy_name + "! Please assemble it according to the blueprint."
			
			if ghost_blueprint:
				var offset = ghost_blueprint.get("projection_offset")
				if offset == null:
					offset = Vector3.ZERO
				ghost_root.transform = ghost_blueprint.transform
				ghost_root.position += offset
			
			assembly_pivot.add_child(ghost_root)
			_apply_ghost_material(ghost_root)
			blueprint_evaluator.set_ghost_root(ghost_root)
	
	if ghost_blueprint:
		ghost_blueprint.queue_free()

	# Dynamically inject order fields into the UI card
	_populate_order_ui(_order)

## Dynamically populate the REPAIR ORDER UI card from the loaded .tres resource.
func _populate_order_ui(order: OrderData) -> void:
	if order_title_label:
		order_title_label.text = "📋 %s" % order.toy_name
	if order_desc_label:
		order_desc_label.text = order.client_description

# ── Input handling ────────────────────────────────────────────────────────────
## Uses _unhandled_input for key events (replaces broken Input.is_key_just_pressed polling).
func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_playing() or GameState.camera_state == "TRANSITIONING" or GameState.camera_state == "MENU_VIEW":
		return

	# Handle ghost rotation if no part is held
	if GameState.held_part == null and ghost_root != null:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			_ghost_rmb_held = event.pressed
			if _ghost_rmb_held:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				if ghost_root is RigidBody3D:
					ghost_root.collision_mask = 0
					ghost_root.freeze = true
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				if ghost_root is RigidBody3D:
					ghost_root.collision_mask = 1
					ghost_root.freeze = false
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseMotion and _ghost_rmb_held:
			var motion := event as InputEventMouseMotion
			var cam := get_viewport().get_camera_3d()
			if cam:
				var cam_right := cam.global_transform.basis.x.normalized()
				var cam_up := cam.global_transform.basis.y.normalized()
				ghost_root.rotate(cam_up, -motion.relative.x * GHOST_ROT_SPEED)
				ghost_root.rotate(cam_right, -motion.relative.y * GHOST_ROT_SPEED)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_TAB:
			_on_ghost_toggle_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			# Tool deselection: Escape resets to "none"
			GameState.set_active_tool("none")
			_update_tool_buttons()
			get_viewport().set_input_as_handled()


func _apply_ghost_material(ghost: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Brighter neon green with higher opacity
	mat.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
	
	# Enable emission for a glowing effect
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4)
	mat.emission_energy_multiplier = 1.5
	
	# Use unshaded so it's always fully bright regardless of room lighting
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true # Still draw on top of solid objects
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var meshes = _find_all_meshes(ghost)
	for mesh in meshes:
		mesh.material_override = mat

func _find_all_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_meshes(child))
	return result

func _input(event: InputEvent) -> void:
	if not GameState.is_playing() or GameState.camera_state == "TRANSITIONING" or GameState.camera_state == "MENU_VIEW":
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Don't process clicks during evaluation view
		if GameState.camera_state == "EVAL_VIEW":
			return
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
				# ── Priority 1: nail/crowbar tool intercept ──────────────
				if (GameState.active_tool == "nail" or GameState.active_tool == "crowbar") and nail_tool.handle_click(mouse_pos):
					return
					
				# ── Priority 1.5: tape tool intercept ────────────────────
				if GameState.active_tool == "tape" and tape_tool.handle_click(mouse_pos):
					return

				# ── Priority 2: pick up an existing loose JunkPart ───────
				if GameState.active_tool == "none":
					var existing := _raycast_for_part(mouse_pos)
					if existing:
						_pick_up_existing_part(existing)
						return

					# ── Priority 3: grab a new part from a JunkBox ───────────
					var box := _raycast_for_box(mouse_pos)
					if box:
						_extract_from_box(box)

# ── Raycast helpers ───────────────────────────────────────────────────────────

## Raycast against placed/loose JunkParts (collision layer 2).
## Returns the JunkPart if it is not already held. Jointed parts are
## allowed — the compound movement system will pick up the whole cluster.
func _raycast_for_part(mouse_pos: Vector2) -> Node3D:
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

	var part := collider as Node3D

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
func _pick_up_existing_part(part: Node3D) -> void:
	# ── Step 1: Discover the full connected cluster ─────────────────────
	var cluster: Array[Node3D] = attachment_system.get_connected_cluster(part, assembly_pivot)

	# ── Check if any part in the cluster is attached to the base ────────
	if _is_cluster_attached_to_base(cluster):
		if part_name_label:
			part_name_label.text = "Cannot pick up: Attached to base"
		return

	# Build secondary list (everything except the primary clicked part)
	var secondary: Array[Node3D] = []
	for p: Node3D in cluster:
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
	for p: Node3D in cluster:
		GameState.assembly_parts.erase(p)

	# ── Step 4: Prepare secondary parts for compound movement ───────────
	for p: Node3D in secondary:
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
	for p: Node3D in cluster:
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
	
	# ── Step 8: Wake up all remaining parts so they don't float! ────────
	for child in assembly_pivot.get_children():
		if child is RigidBody3D:
			child.sleeping = false

func _is_cluster_attached_to_base(cluster: Array[Node3D]) -> bool:
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
	var result = box.extract_random_part()
	if result.is_empty() or not result.has("data"):
		return
		
	var item_data: ItemData = result["data"]
	var model_path: String = result.get("model_path", "")

	var part := JunkPart.new()
	if not model_path.is_empty():
		var scene = ResourceLoader.load(model_path) as PackedScene
		if scene:
			part.custom_model_scene = scene
			
	part.setup(item_data)
	add_child(part)
	var spawn_pos := assembly_pivot.global_position
	spawn_pos.y = _table_y + part._model_half_height + 0.05
	part.global_position = spawn_pos
	part.pick_up()
	GameState.pick_up_part(part)

	var cc := get_node_or_null("CameraController") as Node3D
	if cc and cc.has_method("go_to_table_view"):
		cc.go_to_table_view()

func _place_held_part(_mouse_pos: Vector2) -> void:
	var part := GameState.held_part
	if part == null:
		return

	# Release the part at its current held position — gravity does the rest.
	var drop_pos := part.global_position

	# ── Place the primary part ───────────────────────────────────────────
	part.place_at(drop_pos, assembly_pivot)

	# ── Place all secondary cluster parts ────────────────────────────────
	var secondary := GameState.held_cluster.duplicate()
	var cluster_joints := GameState.cluster_joints.duplicate()

	for p: Node3D in secondary:
		if not is_instance_valid(p):
			continue
		var world_xform := p.global_transform

		if p.get_parent() != assembly_pivot:
			p.reparent(assembly_pivot, true)

		p.global_transform = world_xform
		p.is_held = false
		p.is_placed = true
		p.collision_layer = 2
		p.collision_mask = 3
		p.freeze = false

		GameState.register_assembly_part(p)

	# ── Reparent nails back to assembly_pivot ────────────────────────────
	for child in get_children():
		if child is Nail:
			child.reparent(assembly_pivot, true)

	# ── Re-enable cluster joints with corrected node paths ──────────────
	for joint: Joint3D in cluster_joints:
		if not is_instance_valid(joint):
			continue
		if joint.get_parent() != assembly_pivot:
			joint.reparent(assembly_pivot, true)
		var j_pos := joint.global_position
		var all_cluster: Array[Node3D] = [part as Node3D]
		all_cluster.append_array(secondary)
		var sorted_by_dist: Array[Node3D] = []
		sorted_by_dist.append_array(all_cluster)
		sorted_by_dist.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_to(j_pos) < b.global_position.distance_to(j_pos)
		)
		if sorted_by_dist.size() >= 2:
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


func _attach_part(part: Node3D) -> void:
	# In hand or empty mode, don't auto-create joints – parts stay separate
	if GameState.active_tool == "none" or GameState.active_tool == "select" or GameState.active_tool == "hand":
		return
		
	if GameState.active_tool == "nail" or GameState.active_tool == "tape" or GameState.active_tool == "crowbar":
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

	if GameState.active_tool != "none":
		new_hovered = null

	if new_hovered != _hovered_box:
		if _hovered_box:
			_hovered_box.highlight(false)
		if new_hovered:
			new_hovered.highlight(true)
		_hovered_box = new_hovered

func _on_ghost_toggle_pressed() -> void:
	if GameState.held_part != null:
		return

	if ghost_root != null:
		ghost_root.visible = not ghost_root.visible

## Tool toggle: clicking an active tool button a second time resets to "none".
func _on_tape_pressed() -> void:
	if GameState.held_part != null:
		return
	GameState.set_active_tool("none" if GameState.active_tool == "tape" else "tape")
	_update_tool_buttons()

func _on_nail_pressed() -> void:
	if GameState.held_part != null:
		return
	GameState.set_active_tool("none" if GameState.active_tool == "nail" else "nail")
	_update_tool_buttons()

func _on_crowbar_pressed() -> void:
	if GameState.held_part != null:
		return
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
		match active:
			"nail":
				nail_status_label.text = "Click on a part to place nail, then click nail to hammer"
			"crowbar":
				nail_status_label.text = "Click on a nail or tape to remove it"
			"tape":
				nail_status_label.text = "Click two surface points to tape them together (wobbly)"
			"none":
				nail_status_label.text = "✋ Hand mode — parts drop freely (click tool to select)"
			_:
				nail_status_label.text = ""

# ── TRUST ME evaluation ──────────────────────────────────────────────────────
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

	# ── Blueprint 3D Evaluation (ghost coverage) ─────────────────────────
	if ghost_root != null:
		var bp_result = blueprint_evaluator.evaluate(assembly_pivot)
		var pct: int = bp_result["percentage"]
		var matched: int = bp_result["matched_count"]
		var total: int = bp_result["total_ghost_pieces"]

		var spill_ratio = bp_result.get("spill_ratio", 0.0)
		var spill_pct: int = int(spill_ratio * 100.0)
		
		# Separate base score and final score for clarity
		var base_pct: int = pct
		var final_pct: int = max(0, base_pct - spill_pct)
		var grade: String = evaluation_system.grade_label(final_pct)
		
		var detail := "━━━ BLUEPRINT EVAL ━━━\n%s\nMatched: %d / %d pieces\n" % [grade, matched, total]
		detail += "▶ Base Coverage: %d%%\n" % base_pct
		detail += "▶ Spill Penalty: -%d%%\n" % spill_pct
		detail += "▶ Final Score: %d%%\n\n" % final_pct
		
		for piece in bp_result["pieces"]:
			var icon := "✅" if piece["matched"] else "❌"
			var cov_pct: int = int(piece["coverage"] * 100.0)
			var parts_used: int = piece["overlapping_parts"]
			detail += "%s %s: %d%% filled (%d parts)\n" % [icon, piece["ghost_label"], cov_pct, parts_used]
		
		if final_pct >= 40:
			if spill_ratio > 0.08:
				detail += "\n❌ FAILED! You spilled too much material outside the ghost bounds! (Max 8%)"
			else:
				detail += "\n🎉 SUCCESS! Loading next ghost blueprint in 3 seconds..."
				var reset_func = func():
					_on_skip_pressed()
				get_tree().create_timer(3.0).timeout.connect(reset_func)
			
		result_label.text = detail
		return

	# ── Silhouette Evaluation (if blueprint texture is assigned) ─────────
	if _order.blueprint_silhouette != null:
		_enter_eval_view()
		return

	# ── Fallback: Legacy spatial-tag evaluation ──────────────────────────
	_run_legacy_evaluation()


## Enter the orthographic evaluation view with silhouette overlay.
func _enter_eval_view() -> void:
	var cc = get_node_or_null("CameraController")
	if cc == null or not cc.has_method("enter_eval_view"):
		_run_legacy_evaluation()
		return

	# Switch camera to orthographic
	var eval_cam: Camera3D = cc.enter_eval_view()
	if eval_cam == null:
		_run_legacy_evaluation()
		return

	# Show the silhouette overlay
	if _silhouette_overlay and _order.blueprint_silhouette:
		_silhouette_overlay.texture = _order.blueprint_silhouette
		_silhouette_overlay.visible = true

	# Show the back button
	if _eval_back_btn:
		_eval_back_btn.visible = true

	# Run the silhouette evaluation after a brief delay (let camera settle)
	await get_tree().create_timer(0.1).timeout
	var sil_result = evaluation_system.evaluate_silhouette(eval_cam, _order, assembly_pivot)

	var pct: int = sil_result["percentage"]
	var passed: bool = sil_result["passed"]
	var detail: String = sil_result["detail"]
	var grade: String = evaluation_system.grade_label(pct)

	if result_label:
		result_label.text = "━━━ SILHOUETTE EVAL ━━━\n%s\n%s" % [grade, detail]
		if passed:
			result_label.text += "\n🎉 PASSED! You're a real engineer!"
		else:
			result_label.text += "\n🔧 Keep tweaking... (need %d%%)" % int(_order.pass_tolerance)


## Exit the evaluation view and return to workspace.
func _exit_eval_view() -> void:
	if _silhouette_overlay:
		_silhouette_overlay.visible = false
	if _eval_back_btn:
		_eval_back_btn.visible = false

	var cc = get_node_or_null("CameraController")
	if cc and cc.has_method("exit_eval_view"):
		cc.exit_eval_view()


## Legacy spatial-tag evaluation (fallback when no blueprint_silhouette).
func _run_legacy_evaluation() -> void:
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

	if result_label:
		result_label.text = "━━━ EVALUATION ━━━\n%s\nScore: %d / %d (%d%%)\n\n%s" % [
			grade, score, max_s, pct, detail
		]

func _on_reset_pressed() -> void:
	# Exit eval view if active
	_exit_eval_view()

	# Free any cluster members currently held (reparented under Main)
	for part: Node3D in GameState.held_cluster:
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

func _on_skip_pressed() -> void:
	# Clear the parts first
	_on_reset_pressed()
	
	# Delete the old ghost
	if is_instance_valid(ghost_root):
		ghost_root.queue_free()
		ghost_root = null
		
	# Spawn a new random ghost
	_setup_order()

# ── Nail tool signal handlers ─────────────────────────────────────────────────
func _on_nail_placed(nail: Nail) -> void:
	if not nail.nail_unfastened.is_connected(_on_nail_removed):
		nail.nail_unfastened.connect(_on_nail_removed)
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

func _on_nail_driven(nail: Nail) -> void:
	if nail_status_label:
		nail_status_label.text = "✅ Nail fastened! Place another or switch tools."

	call_deferred("_recalculate_assembly_collisions")

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
	call_deferred("_recalculate_assembly_collisions")

func _on_tape_canceled() -> void:
	if nail_status_label:
		nail_status_label.text = "❌ Tape canceled."
		
func _on_tape_placement_blocked(reason: String) -> void:
	if nail_status_label:
		nail_status_label.text = "⚠️ %s" % reason

# ── GameState signal handlers ─────────────────────────────────────────────────
func _on_camera_state_changed(new_state: String) -> void:
	pass

func _on_part_picked_up(part: RigidBody3D) -> void:
	if part_name_label and part is JunkPart:
		var jp := part as Node3D
		part_name_label.text = "Holding: %s [%s]" % [
			jp.item_data.item_name if jp.item_data else "???",
			", ".join(jp.tags)
		]

func _on_part_placed() -> void:
	if part_name_label:
		part_name_label.text = "Holding: nothing"

# ── UI Helpers ────────────────────────────────────────────────────────────────
func _make_panel(pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
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

func _on_nail_removed() -> void:
	call_deferred("_recalculate_assembly_collisions")

func _on_tape_removed() -> void:
	call_deferred("_recalculate_assembly_collisions")

func _recalculate_assembly_collisions() -> void:
	if not assembly_pivot:
		return
		
	var all_parts: Array[PhysicsBody3D] = []
	for child in assembly_pivot.get_children():
		if child is JunkPart:
			all_parts.append(child as PhysicsBody3D)
			
	# 1. Clear all exceptions between assembly parts
	for i in range(all_parts.size()):
		for j in range(i + 1, all_parts.size()):
			all_parts[i].remove_collision_exception_with(all_parts[j])
			all_parts[j].remove_collision_exception_with(all_parts[i])
			
	# 2. Re-apply for actual connected clusters
	var visited: Array[Node3D] = []
	for part in all_parts:
		if part in visited:
			continue
		var cluster: Array[Node3D] = attachment_system.get_connected_cluster(part, assembly_pivot)
		for c in cluster:
			if not c in visited:
				visited.append(c)
				
		for i in range(cluster.size()):
			for j in range(i + 1, cluster.size()):
				var a := cluster[i] as PhysicsBody3D
				var b := cluster[j] as PhysicsBody3D
				if a and b:
					a.add_collision_exception_with(b)
					b.add_collision_exception_with(a)
