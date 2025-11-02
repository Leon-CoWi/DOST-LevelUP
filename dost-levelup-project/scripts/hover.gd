extends PanelContainer

var opacity_tween: Tween = null
# Offset up and slightly to the right of cursor
var mouse_offset = Vector2(-10, -120)  # x=15 pixels right, y=-100 pixels up

func _ready() -> void:
	# Start hidden
	modulate.a = 0.0
	hide()

func get_mouse_position() -> Vector2:
	# Get the canvas transform (handles zoom)
	var canvas = get_canvas_transform()
	# Get the viewport mouse position
	var viewport_mouse_pos = get_viewport().get_mouse_position()
	# Convert viewport position to canvas position
	var canvas_mouse_pos = (viewport_mouse_pos - canvas.origin) / canvas.get_scale()
	return canvas_mouse_pos

func _process(_delta: float) -> void:
	if visible:
		# Update position using canvas-aware mouse position
		position = get_mouse_position() + mouse_offset

func toggle(on: bool) -> void:
	if opacity_tween and opacity_tween.is_valid():
		opacity_tween.kill()
	
	if on:
		# Show immediately then fade in
		show()
		modulate.a = 0.0
		position = get_mouse_position() + mouse_offset
		tween_opacity(1.0)
	else:
		# Fade out then hide
		tween_opacity(0.0)
		await get_tree().create_timer(0.3).timeout
		hide()

func tween_opacity(to: float) -> Tween:
	opacity_tween = create_tween()
	opacity_tween.tween_property(self, "modulate:a", to, 0.3)
	return opacity_tween
