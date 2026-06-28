@tool
extends SceneTree

func _init():
    var factory = load("res://scripts/GhostBlueprintFactory.gd")
    var gb = load("res://scripts/GhostBlueprint.gd").new()
    gb.ghost_model = load("res://assets/models/boxA/plank1.glb")
    var preview = gb.ghost_model.instantiate()
    gb.add_child(preview)
    var sf = gb._compute_scale_factor(preview)
    var aabb = gb._compute_total_aabb(preview)
    print("AABB size: ", aabb.size * sf)
    quit()
