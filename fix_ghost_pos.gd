@tool
extends SceneTree

func _init():
    var scene = ResourceLoader.load("res://scenes/Main.tscn")
    var root = scene.instantiate()
    var table = root.get_node("TableStaticBody")
    var col = table.get_node("CollisionShape3D")
    var ghost = root.get_node("AssemblyPivot/GhostBlueprint")
    var pivot = root.get_node("AssemblyPivot")
    
    var world_center = table.global_transform * col.transform.origin
    # The box shape size is col.shape.size. Y scale of table is table.global_transform.basis.y.length()
    var top_y = world_center.y + (col.shape.size.y / 2.0) * table.global_transform.basis.y.length()
    
    var target_world_pos = Vector3(world_center.x, top_y, world_center.z)
    
    # We want ghost.global_transform.origin = target_world_pos
    # It's parented to pivot, so local_pos = pivot.global_transform.affine_inverse() * target_world_pos
    var local_pos = pivot.global_transform.affine_inverse() * target_world_pos
    
    print("New Local Pos: ", local_pos)
    ghost.transform.origin = local_pos
    
    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://scenes/Main.tscn")
    quit()
