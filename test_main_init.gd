@tool
extends SceneTree

func _init():
    var main_scene = load("res://scenes/Main.tscn")
    var main = main_scene.instantiate()
    
    # Run _ready which calls _setup_order
    main._ready()
    
    print("Ghost Root is: ", main.ghost_root)
    if main.ghost_root:
        print("Ghost Pieces Count: ", main.blueprint_evaluator._ghost_pieces.size())
        print("Order: ", main._order.toy_name)
    quit()
