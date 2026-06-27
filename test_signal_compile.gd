extends SceneTree
func _init():
    var script = GDScript.new()
    script.source_code = "extends Node\nsignal game_started\n"
    script.reload()
    var n : Node = script.new()
    print("Testing connect...")
    n.game_started.connect(func(): pass)
    print("Success")
    quit()
