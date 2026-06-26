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

# Under-table boxes
var boxes: Array[JunkBox] = []

# UI references
var ui_layer: CanvasLayer
var tool_tape_btn: Button
var tool_bolts_btn: Button
var trust_me_btn: Button
var result_label: Label
var held_label: Label
var view_toggle_btn: Button
var order_desc_label: Label
var part_name_label: Label
var instructions_label: Label

# Hover highlight state
var _hovered_box: JunkBox = null

# Currently hovered drop-zone part (for visual feedback)
var _drop_preview: Node3D = null

# Active order
var _order: OrderData

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_lighting()
	_build_table()
	_build_assembly_pivot()   # Must be before camera so group exists at CameraController._ready()
	_build_boxes()
	_build_camera()
	_build_systems()
	_build_ui()
	_setup_order()

	# Connect GameState signals
	GameState.camera_state_changed.connect(_on_camera_state_changed)
	GameState.part_picked_up.connect(_on_part_picked_up)
	GameState.part_placed.connect(_on_part_placed)

# ── Scene construction ───────────────────────────────────────────────────────
func _build_lighting() -> void:
	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.10, 0.08)
	env.ambient_light_color = Color(0.8, 0.75, 0.65)
	env.ambient_light_energy = 0.6
	ambient.environment = env
	add_child(ambient)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_color = Color(1.0, 0.95, 0.8)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.0, 1.5, -0.5)
	fill.light_color = Color(0.5, 0.6, 0.8)
	fill.light_energy = 0.8
	fill.omni_range = 5.0
	add_child(fill)

func _build_table() -> void:
	# Load and instantiate the garage & workbench GLB model
	var garage_scene := load("res://a garage with a work station.glb")
	if garage_scene:
		table = garage_scene.instantiate()
		table.name = "GarageAndTable"
		var basis := Basis(
			Vector3(0.94388556, 0, 0.33027276),
			Vector3(0, 1, 0),
			Vector3(-0.33027276, 0, 0.94388556)
		)
		table.transform = Transform3D(
			basis,
			Vector3(-0.53302, -0.19935045, -0.6058504)
		)
		add_child(table)
	else:
		# Fallback: Table surface (the workbench top)
		table = CSGBox3D.new()
		table.name = "Table"
		table.size = Vector3(2.0, 0.12, 1.5)
		table.position = Vector3(0.0, 0.0, 0.0)
		var table_mat := StandardMaterial3D.new()
		table_mat.albedo_color = Color(0.45, 0.32, 0.20)
		table_mat.roughness = 0.85
		table.material = table_mat
		add_child(table)

	# Table static body for raycasting (so parts can land on it)
	var table_static := StaticBody3D.new()
	table_static.name = "TableStaticBody"
	table_static.collision_layer = 1
	table_static.collision_mask = 0
	var ts_col := CollisionShape3D.new()
	var ts_shape := BoxShape3D.new()
	ts_shape.size = Vector3(2.0, 0.12, 1.5)
	ts_col.shape = ts_shape
	table_static.add_child(ts_col)
	table_static.position = Vector3(0.0, 0.0, 0.0)
	add_child(table_static)

func _build_camera() -> void:
	camera_controller = Node3D.new()
	camera_controller.name = "CameraController"
	camera_controller.set_script(load("res://scripts/CameraController.gd"))
	add_child(camera_controller)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 100.0
	camera_controller.add_child(cam)

func _build_boxes() -> void:
	# Position the boxes in a horizontal row neatly in front of the assembly station
	var box_configs: Array[Dictionary] = [
		{"pos": Vector3(-0.6, 0.235, 0.55), "color": Color(0.55, 0.32, 0.14), "label": "Box A"},
		{"pos": Vector3(0.0,  0.235, 0.55), "color": Color(0.20, 0.45, 0.25), "label": "Box B"},
		{"pos": Vector3(0.6,  0.235, 0.55), "color": Color(0.30, 0.30, 0.55), "label": "Box C"},
	]

	for cfg in box_configs:
		var box := JunkBox.new()
		box.position = cfg["pos"]
		box.box_color = cfg["color"]
		box.box_label = cfg["label"]
		add_child(box)
		boxes.append(box)

func _build_assembly_pivot() -> void:
	assembly_pivot = Node3D.new()
	assembly_pivot.name = "AssemblyPivot"
	assembly_pivot.position = Vector3(0.0, 0.12, 0.0)
	assembly_pivot.add_to_group("assembly_pivot")
	add_child(assembly_pivot)

	# A small base indicator on the table
	var base := CSGCylinder3D.new()
	base.name = "PivotBase"
	base.radius = 0.22
	base.height = 0.015
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.7, 0.6, 0.1)
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.6, 0.5, 0.05)
	base_mat.emission_energy_multiplier = 0.3
	base.material = base_mat
	assembly_pivot.add_child(base)

func _build_systems() -> void:
	attachment_system = AttachmentSystem.new()
	attachment_system.name = "AttachmentSystem"
	add_child(attachment_system)

	evaluation_system = EvaluationSystem.new()
	evaluation_system.name = "EvaluationSystem"
	add_child(evaluation_system)

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	# ── Order Panel (using VBoxContainer to prevent overlap) ─────────────────
	var panel := _make_panel(Vector2(10, 10), Vector2(320, 215))
	ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "OrderVBox"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Order title
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

	# Held part indicator
	part_name_label = Label.new()
	part_name_label.name = "PartName"
	part_name_label.text = "Holding: nothing"
	part_name_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	part_name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(part_name_label)

	# Instructions
	instructions_label = Label.new()
	instructions_label.name = "Instructions"
	instructions_label.text = "RMB drag: rotate assembly\nClick box: grab part\nLMB: place part"
	instructions_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	instructions_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(instructions_label)

	# ── Tool selector (using VBox & HBox layout) ─────────────────────────────
	var tool_panel := _make_panel(Vector2(10, 235), Vector2(320, 85))
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

	tool_bolts_btn = _make_button("🔩 BOLTS (Rigid)", Vector2.ZERO, Vector2(140, 32))
	tool_bolts_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_bolts_btn.pressed.connect(_on_bolts_pressed)
	tool_hbox.add_child(tool_bolts_btn)

	tool_tape_btn = _make_button("📎 TAPE (Wobbly)", Vector2.ZERO, Vector2(140, 32))
	tool_tape_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_tape_btn.pressed.connect(_on_tape_pressed)
	tool_hbox.add_child(tool_tape_btn)

	_update_tool_buttons()

	# ── View toggle ──────────────────────────────────────────────────────────
	view_toggle_btn = _make_button("🔽 LOOK UNDER TABLE (Tab)", Vector2(10, 330), Vector2(320, 40))
	view_toggle_btn.pressed.connect(_on_view_toggle_pressed)
	ui_layer.add_child(view_toggle_btn)

	# ── TRUST ME button ──────────────────────────────────────────────────────
	trust_me_btn = _make_button("⚡ TRUST ME, I'M AN ENGINEER ⚡", Vector2(10, 380), Vector2(320, 50))
	trust_me_btn.add_theme_font_size_override("font_size", 15)
	trust_me_btn.add_theme_color_override("font_color", Color(1, 1, 0))
	trust_me_btn.pressed.connect(_on_trust_me_pressed)
	ui_layer.add_child(trust_me_btn)

	# ── Result display (using vertical layout) ───────────────────────────────
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

	# ── Reset button ─────────────────────────────────────────────────────────
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

# ── Input handling ───────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# Tab key toggles view
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_TAB:
			_on_view_toggle_pressed()

	# Mouse click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(event.position)

func _handle_left_click(mouse_pos: Vector2) -> void:
	match GameState.camera_state:
		"UNDER_TABLE_VIEW":
			# Try to click a box
			var box := _raycast_for_box(mouse_pos)
			if box:
				_extract_from_box(box)

		"TABLE_VIEW":
			# If holding a part, place it
			if GameState.held_part != null:
				_place_held_part(mouse_pos)
			else:
				# Try to click a box to grab a part directly
				var box := _raycast_for_box(mouse_pos)
				if box:
					_extract_from_box(box)

func _raycast_for_box(mouse_pos: Vector2) -> JunkBox:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null

	var origin := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 4  # box layer
	var result := space.intersect_ray(query)

	if result and result.collider is JunkBox:
		return result.collider as JunkBox
	return null

func _extract_from_box(box: JunkBox) -> void:
	var item_data := box.extract_random_part()
	if item_data == null:
		return

	# Spawn part above the box temporarily
	var part := JunkPart.new()
	part.setup(item_data)
	add_child(part)
	part.global_position = box.global_position + Vector3(0, 0.3, 0)
	part.pick_up()
	GameState.pick_up_part(part)

	# Transition camera back to table
	var cc := get_node_or_null("CameraController") as Node3D
	if cc and cc.has_method("go_to_table_view"):
		cc.go_to_table_view()

func _place_held_part(mouse_pos: Vector2) -> void:
	var part := GameState.held_part
	if part == null:
		return

	# Raycast against the table or existing parts
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var origin := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)

	# Default: place at table surface height
	var table_y := 0.06   # table top surface
	var drop_pos := Vector3.ZERO

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 1   # table layer
	var result := space.intersect_ray(query)

	if result:
		drop_pos = result.position
		drop_pos.y = max(drop_pos.y, table_y)
	else:
		# Fallback: intersect horizontal plane
		if abs(direction.y) > 0.001:
			var t := (table_y - origin.y) / direction.y
			if t > 0:
				drop_pos = origin + direction * t

	drop_pos.y = table_y + (part.item_data.size.y * 0.5 if part.item_data else 0.1)

	part.place_at(drop_pos, assembly_pivot)
	_attach_part(part)
	GameState.place_part()

func _attach_part(part: JunkPart) -> void:
	var placed_count: int = 0
	for child in assembly_pivot.get_children():
		if child is JunkPart and child != part and child.is_placed:
			placed_count += 1

	if placed_count == 0:
		# First piece — just sits on the pivot, no joint needed
		return

	# Attach to the nearest sibling
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

# ── UI callbacks ─────────────────────────────────────────────────────────────
func _on_view_toggle_pressed() -> void:
	if GameState.held_part != null:
		return  # Don't go under table while holding something

	var cc := get_node_or_null("CameraController")
	if cc and cc.has_method("toggle_view"):
		cc.toggle_view()

func _on_bolts_pressed() -> void:
	GameState.set_active_tool("bolts")
	_update_tool_buttons()

func _on_tape_pressed() -> void:
	GameState.set_active_tool("tape")
	_update_tool_buttons()

func _update_tool_buttons() -> void:
	if tool_bolts_btn == null or tool_tape_btn == null:
		return
	var active := GameState.active_tool
	tool_bolts_btn.modulate = Color(1.0, 0.9, 0.3) if active == "bolts" else Color(0.75, 0.75, 0.75)
	tool_tape_btn.modulate  = Color(1.0, 0.9, 0.3) if active == "tape"  else Color(0.75, 0.75, 0.75)

func _on_trust_me_pressed() -> void:
	if _order == null:
		return
	if result_label == null:
		return

	# Count placed parts
	var placed_count: int = 0
	for child in assembly_pivot.get_children():
		if child is JunkPart:
			placed_count += 1

	if placed_count == 0:
		result_label.text = "❌ Nothing is attached yet!\nGrab some junk from the boxes!"
		return

	var eval_result := evaluation_system.evaluate(assembly_pivot, _order)
	var pct: int = eval_result["percentage"]
	var grade: String = evaluation_system.grade_label(pct)
	var score: int = eval_result["total_score"]
	var max_s: int = eval_result["max_score"]

	var detail: String = ""
	for req in eval_result["requirements"]:
		var tag: String = req["tag"]
		var earned: int = req["points_earned"]
		var possible: int = req["points_possible"]
		var found: bool = req["found"]
		var icon: String = "✅" if earned == possible else ("⚠️" if earned > 0 else "❌")
		if not found:
			detail += "%s [%s]: Not found (0/%d pts)\n" % [icon, tag, possible]
		else:
			var dist: float = req["distance"]
			detail += "%s [%s]: %.2fm away (%d/%d pts)\n" % [icon, tag, dist, earned, possible]

	result_label.text = "━━━ EVALUATION ━━━\n%s\nScore: %d / %d (%d%%)\n\n%s" % [
		grade, score, max_s, pct, detail
	]

func _on_reset_pressed() -> void:
	# Remove all placed parts and joints from assembly pivot
	for child in assembly_pivot.get_children():
		if child is JunkPart or child is Joint3D:
			child.queue_free()

	# Also remove any held part
	if GameState.held_part:
		GameState.held_part.queue_free()
		GameState.place_part()

	GameState.clear_assembly()

	if result_label:
		result_label.text = "Assembly cleared. Grab some parts from the boxes!"

	if part_name_label:
		part_name_label.text = "Holding: nothing"

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
