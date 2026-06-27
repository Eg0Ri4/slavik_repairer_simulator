extends SceneTree
func _init():
    var main = Node.new()
    var camera_controller = load("res://scripts/CameraController.gd").new()
    main.add_child(camera_controller)
    var menu_controller = load("res://scripts/MenuController.gd").new()
    main.add_child(menu_controller)
    
    # Try to find by signal
    var found = null
    for child in main.get_children():
        if child.has_signal("game_started"):
            found = child
            break
    print("Found MenuController: ", found != null)
    quit()
