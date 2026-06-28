@tool
extends EditorScript

## Run this script from the Godot Script Editor by clicking "File -> Run" (or Ctrl+Shift+X).
## It will recursively scan res://assets/models/ghosts/ for .glb files and export them
## as interactive ghost blueprint scenes (.tscn) into res://scenes/ghosts/

func _run() -> void:
	print("--- Starting Ghost Export ---")
	var factory = preload("res://scripts/GhostBlueprintFactory.gd").new()
	var to_process: Array[String] = ["res://assets/models/ghosts"]
	
	DirAccess.make_dir_absolute("res://scenes/ghosts")
	
	var count: int = 0
	while to_process.size() > 0:
		var dir_path: String = to_process.pop_back()
		var dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name == "." or file_name == "..":
					pass
				elif dir.current_is_dir():
					to_process.push_back(dir_path + "/" + file_name)
				elif file_name.ends_with(".glb"):
					var path = dir_path + "/" + file_name
					print("Exporting ghost from: ", path)
					
					var scene = ResourceLoader.load(path)
					if scene:
						var ghost_root = factory.create_ghost_from_scene(scene)
						if ghost_root:
							_set_owner(ghost_root, ghost_root)
							var packed = PackedScene.new()
							packed.pack(ghost_root)
							
							var save_name = file_name.replace(".glb", ".tscn")
							var save_path = "res://scenes/ghosts/Ghost_" + save_name
							ResourceSaver.save(packed, save_path)
							
							ghost_root.queue_free()
							count += 1
				file_name = dir.get_next()
	
	print("--- Ghost Export Complete ---")
	print("Successfully exported ", count, " ghosts to res://scenes/ghosts/")

## Ensures all dynamically generated nodes are saved into the .tscn file
func _set_owner(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		_set_owner(child, owner_node)
