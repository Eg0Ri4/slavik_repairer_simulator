@tool
extends SceneTree

func _init():
    var factory = preload("res://scripts/GhostBlueprintFactory.gd").new()
    var scene = ResourceLoader.load("res://assets/models/skvorechnik.glb")
    var ghost_root = factory.create_ghost_from_scene(scene)
    
    var pivot = Node3D.new()
    pivot.add_child(ghost_root)
    
    var eval = preload("res://scripts/BlueprintEvaluator.gd").new()
    eval.set_ghost_root(ghost_root)
    
    var part = preload("res://scripts/JunkPart.gd").new()
    part.name = "TestPart"
    
    var item_data = preload("res://scripts/ItemData.gd").new()
    part.setup(item_data)
    
    pivot.add_child(part)
    # move part to overlap
    part.global_position = Vector3(0,0,0)
    
    var res = eval.evaluate(pivot)
    print("Eval result: ", res)
    quit()
