@tool
class_name ItemData
extends Resource

## Name shown in UI
@export var item_name: String = "Unknown Part"

## Semantic tags used for evaluation (e.g. ["blade", "motor", "frame"])
@export var tags: Array = []

## Visual color of this item (used for CSG mesh material)
@export var item_color: Color = Color(0.6, 0.6, 0.7)

## Size multiplier for the CSG primitive
@export var size: Vector3 = Vector3(0.2, 0.2, 0.2)

## Shape type: "box", "cylinder", "sphere"
@export var shape_type: String = "box"
