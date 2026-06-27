extends SceneTree
func _init():
    var main = preload("res://scenes/Main.tscn").instantiate()
    root.add_child(main)
    var menu = main.get_node("MenuController")
    if menu:
        print("Menu found, calling _on_start")
        menu._on_start()
    else:
        print("Menu NOT found")
    quit()
