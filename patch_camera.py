with open("scripts/CameraController.gd", "r") as f:
    content = f.read()

orig_orbit = """	elif event is InputEventMouseMotion and _rmb_down:
		if _pivot:
			var d: Vector2 = event.position - _last_mouse
			_last_mouse = event.position
			_pivot.rotate_y(deg_to_rad(-d.x * pivot_sensitivity))
			_pivot.rotate_x(deg_to_rad(-d.y * pivot_sensitivity * 0.5))"""

new_orbit = """	elif event is InputEventMouseMotion and _rmb_down:
		pass # Orbit assembly disabled per user request"""

content = content.replace(orig_orbit, new_orbit)

with open("scripts/CameraController.gd", "w") as f:
    f.write(content)
print("CameraController patched")
