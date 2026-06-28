@tool
extends SceneTree

func _init():
    var main_scene = load("res://scenes/Main.tscn")
    var main = main_scene.instantiate()
    
    # Run _ready which calls _setup_order
    main._ready()
    
    print("First Ghost: ", main.ghost_root)
    
    # Simulate pressing reset
    main._on_reset_pressed()
    
    print("Second Ghost: ", main.ghost_root)
    
    quit()
