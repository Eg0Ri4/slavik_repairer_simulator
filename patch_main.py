import re

with open("scripts/Main.gd", "r") as f:
    content = f.read()

# 1. Add _hud_root variable
content = content.replace("var ui_layer: CanvasLayer\n", "var ui_layer: CanvasLayer\nvar _hud_root: Control\n")

# 2. Update _build_ui to create _hud_root
build_ui_orig = """func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)"""

build_ui_new = """func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	
	_hud_root = Control.new()
	_hud_root.name = "HudRoot"
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_hud_root)"""
content = content.replace(build_ui_orig, build_ui_new)

# 3. Replace ui_layer.add_child with _hud_root.add_child inside _build_ui for HUD panels
# Order Panel
content = content.replace("ui_layer.add_child(panel)", "_hud_root.add_child(panel)")
# Tool Panel
content = content.replace("ui_layer.add_child(tool_panel)", "_hud_root.add_child(tool_panel)")
# Result Panel
content = content.replace("ui_layer.add_child(result_panel)", "_hud_root.add_child(result_panel)")
# Reset btn
content = content.replace("ui_layer.add_child(reset_btn)", "_hud_root.add_child(reset_btn)")
# Trust me btn
content = content.replace("ui_layer.add_child(trust_me_btn)", "_hud_root.add_child(trust_me_btn)")

# Note: view_toggle_btn is left on ui_layer!
# ui_layer.add_child(view_toggle_btn) is unchanged.
# _silhouette_overlay and _eval_back_btn are unchanged.

# 4. Update _setup_menu
setup_menu_orig = """func _setup_menu() -> void:
	var menu = MenuController.new()
	menu.name = "MenuController"
	add_child(menu)
	menu.game_started.connect(func(): pass)
	menu.returned_to_menu.connect(func(): ui_layer.visible = false)
	
	ui_layer.visible = false
	GameState.set_phase(GameState.GamePhase.MENU)"""

setup_menu_new = """func _setup_menu() -> void:
	var menu = MenuController.new()
	menu.name = "MenuController"
	ui_layer.add_child(menu)
	menu.game_started.connect(func():
		_hud_root.visible = true
		view_toggle_btn.visible = true
	)
	menu.returned_to_menu.connect(func():
		_hud_root.visible = false
		view_toggle_btn.visible = false
	)
	
	_hud_root.visible = false
	if view_toggle_btn:
		view_toggle_btn.visible = false
	GameState.set_phase(GameState.GamePhase.MENU)"""
content = content.replace(setup_menu_orig, setup_menu_new)

# 5. Update _on_camera_state_changed
cam_state_orig = """func _on_camera_state_changed(new_state: String) -> void:
	if new_state == "TABLE_VIEW" or new_state == "UNDER_TABLE_VIEW":
		if GameState.is_playing():
			ui_layer.visible = true
	elif new_state == "EVAL_VIEW":
		# Keep UI visible during eval view (for result label)
		pass
	else:
		ui_layer.visible = false
		
	if view_toggle_btn == null:
		return
	if new_state == "TABLE_VIEW":
		view_toggle_btn.text = "🔽 LOOK UNDER TABLE (Tab)"
	else:
		view_toggle_btn.text = "🔼 BACK TO TABLE (Tab)\""""

cam_state_new = """func _on_camera_state_changed(new_state: String) -> void:
	if view_toggle_btn == null:
		return
		
	if new_state == "TABLE_VIEW":
		if GameState.is_playing():
			_hud_root.visible = true
			view_toggle_btn.visible = true
		view_toggle_btn.text = "🔽 LOOK UNDER TABLE (Tab)"
	elif new_state == "UNDER_TABLE_VIEW":
		if GameState.is_playing():
			_hud_root.visible = false
			view_toggle_btn.visible = true
		view_toggle_btn.text = "🔼 BACK TO TABLE (Tab)"
	elif new_state == "EVAL_VIEW":
		_hud_root.visible = true
		view_toggle_btn.visible = false
	else:
		_hud_root.visible = false
		view_toggle_btn.visible = false"""
content = content.replace(cam_state_orig, cam_state_new)

# 6. Update _on_phase_changed
phase_orig = """func _on_phase_changed(phase: GameState.GamePhase) -> void:
	if phase == GameState.GamePhase.MENU:
		ui_layer.visible = false"""

phase_new = """func _on_phase_changed(phase: GameState.GamePhase) -> void:
	pass"""
content = content.replace(phase_orig, phase_new)

with open("scripts/Main.gd", "w") as f:
    f.write(content)
print("Main.gd patched successfully")
