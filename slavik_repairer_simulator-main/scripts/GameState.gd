## GameState - Autoload singleton for global game state
extends Node

## Current tool: "tape" or "nail"
var active_tool: String = "tape"

## The part currently being held/dragged
var held_part: RigidBody3D = null

## Camera state
var camera_state: String = "TABLE_VIEW"  # or "UNDER_TABLE_VIEW"

## All parts attached to the assembly
var assembly_parts: Array[Node3D] = []

## Current order being worked on
var current_order: OrderData = null

## Signals
signal tool_changed(new_tool: String)
signal part_picked_up(part: RigidBody3D)
signal part_placed()
signal camera_state_changed(new_state: String)
signal nail_event(event_name: String, data: Variant)

func set_active_tool(tool_name: String) -> void:
	active_tool = tool_name
	tool_changed.emit(tool_name)

func pick_up_part(part: RigidBody3D) -> void:
	held_part = part
	part_picked_up.emit(part)

func place_part() -> void:
	held_part = null
	part_placed.emit()

func set_camera_state(new_state: String) -> void:
	camera_state = new_state
	camera_state_changed.emit(new_state)

func register_assembly_part(part: Node3D) -> void:
	if part not in assembly_parts:
		assembly_parts.append(part)

func clear_assembly() -> void:
	assembly_parts.clear()
