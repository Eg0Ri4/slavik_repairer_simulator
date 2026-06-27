extends SceneTree
var frames = 0
var main
func _init():
    main = preload("res://scenes/Main.tscn").instantiate()
    root.add_child(main)
func _process(delta):
    frames += 1
    if frames == 10:
        var ev = InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = true
        # Use center of the viewport
        ev.position = root.get_viewport().get_visible_rect().size / 2
        root.get_viewport().push_input(ev)
        print("INJECTED CLICK at ", ev.position)
    if frames == 20:
        var ev2 = InputEventMouseButton.new()
        ev2.button_index = MOUSE_BUTTON_LEFT
        ev2.pressed = false
        ev2.position = root.get_viewport().get_visible_rect().size / 2
        root.get_viewport().push_input(ev2)
        print("INJECTED RELEASE at ", ev2.position)
    if frames == 40:
        var menu = main.get_node_or_null("MenuController")
        if menu:
            print("Menu visible: ", menu.get_node("MenuRoot").visible)
            print("Camera transitioning: ", GameState.camera_state)
        quit()
