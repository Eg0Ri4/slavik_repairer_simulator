@tool
class_name OrderData
extends Resource

## Human-readable name for this order/repair job
@export var order_name: String = "Broken Fan"

## Description shown to player
@export var description: String = "Fix this thing with junk!"

## Array of target requirements.
## Each dict must have:
##   required_tag: String  - the tag a part must have
##   target_position: Vector3 - where (in AssemblyPivot local space) it should end up
##   points: int           - points awarded for meeting this requirement
@export var requirements: Array[Dictionary] = [
	{
		"required_tag": "blade",
		"target_position": Vector3(0.0, 0.3, 0.0),
		"points": 100
	},
	{
		"required_tag": "motor",
		"target_position": Vector3(0.0, 0.0, 0.0),
		"points": 150
	},
	{
		"required_tag": "frame",
		"target_position": Vector3(0.0, -0.2, 0.0),
		"points": 80
	}
]

## Maximum distance in units for a tag to count as "in position"
@export var tolerance: float = 0.5
