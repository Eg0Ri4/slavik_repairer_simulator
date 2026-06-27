with open("scripts/Main.gd", "r") as f:
    content = f.read()

# 1. Disable picking up existing loose part or extracting from box if holding tool
orig_priority2 = """				# ── Priority 2: pick up an existing loose JunkPart ───────
				var existing := _raycast_for_part(mouse_pos)
				if existing:
					_pick_up_existing_part(existing)
					return

				# ── Priority 3: grab a new part from a JunkBox ───────────
				var box := _raycast_for_box(mouse_pos)
				if box:
					_extract_from_box(box)"""

new_priority2 = """				# ── Priority 2: pick up an existing loose JunkPart ───────
				if GameState.active_tool == "none":
					var existing := _raycast_for_part(mouse_pos)
					if existing:
						_pick_up_existing_part(existing)
						return

					# ── Priority 3: grab a new part from a JunkBox ───────────
					var box := _raycast_for_box(mouse_pos)
					if box:
						_extract_from_box(box)"""

content = content.replace(orig_priority2, new_priority2)

# 2. Disable tool selection if holding a part
def patch_tool_btn(func_name, tool_name):
    orig = f"""func {func_name}() -> void:
	GameState.set_active_tool("none" if GameState.active_tool == "{tool_name}" else "{tool_name}")"""
    new = f"""func {func_name}() -> void:
	if GameState.held_part != null:
		return
	GameState.set_active_tool("none" if GameState.active_tool == "{tool_name}" else "{tool_name}")"""
    return orig, new

orig_t, new_t = patch_tool_btn("_on_tape_pressed", "tape")
content = content.replace(orig_t, new_t)

orig_n, new_n = patch_tool_btn("_on_nail_pressed", "nail")
content = content.replace(orig_n, new_n)

orig_c, new_c = patch_tool_btn("_on_crowbar_pressed", "crowbar")
content = content.replace(orig_c, new_c)

# Also disable hovering boxes when holding a tool
orig_hover = """	if new_hovered != _hovered_box:
		if _hovered_box:
			_hovered_box.highlight(false)"""

new_hover = """	if GameState.active_tool != "none":
		new_hovered = null

	if new_hovered != _hovered_box:
		if _hovered_box:
			_hovered_box.highlight(false)"""
content = content.replace(orig_hover, new_hover)

# Also update the instructions label to reflect the changes
orig_instr = """	instructions_label.text = "Hold RMB: rotate held part\\nNo part + RMB drag: orbit assembly\\nLMB part on table: pick it back up\\nClick box: grab part  ·  LMB: place\\nScroll: raise/lower held part\""""
new_instr = """	instructions_label.text = "Hold RMB: rotate held part\\nLMB part on table: pick it back up\\nClick box: grab part  ·  LMB: place\\nScroll: raise/lower held part\""""
content = content.replace(orig_instr, new_instr)

with open("scripts/Main.gd", "w") as f:
    f.write(content)
print("Main.gd pickup logic patched")
