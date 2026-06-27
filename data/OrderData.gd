@tool
class_name OrderData
extends Resource

## ── Toy Identity ────────────────────────────────────────────────────────────
## Human-readable name for this toy/repair job (shown as order title)
@export var toy_name: String = "Broken Fan"

## Flavor text describing the client's request
@export_multiline var client_description: String = "Fix this thing with junk!"

## ── Blueprint Silhouette ────────────────────────────────────────────────────
## Semi-transparent 2D texture overlaid on the viewport during evaluation.
## The EvaluationSystem raycasts through opaque pixels to score alignment.
@export var blueprint_silhouette: Texture2D = null

## Tags that a JunkPart must carry for a ray-hit to count as a valid match.
@export var required_component_tags: Array[String] = ["blade", "motor", "frame"]

## Minimum percentage (0-100) of matching score required to pass evaluation.
@export var pass_tolerance: float = 80.0

## ── Legacy Requirements (kept for backward compatibility) ───────────────────
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

## Maximum distance in units for a tag to count as "in position" (legacy eval)
@export var tolerance: float = 0.5
