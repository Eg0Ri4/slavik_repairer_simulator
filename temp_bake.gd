@tool
extends SceneTree

func _init():
    var script = load("res://scripts/tools/BakeGhostsTool.gd").new()
    script._run()
    quit()
