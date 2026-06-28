@tool
extends Node3D

var _child

func _ready():
	_child = MeshInstance3D.new()
	_child.mesh = BoxMesh.new()
	add_child(_child)
