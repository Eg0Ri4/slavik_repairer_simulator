@tool
extends SceneTree

func _find_all_meshes(node: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    if node is MeshInstance3D:
        result.append(node)
    for child in node.get_children():
        result.append_array(_find_all_meshes(child))
    return result

func _init():
    var scene = load("res://scenes/ghosts/Ghost_skvorechnik.tscn")
    var inst = scene.instantiate()
    var meshes = _find_all_meshes(inst)
    print("Found ", meshes.size(), " meshes")
    quit()
