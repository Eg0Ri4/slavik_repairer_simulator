import re

with open('/home/eho/repairer/scenes/Main.tscn', 'r') as f:
    content = f.read()

# Replace Camera3D with GameCamera
content = content.replace('[node name="Camera3D" type="Camera3D" parent="CameraController"', '[node name="GameCamera" type="Camera3D" parent="CameraController"')

# Insert MenuCamera right before GameCamera
menu_cam = """[node name="MenuCamera" type="Camera3D" parent="CameraController" unique_id=1895147347]
transform = Transform3D(0.9006695, 0.22540972, -0.3714632, -0.30724123, 0.9349047, -0.17763859, 0.30724123, 0.27412248, 0.91129535, -0.73227286, -0.3474198, -0.7686384)
current = true
fov = 60.0
far = 100.0

"""

content = content.replace('[node name="GameCamera"', menu_cam + '[node name="GameCamera"')

with open('/home/eho/repairer/scenes/Main.tscn', 'w') as f:
    f.write(content)

