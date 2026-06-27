extends SceneTree
func _init():
    var main = preload("res://scenes/Main.tscn").instantiate()
    root.add_child(main)
    # create timer
    var timer = root.get_tree().create_timer(1.0)
    timer.timeout.connect(_on_timeout.bind(main))
func _on_timeout(main):
    var menu = main.get_node("MenuController")
    var btn = menu.get_node("MenuRoot").get_child(0).get_child(0).get_child(1)
    print("Found button: ", btn.text)
    btn.pressed.emit()
    var t2 = root.get_tree().create_timer(2.0)
    t2.timeout.connect(func(): quit())
