## Main.gd
extends Node3D

var camera_controller : Node3D
var assembly_pivot    : Node3D
var table             : Node3D
var attachment_system : AttachmentSystem
var evaluation_system : EvaluationSystem
var nail_tool         : NailTool

var boxes : Array[JunkBox] = []

# UI
var ui_layer         : CanvasLayer
var _hud_root        : Control      # скрывается/показывается вместе с игрой
var tool_tape_btn    : Button
var tool_nail_btn    : Button
var trust_me_btn     : Button
var result_label     : Label
var view_toggle_btn  : Button
var order_desc_label : Label
var part_name_label  : Label
var instructions_label : Label
var nail_status_label  : Label

var _hovered_box : JunkBox = null
var _order       : OrderData
var _table_y     : float = 0.3

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	camera_controller = $CameraController
	assembly_pivot    = $AssemblyPivot
	table             = get_node_or_null("GarageAndTable")
	boxes             = [$BoxA, $BoxB, $BoxC]

	var table_static := get_node_or_null("TableStaticBody")
	if table_static:
		var col_shape = table_static.get_node_or_null("CollisionShape3D")
		if col_shape and col_shape.shape is BoxShape3D:
			var shape_size : Vector3 = (col_shape.shape as BoxShape3D).size
			_table_y = col_shape.global_position.y + \
				(shape_size.y * 0.5 * col_shape.global_transform.basis.get_scale().y)
			if assembly_pivot:
				assembly_pivot.global_position.y = _table_y

	_build_systems()
	_build_ui()        # строит весь HUD, но скрытым
	_setup_menu()      # поверх HUD добавляет MenuController
	_setup_order()

	GameState.camera_state_changed.connect(_on_camera_state_changed)
	GameState.part_picked_up.connect(_on_part_picked_up)
	GameState.part_placed.connect(_on_part_placed)
	GameState.phase_changed.connect(_on_phase_changed)

# ── Systems ───────────────────────────────────────────────────────────────────
func _build_systems() -> void:
	attachment_system      = AttachmentSystem.new()
	attachment_system.name = "AttachmentSystem"
	add_child(attachment_system)

	evaluation_system      = EvaluationSystem.new()
	evaluation_system.name = "EvaluationSystem"
	add_child(evaluation_system)

	nail_tool              = NailTool.new()
	nail_tool.name         = "NailTool"
	nail_tool.assembly_pivot = assembly_pivot
	add_child(nail_tool)

	nail_tool.nail_placed.connect(_on_nail_placed)
	nail_tool.nail_strike_performed.connect(_on_nail_strike)
	nail_tool.nail_fully_driven.connect(_on_nail_driven)
	nail_tool.nail_placement_blocked.connect(_on_nail_placement_blocked)

# ── UI build ──────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	ui_layer      = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	# Корневой контейнер всего игрового HUD — скрыт до старта
	_hud_root                 = Control.new()
	_hud_root.name            = "HudRoot"
	_hud_root.visible         = false
	_hud_root.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_hud_root)

	# ── Order panel ───────────────────────────────────────────────────────────
	var panel := _make_panel(Vector2(10, 10), Vector2(320, 215))
	_hud_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var order_title := Label.new()
	order_title.text = "📋 REPAIR ORDER"
	order_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(order_title)

	order_desc_label = Label.new()
	order_desc_label.text = "Loading order..."
	order_desc_label.add_theme_font_size_override("font_size", 13)
	order_desc_label.custom_minimum_size = Vector2(295, 60)
	order_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(order_desc_label)

	part_name_label = Label.new()
	part_name_label.text = "Holding: nothing"
	part_name_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	part_name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(part_name_label)

	instructions_label = Label.new()
	instructions_label.text = "Hold RMB: rotate held part\nNo part + RMB drag: orbit assembly\nClick box: grab part  ·  LMB: place\nQ/E: yaw  R/F: pitch  T/G: roll\nTab: look under table"
	instructions_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	instructions_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(instructions_label)

	# ── Tool panel ────────────────────────────────────────────────────────────
	var tool_panel := _make_panel(Vector2(10, 235), Vector2(320, 115))
	_hud_root.add_child(tool_panel)

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

	tool_nail_btn = _make_button("🔨 NAIL", Vector2.ZERO, Vector2(100, 32))
	tool_nail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_nail_btn.pressed.connect(_on_nail_pressed)
	tool_hbox.add_child(tool_nail_btn)

	nail_status_label = Label.new()
	nail_status_label.text = ""
	nail_status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	nail_status_label.add_theme_font_size_override("font_size", 12)
	tool_vbox.add_child(nail_status_label)

	_update_tool_buttons()

	# ── View toggle ───────────────────────────────────────────────────────────
	view_toggle_btn = _make_button("🔽 LOOK UNDER TABLE (Tab)", Vector2(10, 360), Vector2(320, 40))
	view_toggle_btn.pressed.connect(_on_view_toggle_pressed)
	_hud_root.add_child(view_toggle_btn)

	# ── Trust Me button ───────────────────────────────────────────────────────
	trust_me_btn = _make_button("⚡ TRUST ME, I'M AN ENGINEER ⚡", Vector2(10, 410), Vector2(320, 50))
	trust_me_btn.add_theme_font_size_override("font_size", 15)
	trust_me_btn.add_theme_color_override("font_color", Color(1, 1, 0))
	trust_me_btn.pressed.connect(_on_trust_me_pressed)
	_hud_root.add_child(trust_me_btn)

	# ── Result panel ──────────────────────────────────────────────────────────
	var result_panel := _make_panel(Vector2(10, 470), Vector2(320, 135))
	result_panel.name = "ResultPanel"
	_hud_root.add_child(result_panel)

	var result_vbox := VBoxContainer.new()
	result_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(result_vbox)

	result_label = Label.new()
	result_label.text = "Press 'TRUST ME' to evaluate your repair!"
	result_label.add_theme_font_size_override("font_size", 13)
	result_label.custom_minimum_size = Vector2(300, 110)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_vbox.add_child(result_label)

	# ── Reset button ──────────────────────────────────────────────────────────
	var reset_btn := _make_button("🗑 CLEAR ASSEMBLY", Vector2(10, 615), Vector2(320, 36))
	reset_btn.pressed.connect(_on_reset_pressed)
	_hud_root.add_child(reset_btn)

# ── Menu setup ────────────────────────────────────────────────────────────────
func _setup_menu() -> void:
	var menu      := MenuController.new()
	menu.name     = "MenuController"
	ui_layer.add_child(menu)
	# Подключаемся чтобы показывать/скрывать HUD при переключении фазы
	menu.game_started.connect(_show_hud)
	menu.returned_to_menu.connect(_hide_hud)

func _show_hud() -> void:
	_hud_root.visible = true

func _hide_hud() -> void:
	_hud_root.visible = false

# ── Order ─────────────────────────────────────────────────────────────────────
func _setup_order() -> void:
	_order             = OrderData.new()
	_order.order_name  = "Broken Workshop Fan"
	_order.description = "The workshop fan stopped working! Needs:\n• A BLADE near the top\n• A MOTOR in the center\n• A FRAME at the base"
	_order.requirements = [
		{"required_tag": "blade", "target_position": Vector3(0.0,  0.30, 0.0), "points": 100},
		{"required_tag": "motor", "target_position": Vector3(0.0,  0.00, 0.0), "points": 150},
		{"required_tag": "frame", "target_position": Vector3(0.0, -0.20, 0.0), "points": 80},
	]
	_order.tolerance        = 0.5
	GameState.current_order = _order

	if order_desc_label:
		order_desc_label.text = _order.description

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not GameState.is_playing():
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_TAB:
			_on_view_toggle_pressed()

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
				_place_held_part(mouse_pos)
			else:
				if GameState.active_tool == "nail" and nail_tool.handle_click(mouse_pos):
					return
				var existing := _raycast_for_part(mouse_pos)
				if existing:
					_pick_up_existing_part(existing)
					return
				var box := _raycast_for_box(mouse_pos)
				if box:
					_extract_from_box(box)

# ── Raycasts ──────────────────────────────────────────────────────────────────
func _raycast_for_part(mouse_pos: Vector2) -> JunkPart:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var origin    := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)
	var space     := get_world_3d().direct_space_state
	var query     := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 2
	var result    := space.intersect_ray(query)
	if not result or not (result.collider is JunkPart):
		return null
	var part := result.collider as JunkPart
	if part.is_held:
		return null
	for child in part.get_children():
		if child is Joint3D:
			return null
	return part

func _raycast_for_box(mouse_pos: Vector2) -> JunkBox:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var origin    := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)
	var space     := get_world_3d().direct_space_state
	var query     := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 4
	var result    := space.intersect_ray(query)
	if result and result.collider is JunkBox:
		return result.collider as JunkBox
	return null

# ── Part handling ─────────────────────────────────────────────────────────────
func _pick_up_existing_part(part: JunkPart) -> void:
	GameState.assembly_parts.erase(part)
	part.pick_up_existing()
	GameState.pick_up_part(part)

func _extract_from_box(box: JunkBox) -> void:
	var item_data := box.extract_random_part()
	if item_data == null:
		return
	var part := JunkPart.new()
	part.setup(item_data)
	add_child(part)
	var spawn_pos      := box.global_position
	spawn_pos.y        = _table_y + 0.05
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

	var origin    := cam.project_ray_origin(mouse_pos)
	var direction := cam.project_ray_normal(mouse_pos)
	var table_y   := _table_y
	var drop_pos  := Vector3.ZERO
	var hit_y     := table_y

	var space  := get_world_3d().direct_space_state
	var query  := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20.0)
	query.collision_mask = 3
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
	part.place_at(drop_pos, assembly_pivot)
	_attach_part(part)
	GameState.place_part()

func _attach_part(part: JunkPart) -> void:
	var placed_count : int = 0
	for child in assembly_pivot.get_children():
		if child is JunkPart and child != part and child.is_placed:
			placed_count += 1
	if placed_count == 0:
		return
	attachment_system.attach(part, assembly_pivot)

# ── Process (hover) ───────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not GameState.is_playing():
		return
	if GameState.camera_state == "UNDER_TABLE_VIEW":
		_update_box_hover()

func _update_box_hover() -> void:
	var mouse_pos   := get_viewport().get_mouse_position()
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
	GameState.set_active_tool("tape")
	_update_tool_buttons()

func _on_nail_pressed() -> void:
	GameState.set_active_tool("nail")
	_update_tool_buttons()

func _update_tool_buttons() -> void:
	if tool_tape_btn == null or tool_nail_btn == null:
		return
	var active         := GameState.active_tool
	var active_color   := Color(1.0, 0.9, 0.3)
	var inactive_color := Color(0.75, 0.75, 0.75)
	tool_tape_btn.modulate = active_color if active == "tape" else inactive_color
	tool_nail_btn.modulate = active_color if active == "nail" else inactive_color
	if nail_status_label:
		nail_status_label.text = "Click on a part to place nail, then click nail to hammer" \
			if active == "nail" else ""

func _on_trust_me_pressed() -> void:
	if _order == null or result_label == null:
		return
	var placed_count : int = 0
	for child in assembly_pivot.get_children():
		if child is JunkPart:
			placed_count += 1
	if placed_count == 0:
		result_label.text = "❌ Nothing attached yet!\nGrab some junk from the boxes!"
		return
	var eval_result   := evaluation_system.evaluate(assembly_pivot, _order)
	var pct   : int    = eval_result["percentage"]
	var grade : String = evaluation_system.grade_label(pct)
	var score : int    = eval_result["total_score"]
	var max_s : int    = eval_result["max_score"]
	var detail : String = ""
	for req in eval_result["requirements"]:
		var tag      : String = req["tag"]
		var earned   : int    = req["points_earned"]
		var possible : int    = req["points_possible"]
		var found    : bool   = req["found"]
		var icon     : String = "✅" if earned == possible else ("⚠️" if earned > 0 else "❌")
		if not found:
			detail += "%s [%s]: Not found (0/%d pts)\n" % [icon, tag, possible]
		else:
			detail += "%s [%s]: %.2fm away (%d/%d pts)\n" % [icon, tag, req["distance"], earned, possible]
	result_label.text = "━━━ EVALUATION ━━━\n%s\nScore: %d / %d (%d%%)\n\n%s" % \
		[grade, score, max_s, pct, detail]

func _on_reset_pressed() -> void:
	for child in assembly_pivot.get_children():
		if child is JunkPart or child is Joint3D or child is Nail:
			child.queue_free()
	if GameState.held_part:
		GameState.held_part.queue_free()
		GameState.place_part()
	GameState.clear_assembly()
	if result_label:
		result_label.text = "Assembly cleared. Grab some parts from the boxes!"
	if part_name_label:
		part_name_label.text = "Holding: nothing"

# ── Nail signals ──────────────────────────────────────────────────────────────
func _on_nail_placed(nail: Nail) -> void:
	if nail_status_label:
		nail_status_label.text = "🔨 Nail placed! Click it to hammer in (%d%%)" % int(nail.get_progress() * 100)

func _on_nail_strike(progress: float) -> void:
	if nail_status_label:
		var pct := int(progress * 100)
		nail_status_label.text = "✅ Nail fully driven! Objects fastened." \
			if pct >= 100 else "🔨 Hammering... %d%%" % pct

func _on_nail_driven(_nail: Nail) -> void:
	if nail_status_label:
		nail_status_label.text = "✅ Nail fastened! Place another or switch tools."

func _on_nail_placement_blocked(reason: String) -> void:
	if nail_status_label:
		nail_status_label.text = "⚠️ %s" % reason

# ── GameState signals ─────────────────────────────────────────────────────────
func _on_phase_changed(_phase: GameState.GamePhase) -> void:
	pass  # HUD показывается через _show_hud/_hide_hud от MenuController

func _on_camera_state_changed(new_state: String) -> void:
	if view_toggle_btn == null:
		return
	view_toggle_btn.text = "🔽 LOOK UNDER TABLE (Tab)" \
		if new_state == "TABLE_VIEW" else "🔼 BACK TO TABLE (Tab)"

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

# ── UI helpers ────────────────────────────────────────────────────────────────
func _make_panel(pos: Vector2, sz: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position            = pos
	panel.custom_minimum_size = sz
	panel.size                = sz
	var style                 := StyleBoxFlat.new()
	style.bg_color            = Color(0.08, 0.07, 0.06, 0.88)
	style.border_color        = Color(0.4, 0.35, 0.2, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left   = 8
	style.content_margin_top    = 6
	style.content_margin_right  = 8
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_button(txt: String, pos: Vector2, sz: Vector2) -> Button:
	var btn := Button.new()
	btn.text                = txt
	btn.position            = pos
	btn.custom_minimum_size = sz
	btn.size                = sz
	for pair in [
		["normal",  Color(0.22, 0.18, 0.12, 0.95), Color(0.55, 0.45, 0.25)],
		["hover",   Color(0.35, 0.28, 0.16, 0.95), Color(0.8,  0.7,  0.3 )],
		["pressed", Color(0.18, 0.15, 0.10, 0.95), Color(1.0,  0.9,  0.2 )],
	]:
		var s := StyleBoxFlat.new()
		s.bg_color     = pair[1]
		s.border_color = pair[2]
		s.set_border_width_all(2)
		s.set_corner_radius_all(5)
		btn.add_theme_stylebox_override(pair[0], s)
	return btn
