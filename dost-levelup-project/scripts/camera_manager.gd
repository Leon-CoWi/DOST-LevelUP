extends Node2D

@export var zoom_speed := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 20.0
@export var drag_speed := 1.0

# Smooth zoom options
@export var smooth_zoom := true
@export var zoom_lerp_speed := 8.0

# Optional pan limits
@export var limit_panning := true
var pan_limits: Rect2 = Rect2(-10000, -10000, 20000, 20000) # Internal; derived from edges
@export_group("Pan Limits (World Coordinates)")
@export var limit_left := -1000.0  ## How far left the camera can pan (negative X)
@export var limit_top := -1000.0   ## How far up the camera can pan (negative Y)
@export var limit_right := 3800.0  ## How far right the camera can pan (positive X)
@export var limit_bottom := 2000.0 ## How far down the camera can pan (positive Y)
@export var pan_margin := 0.0      ## Extra slack (in world units) allowed beyond edges
@export var debug_limits := false  ## Print computed clamp values every frame
@export var auto_bounds := false   ## Derive limits from listed nodes' global rects at startup
@export var bounds_nodes: Array[NodePath] = [] ## Nodes used to compute world bounds (Control/Node2D)
@export var pan_padding := 0.0     ## Extra padding added around computed auto bounds (world units)

var dragging := false
var drag_delta := Vector2.ZERO
var target_zoom := 1.0
var zoom_anchor_position := Vector2.ZERO  # World position to zoom towards

@onready var camera := get_node_or_null("Camera2D") as Camera2D

func _ready() -> void:
	if camera == null:
		push_error("camera_manager.gd: Camera2D node not found as child. Make sure a Camera2D named 'Camera2D' is a child of this node.")
		return
	if auto_bounds and bounds_nodes.size() > 0:
		_auto_set_limits_from_nodes()
	else:
		_rebuild_pan_limits()

	target_zoom = camera.zoom.x

func _rebuild_pan_limits() -> void:
	# Build the internal Rect2 from the exported edges for clarity in the Inspector
	var width = limit_right - limit_left
	var height = limit_bottom - limit_top
	if width > 0.0 and height > 0.0:
		pan_limits = Rect2(limit_left, limit_top, width, height)
		print("[Camera] Pan limits set: Left=%.1f, Top=%.1f, Right=%.1f, Bottom=%.1f" % [limit_left, limit_top, limit_right, limit_bottom])
		print("[Camera] Pan area size: %.1f x %.1f" % [width, height])

func _auto_set_limits_from_nodes() -> void:
	var first := true
	var min_x := 0.0
	var min_y := 0.0
	var max_x := 0.0
	var max_y := 0.0
	for p in bounds_nodes:
		var n = get_node_or_null(p)
		if n == null:
			continue
		if n is Control:
			var r: Rect2 = (n as Control).get_global_rect()
			if first:
				min_x = r.position.x
				min_y = r.position.y
				max_x = r.position.x + r.size.x
				max_y = r.position.y + r.size.y
				first = false
			else:
				min_x = min(min_x, r.position.x)
				min_y = min(min_y, r.position.y)
				max_x = max(max_x, r.position.x + r.size.x)
				max_y = max(max_y, r.position.y + r.size.y)
		elif n is Node2D:
			var gp: Vector2 = (n as Node2D).global_position
			if first:
				min_x = gp.x
				min_y = gp.y
				max_x = gp.x
				max_y = gp.y
				first = false
			else:
				min_x = min(min_x, gp.x)
				min_y = min(min_y, gp.y)
				max_x = max(max_x, gp.x)
				max_y = max(max_y, gp.y)
	if not first:
		# Apply padding
		min_x -= pan_padding
		min_y -= pan_padding
		max_x += pan_padding
		max_y += pan_padding
		limit_left = min_x
		limit_top = min_y
		limit_right = max_x
		limit_bottom = max_y
		_rebuild_pan_limits()

func _input(event: InputEvent) -> void:
	if camera == null:
		return

	if event is InputEventMouseMotion and dragging:
		# scale drag by zoom so pan speed feels consistent across zoom levels
		drag_delta = event.relative * drag_speed * camera.zoom.x
		camera.position -= drag_delta
		_apply_pan_limits()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# zoom in towards mouse position
			_zoom_at_point(event.position, target_zoom + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# zoom out from mouse position
			_zoom_at_point(event.position, target_zoom - zoom_speed)

# Catch releases that might be consumed elsewhere
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			dragging = false

func _process(delta: float) -> void:
	if camera == null:
		return
	# Safety: if release wasn't received, sync dragging with actual mouse state
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		dragging = false
	if smooth_zoom:
		var t: float = clamp(zoom_lerp_speed * delta, 0.0, 1.0)
		camera.zoom = camera.zoom.lerp(Vector2.ONE * target_zoom, t)
	else:
		camera.zoom = Vector2.ONE * target_zoom
	# Re-apply pan limits after zoom changes so viewport stays inside bounds
	_apply_pan_limits()

func _update_target_zoom(new_zoom: float) -> void:
	# compute dynamic allowed upper zoom based on pan_limits and viewport so we don't zoom out past border
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if limit_panning and viewport_size.x > 0 and viewport_size.y > 0:
		var max_x: float = pan_limits.size.x / viewport_size.x
		var max_y: float = pan_limits.size.y / viewport_size.y
		var dynamic_max: float = min(max_x, max_y)
		# Allow user to zoom in beyond dynamic limit for closer inspection
		# Only apply dynamic_max to prevent zooming OUT too far
		var final_upper: float = max_zoom
		var final_lower: float = min(min_zoom, dynamic_max)
		target_zoom = clamp(new_zoom, final_lower, final_upper)
	else:
		target_zoom = clamp(new_zoom, min_zoom, max_zoom)

func _zoom_at_point(mouse_pos: Vector2, new_zoom: float) -> void:
	# Get the world position under the mouse BEFORE zoom
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse_world_pos_before: Vector2 = camera.position + (mouse_pos - viewport_size * 0.5) / camera.zoom.x
	
	# Update the target zoom
	_update_target_zoom(new_zoom)
	
	# Calculate what the world position under mouse would be AFTER zoom with current camera position
	var mouse_world_pos_after: Vector2 = camera.position + (mouse_pos - viewport_size * 0.5) / target_zoom
	
	# Adjust camera position to keep the world point under the mouse cursor
	camera.position += mouse_world_pos_before - mouse_world_pos_after
	
	# Apply pan limits to ensure we stay in bounds
	_apply_pan_limits()

func _apply_pan_limits() -> void:
	if not limit_panning or camera == null:
		return
	
	# When zoomed in significantly (zoom > 2.0), disable pan limits to allow full exploration
	if camera.zoom.x > 2.0:
		return
	
	# Size of the viewport (screen) in pixels
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	# Half size of the visible area in WORLD units.
	# In Godot, larger zoom values show a smaller world area, so divide by zoom.
	var zoom_scalar: float = max(camera.zoom.x, 0.0001)
	var half_view: Vector2 = (viewport_size * 0.5) / zoom_scalar

	# World bounds (pan_limits) min and max center positions that keep the viewport inside the world
	var margin_vec := Vector2(pan_margin, pan_margin)
	var world_min_center: Vector2 = pan_limits.position + half_view - margin_vec
	var world_max_center: Vector2 = pan_limits.position + pan_limits.size - half_view + margin_vec

	# Only apply limits if the view is smaller than the world bounds
	# When zoomed in far enough, allow free panning within the entire world area
	if pan_limits.size.x > half_view.x * 2.0:
		camera.position.x = clamp(camera.position.x, world_min_center.x, world_max_center.x)
	else:
		# When zoomed in, just keep camera center within the world bounds
		camera.position.x = clamp(camera.position.x, pan_limits.position.x, pan_limits.position.x + pan_limits.size.x)

	if pan_limits.size.y > half_view.y * 2.0:
		camera.position.y = clamp(camera.position.y, world_min_center.y, world_max_center.y)
	else:
		# When zoomed in, just keep camera center within the world bounds
		camera.position.y = clamp(camera.position.y, pan_limits.position.y, pan_limits.position.y + pan_limits.size.y)

	if debug_limits:
		print("[Camera] half_view=", half_view, " min_center=", world_min_center, " max_center=", world_max_center, " cam_pos=", camera.position)
