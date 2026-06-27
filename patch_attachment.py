with open("scripts/AttachmentSystem.gd", "r") as f:
    content = f.read()

orig = """		if child is Joint3D:
			var joint := child as Joint3D
			var body_a: PhysicsBody3D = joint.get_node_or_null(joint.node_a) if joint.node_a else null"""

new = """		if child is Joint3D:
			var joint := child as Joint3D
			if joint.is_queued_for_deletion():
				continue
			var body_a: PhysicsBody3D = joint.get_node_or_null(joint.node_a) if joint.node_a else null"""
content = content.replace(orig, new)

orig2 = """		if child is Joint3D:
			var joint := child as Joint3D
			var body_a: PhysicsBody3D = joint.get_node_or_null(joint.node_a) if joint.node_a else null"""
content = content.replace(orig2, new)

with open("scripts/AttachmentSystem.gd", "w") as f:
    f.write(content)
print("AttachmentSystem.gd patched")
