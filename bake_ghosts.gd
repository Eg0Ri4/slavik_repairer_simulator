@tool
extends SceneTree

func _init():
    var factory = preload("res://scripts/GhostBlueprintFactory.gd").new()
    var dir = DirAccess.open("res://assets/models")
    if dir:
        DirAccess.make_dir_absolute("res://scenes/ghosts")
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if not dir.current_is_dir() and file_name.ends_with(".glb"):
                print("Processing ", file_name)
                var path = "res://assets/models/" + file_name
                var scene = ResourceLoader.load(path)
                if scene:
                    var ghost_root = factory.create_ghost_from_scene(scene)
                    if ghost_root:
                        # Make sure all nodes have owner set to root so they save
                        _set_owner(ghost_root, ghost_root)
                        var packed = PackedScene.new()
                        packed.pack(ghost_root)
                        var save_path = "res://scenes/ghosts/Ghost_" + file_name.replace(".glb", ".tscn")
                        ResourceSaver.save(packed, save_path)
                        ghost_root.queue_free()
            file_name = dir.get_next()
    print("Done")
    quit()

func _set_owner(node: Node, owner_node: Node):
    if node != owner_node:
        node.owner = owner_node
    for child in node.get_children():
        _set_owner(child, owner_node)
