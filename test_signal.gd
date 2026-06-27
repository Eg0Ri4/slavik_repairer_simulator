extends SceneTree
func _init():
    var node = Node.new()
    var script = GDScript.new()
    script.source_code = "extends Node\nsignal game_started\n"
    script.reload()
    node.set_script(script)
    print("has_signal: ", node.has_signal("game_started"))
    quit()
