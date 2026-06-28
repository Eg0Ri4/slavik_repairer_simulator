extends SceneTree
func _init():
    var scene = load("res://assets/models/boxglb.glb")
    var inst = scene.instantiate()
    var meshes = []
    
    var queue = [inst]
    while queue.size() > 0:
        var curr = queue.pop_front()
        if curr is MeshInstance3D:
            meshes.append(curr)
        queue.append_array(curr.get_children())
        
    for m in meshes:
        var aabb = m.get_aabb()
        print("Mesh: ", m.name, " AABB Pos: ", aabb.position, " Size: ", aabb.size)
    quit()
