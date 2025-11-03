extends AnimatedSprite2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Play disaster sound if AudioStreamPlayer2D exists
	if has_node("AudioStreamPlayer2D"):
		$AudioStreamPlayer2D.play()
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
