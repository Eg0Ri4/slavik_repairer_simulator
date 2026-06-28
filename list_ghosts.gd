@tool
extends SceneTree

func _init():
    var dir = DirAccess.open("res://scenes/ghosts")
    if dir:
        dir.list_dir_begin()
        var f = dir.get_next()
        while f != "":
            if f.ends_with(".tscn"):
                print(f)
            f = dir.get_next()
    quit()
