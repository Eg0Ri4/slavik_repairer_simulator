## SilhouetteChecker.gd
## Self-contained 3-view silhouette comparison system.
##
## Spawns 3 orthogonal SubViewports + Camera3Ds, captures silhouette images
## of a reference PackedScene and the player's assembled Node3D, then scores
## the match using pixel Intersection-over-Union (IoU).
##
## RULE: No part IDs, node names, or tag matching — purely visual shape check.
class_name SilhouetteChecker
extends Node

# ── Configuration ────────────────────────────────────────────────────────────

## Minimum IoU score (0-1) to pass. 0.55 = forgiving for janky repairs.
@export var min_pass_score: float = 0.55

## Resolution of each silhouette capture viewport (square).
@export var capture_resolution: int = 256

## Visual layer used to isolate the captured object (all other objects invisible).
const ISOLATION_LAYER: int = 10  # bit index (0-based → layer 11 in editor UI)

## Padding multiplier for AABB → ortho size (1.1 = 10% margin).
const AABB_PADDING: float = 1.15

# ── Camera directions (unit vectors) ─────────────────────────────────────────
# Each entry: [camera_position_direction, camera_up_vector]
const VIEW_DIRS: Array = [
	[Vector3(0, 0, 1),  Vector3(0, 1, 0)],   # Front
	[Vector3(1, 0, 0),  Vector3(0, 1, 0)],   # Side (right)
	[Vector3(0, 1, 0),  Vector3(0, 0, -1)],  # Top
]

# ── Public API ───────────────────────────────────────────────────────────────

## Main entry point. Call with the player's assembled Node3D and the OrderData.
## Returns a Dictionary:
##   {
##     "passed": bool,
##     "score": float,            # 0.0 – 1.0
##     "per_view": [float, float, float],  # IoU per view
##     "grade": String,
##   }
func check(player_assembly: Node3D, order: OrderData) -> Dictionary:
	if order.reference_model == null:
		push_warning("SilhouetteChecker: No reference_model on order '%s'" % order.order_name)
		return {"passed": false, "score": 0.0, "per_view": [0.0, 0.0, 0.0], "grade": "NO REFERENCE"}

	# ── Build the viewport rig ───────────────────────────────────────────
	var rig := _build_viewport_rig()
	add_child(rig.root)

	# We must wait one frame for viewports to initialize
	await get_tree().process_frame

	# ── Capture reference silhouettes ────────────────────────────────────
	var ref_images: Array[Image] = await _capture_reference(rig, order.reference_model)

	# ── Capture player silhouettes ───────────────────────────────────────
	var player_images: Array[Image] = await _capture_player(rig, player_assembly)

	# ── Tear down the rig ────────────────────────────────────────────────
	rig.root.queue_free()

	# ── Compute IoU per view ─────────────────────────────────────────────
	var per_view: Array[float] = []
	for i in range(3):
		var iou := _compute_iou(ref_images[i], player_images[i])
		per_view.append(iou)

	# Average the 3 views
	var total_score: float = (per_view[0] + per_view[1] + per_view[2]) / 3.0
	var passed: bool = total_score >= min_pass_score

	return {
		"passed": passed,
		"score": total_score,
		"per_view": per_view,
		"grade": _grade(total_score),
	}


# ── Viewport Rig Construction ────────────────────────────────────────────────

## Internal struct-like dictionary returned by _build_viewport_rig().
## Keys: root, viewports (Array[SubViewport]), cameras (Array[Camera3D]),
##        world (World3D)

func _build_viewport_rig() -> Dictionary:
	var root := Node.new()
	root.name = "SilhouetteRig"

	# Shared isolated World3D so nothing from the main scene leaks in
	var world := World3D.new()

	# One DirectionalLight3D to ensure meshes are visible (flat white)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.0
	light.rotation_degrees = Vector3(-45, 45, 0)
	# light will be added to first viewport so it exists in the shared world

	var viewports: Array[SubViewport] = []
	var cameras: Array[Camera3D] = []

	for i in range(3):
		var vp := SubViewport.new()
		vp.name = "SilVP_%d" % i
		vp.size = Vector2i(capture_resolution, capture_resolution)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.transparent_bg = true
		vp.world_3d = world
		vp.own_world_3d = false
		# Disable MSAA/shadows for clean silhouette
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		root.add_child(vp)

		var cam := Camera3D.new()
		cam.name = "SilCam_%d" % i
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.current = true
		# Cull mask: ONLY isolation layer
		cam.cull_mask = 1 << ISOLATION_LAYER
		vp.add_child(cam)

		viewports.append(vp)
		cameras.append(cam)

	# Add the light to the shared world via the first viewport
	viewports[0].add_child(light)

	return {
		"root": root,
		"viewports": viewports,
		"cameras": cameras,
		"world": world,
	}


# ── Reference Capture ────────────────────────────────────────────────────────

func _capture_reference(rig: Dictionary, ref_scene: PackedScene) -> Array[Image]:
	var viewports: Array[SubViewport] = []
	for vp in rig.viewports:
		viewports.append(vp as SubViewport)
	var cameras: Array[Camera3D] = []
	for cam in rig.cameras:
		cameras.append(cam as Camera3D)

	# Instantiate reference model inside the first viewport (shares the world)
	var instance: Node3D = ref_scene.instantiate() as Node3D
	viewports[0].add_child(instance)

	# Force all meshes to isolation layer
	_set_visual_layer_recursive(instance, 1 << ISOLATION_LAYER)

	# Center the model at origin
	var aabb := _get_combined_aabb(instance)
	var center := aabb.get_center()
	instance.global_position -= center

	# Recalculate AABB after centering
	aabb = _get_combined_aabb(instance)

	# Frame cameras
	_frame_cameras(cameras, aabb)

	# Render & capture
	var images: Array[Image] = await _render_and_capture(viewports)

	# Clean up
	instance.queue_free()
	# Wait for the free to process
	await get_tree().process_frame

	return images


# ── Player Capture ───────────────────────────────────────────────────────────

func _capture_player(rig: Dictionary, player_assembly: Node3D) -> Array[Image]:
	var viewports: Array[SubViewport] = []
	for vp in rig.viewports:
		viewports.append(vp as SubViewport)
	var cameras: Array[Camera3D] = []
	for cam in rig.cameras:
		cameras.append(cam as Camera3D)

	# ── Save original state ──────────────────────────────────────────────
	var original_transform := player_assembly.global_transform
	var saved_layers: Dictionary = {}  # Node → int (original layers_mask)
	_save_visual_layers_recursive(player_assembly, saved_layers)

	# ── Duplicate player assembly into the rig's world ───────────────────
	# We duplicate instead of moving to avoid disrupting the player's scene.
	var clone: Node3D = player_assembly.duplicate() as Node3D
	viewports[0].add_child(clone)

	# Force to isolation layer
	_set_visual_layer_recursive(clone, 1 << ISOLATION_LAYER)

	# Center
	var aabb := _get_combined_aabb(clone)
	if aabb.size.length() < 0.001:
		# Fallback: no mesh geometry found — return blank images
		clone.queue_free()
		await get_tree().process_frame
		var blank: Array[Image] = []
		for i in range(3):
			var img := Image.create(capture_resolution, capture_resolution, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			blank.append(img)
		return blank

	var center := aabb.get_center()
	clone.global_position -= center

	# Recalculate
	aabb = _get_combined_aabb(clone)

	# Frame cameras
	_frame_cameras(cameras, aabb)

	# Render & capture
	var images: Array[Image] = await _render_and_capture(viewports)

	# Clean up clone
	clone.queue_free()
	await get_tree().process_frame

	return images


# ── Rendering ────────────────────────────────────────────────────────────────

func _render_and_capture(viewports: Array[SubViewport]) -> Array[Image]:
	# Request each viewport to render
	for vp in viewports:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Wait for RenderingServer to finish drawing
	await RenderingServer.frame_post_draw

	var images: Array[Image] = []
	for vp in viewports:
		var tex := vp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				images.append(img)
			else:
				var blank := Image.create(capture_resolution, capture_resolution, false, Image.FORMAT_RGBA8)
				images.append(blank)
		else:
			var blank := Image.create(capture_resolution, capture_resolution, false, Image.FORMAT_RGBA8)
			images.append(blank)

	return images


# ── Camera Framing ───────────────────────────────────────────────────────────

func _frame_cameras(cameras: Array[Camera3D], aabb: AABB) -> void:
	var size := aabb.size
	# The distance to place the camera from the center
	var max_extent: float = max(size.x, size.y, size.z) * AABB_PADDING

	for i in range(3):
		var cam := cameras[i]
		var dir: Vector3 = VIEW_DIRS[i][0]
		var up: Vector3 = VIEW_DIRS[i][1]

		# Position camera looking at origin from the direction
		var cam_pos: Vector3 = dir * (max_extent * 2.0)
		cam.global_position = cam_pos
		cam.look_at(Vector3.ZERO, up)

		# Set orthographic size to frame the object
		# The ortho size is HALF the vertical extent the camera sees
		match i:
			0:  # Front: sees X (width) and Y (height)
				cam.size = max(size.x, size.y) * AABB_PADDING
			1:  # Side: sees Z (depth) and Y (height)
				cam.size = max(size.z, size.y) * AABB_PADDING
			2:  # Top: sees X (width) and Z (depth)
				cam.size = max(size.x, size.z) * AABB_PADDING


# ── IoU Computation ──────────────────────────────────────────────────────────

## Computes Intersection-over-Union between two silhouette images.
## A pixel is "filled" if its alpha > threshold.
## PENALIZES extra player pixels outside the reference silhouette.
func _compute_iou(ref_img: Image, player_img: Image) -> float:
	var w := ref_img.get_width()
	var h := ref_img.get_height()

	if w != player_img.get_width() or h != player_img.get_height():
		# Resize player to match reference
		player_img.resize(w, h)

	var alpha_threshold: float = 0.1

	var intersection: int = 0
	var union_count: int = 0
	var ref_count: int = 0
	var player_count: int = 0

	for y in range(h):
		for x in range(w):
			var ref_filled: bool = ref_img.get_pixel(x, y).a > alpha_threshold
			var player_filled: bool = player_img.get_pixel(x, y).a > alpha_threshold

			if ref_filled:
				ref_count += 1
			if player_filled:
				player_count += 1
			if ref_filled and player_filled:
				intersection += 1
			if ref_filled or player_filled:
				union_count += 1

	if union_count == 0:
		return 0.0

	# Standard IoU already penalizes extra pixels because they inflate the union
	# without adding to the intersection. This naturally prevents the "blob exploit":
	# a giant ball covers all reference pixels (high intersection) but also has
	# massive extra pixels (huge union), tanking the score.
	var iou: float = float(intersection) / float(union_count)
	return iou


# ── Visual Layer Helpers ─────────────────────────────────────────────────────

func _set_visual_layer_recursive(node: Node, layer_mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer_mask
	if node is Light3D:
		(node as Light3D).light_cull_mask = layer_mask
	for child in node.get_children():
		_set_visual_layer_recursive(child, layer_mask)

func _save_visual_layers_recursive(node: Node, out: Dictionary) -> void:
	if node is VisualInstance3D:
		out[node] = (node as VisualInstance3D).layers
	for child in node.get_children():
		_save_visual_layers_recursive(child, out)

func _restore_visual_layers(saved: Dictionary) -> void:
	for node: Node in saved:
		if is_instance_valid(node) and node is VisualInstance3D:
			(node as VisualInstance3D).layers = saved[node]


# ── AABB Helpers ─────────────────────────────────────────────────────────────

func _get_combined_aabb(node: Node3D) -> AABB:
	return _collect_aabb_recursive(node)

func _collect_aabb_recursive(node: Node) -> AABB:
	var result := AABB()
	var has_any := false

	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var mesh_aabb := vi.get_aabb()
		# Transform to global space
		var global_aabb := vi.global_transform * mesh_aabb
		if not has_any:
			result = global_aabb
			has_any = true
		else:
			result = result.merge(global_aabb)

	for child in node.get_children():
		var child_aabb := _collect_aabb_recursive(child)
		if child_aabb.size.length() > 0.0001:
			if not has_any:
				result = child_aabb
				has_any = true
			else:
				result = result.merge(child_aabb)

	return result


# ── Grade Label ──────────────────────────────────────────────────────────────

func _grade(score: float) -> String:
	if score >= 0.85:
		return "MASTER CRAFTSMAN! 🏆"
	elif score >= 0.70:
		return "Looks about right! 👍"
	elif score >= 0.55:
		return "Close enough... 🤷"
	elif score >= 0.35:
		return "Squint and it works? 😬"
	elif score >= 0.15:
		return "What IS that? 🤔"
	else:
		return "That's modern art. 🎨"
