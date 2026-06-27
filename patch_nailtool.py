with open("scripts/NailTool.gd", "r") as f:
    content = f.read()

orig_signals = """signal nail_placement_blocked(reason: String)"""
new_signals = """signal nail_placement_blocked(reason: String)
signal tape_removed()"""
content = content.replace(orig_signals, new_signals)

orig_remove_tape = """	if is_instance_valid(mesh):
		mesh.queue_free()
		
	# Trigger the UI feedback text for crowbar (it checks for 0 progress)
	nail_strike_performed.emit(0.0)"""

new_remove_tape = """	if is_instance_valid(mesh):
		mesh.queue_free()
		
	tape_removed.emit()
	# Trigger the UI feedback text for crowbar (it checks for 0 progress)
	nail_strike_performed.emit(0.0)"""
content = content.replace(orig_remove_tape, new_remove_tape)

with open("scripts/NailTool.gd", "w") as f:
    f.write(content)
print("NailTool.gd patched")
