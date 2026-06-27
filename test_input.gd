extends SceneTree
func _init():
    var main = preload("res://scenes/Main.tscn").instantiate()
    root.add_child(main)
    # Wait 2 frames
    await root.get_tree().process_frame
    await root.get_tree().process_frame
    print("Injecting mouse click...")
    var ev = InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = true
    ev.position = Vector2(500, 300) # center of screen
    root.get_viewport().push_input(ev)
    
    await root.get_tree().process_frame
    var menu = main.get_node_or_null("MenuController")
    if menu:
        print("Menu visible: ", menu.get_node("MenuRoot").visible)
    else:
        print("Menu not found")
    quit()
