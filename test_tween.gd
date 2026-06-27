extends SceneTree
func _init():
    var node = Node.new()
    root.add_child(node)
    var tw = node.create_tween()
    tw.tween_interval(0.1)
    tw.finished.connect(func(): print("Tween finished!"), CONNECT_ONE_SHOT)
    
    var t2 = root.get_tree().create_timer(0.5)
    t2.timeout.connect(func(): quit())
