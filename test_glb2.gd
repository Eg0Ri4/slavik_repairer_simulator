extends SceneTree
func _init():
    var scene = load("res://assets/models/boxglb.glb")
    var inst = scene.instantiate()
    print("Root: ", inst.name, " type: ", inst.get_class())
    for child in inst.get_children():
        print(" Child: ", child.name, " type: ", child.get_class())
        if child is MeshInstance3D:
            print("  Transform: ", child.transform)
    quit()
