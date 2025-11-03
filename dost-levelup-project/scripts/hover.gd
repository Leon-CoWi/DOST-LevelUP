extends PanelContainer

var opacity_tween: Tween = null
# Offset up and slightly to the right of cursor
var mouse_offset = Vector2(15, -50)  # x=15 pixels right, y=-50 pixels up

func _ready() -> void:
	# Make this Control render in screen space, ignoring parent transforms
	top_level = true
	# Prevent tooltip from blocking mouse events to plot slots below
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Render above everything else
	z_index = 100
	
	# Ensure minimum size so tooltip is visible
	custom_minimum_size = Vector2(150, 100)
	
	# Start hidden
	modulate.a = 0.0
	hide()
	
	print("[Hover] Tooltip initialized with top_level=true, z_index=100")

func _process(_delta: float) -> void:
	if visible:
		# Get mouse position in viewport (screen) coordinates
		var viewport_mouse_pos = get_viewport().get_mouse_position()
		# Convert to canvas coordinates (accounts for camera zoom/pan)
		var canvas_transform = get_canvas_transform()
		var canvas_mouse_pos = canvas_transform.affine_inverse() * viewport_mouse_pos
		# Set global position (bypasses parent transforms because top_level=true)
		global_position = canvas_mouse_pos + mouse_offset

func toggle(on: bool) -> void:
	if opacity_tween and opacity_tween.is_valid():
		opacity_tween.kill()
	
	if on:
		# Show immediately then fade in
		show()
		modulate.a = 0.0
		# Position at mouse in canvas space
		var viewport_mouse_pos = get_viewport().get_mouse_position()
		var canvas_transform = get_canvas_transform()
		var canvas_mouse_pos = canvas_transform.affine_inverse() * viewport_mouse_pos
		global_position = canvas_mouse_pos + mouse_offset
		print("[Hover] Showing tooltip at global_position: ", global_position, " (viewport mouse: ", viewport_mouse_pos, ")")
		tween_opacity(1.0)
	else:
		# Fade out then hide
		print("[Hover] Hiding tooltip")
		tween_opacity(0.0)
		if get_tree():
			await get_tree().create_timer(0.3).timeout
			hide()

func tween_opacity(to: float) -> Tween:
	opacity_tween = create_tween()
	opacity_tween.tween_property(self, "modulate:a", to, 0.3)
	return opacity_tween
