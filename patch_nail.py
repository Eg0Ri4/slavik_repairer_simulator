with open("scripts/Nail.gd", "r") as f:
    content = f.read()

orig_signal = "signal nail_fastened()"
new_signal = "signal nail_fastened()\nsignal nail_unfastened()"
content = content.replace(orig_signal, new_signal)

orig_unfasten = """func _unfasten() -> void:
	if _is_fastened:
		_is_fastened = false
		_break_joint()
	queue_free()"""

new_unfasten = """func _unfasten() -> void:
	if _is_fastened:
		_is_fastened = false
		_break_joint()
		nail_unfastened.emit()
	queue_free()"""
content = content.replace(orig_unfasten, new_unfasten)

with open("scripts/Nail.gd", "w") as f:
    f.write(content)
print("Nail.gd patched")
