extends AnimatedSprite2D

class_name SC

@export var max_hp: int = 1250
var hp: int
var health_bar 
var hp_not_init = true

# 1 is full damage, if they resist will be lower
var fire_resistance = 1 
var wind_resistance = 1
var water_resistance = 1
var sturdiness = 1 #earthquake/disruption res
var smart_center_res = 1
var attack = 0
var production_rate = 0
var energy_consumption = 0
var plot_index = [0,0] #this is the index of the current building
var disabled = false 
var disable_timer = 0
var inactive = false

#var level = 0
@export var damage_popup_scene: PackedScene
var popup

var owner_peer_id: int = 0

signal destroyed(owner_peer_id)

func _ready():
	hp = max_hp

	# Find the health bar safely
	if get_parent().board_owner == "player":
		health_bar = get_parent().get_parent().get_parent().get_parent().get_node("CanvasLayer/PlayerHealthbar")
	else:
		health_bar = get_parent().get_parent().get_parent().get_parent().get_node("CanvasLayer/OpponentHealthbar")

	# Initialize if it exists
	if health_bar:
		if health_bar.has_method("init_health"):
			health_bar.init_health(max_hp)
		health_bar.value = hp
	else:
		push_warning("⚠️ No Healthbar found in " + str(name))
	
	if $AudioStreamPlayer2D:
		$AudioStreamPlayer2D.play()

func blackout():
	await get_tree().create_timer(1).timeout
	take_damage(10, "true")
	disabled = true
	disable_timer = 10.0

	# Start a tween to fade to dark gray
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate", Color(0.2, 0.2, 0.2, 1.0), 1.0) # fade to dark over 1s

	# Wait for the 10s blackout duration
	tween.tween_interval(10.0)

	# Fade back to normal brightness over 1s
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 1.0)

	# When the tween completes, re-enable building
	tween.finished.connect(func ():
		disabled = false
		disable_timer = 0
	)



func _process(delta):
	if inactive:
		return
		
	if disabled:
		disable_timer -= delta
		if disable_timer <= 0:
			disabled = false
			modulate = Color(1,1,1,1)
		return
		
	trigger_effect(delta)


func trigger_effect(delta):
	pass

func take_damage(amount: int, damage_type: String) -> void:
	if inactive:
		return
	#sc takes damage uniquely as its resistance doesnt affect damage taken
	print("Taking damage:", amount, "type:", damage_type, "HP before:", hp)
	#for each active building, reduce damage by 4%
	smart_center_res = 1 - (get_parent().get_parent().get_parent().count_active_buildings() * 0.04)
	amount = amount * smart_center_res

	hp = max(0, hp - amount)
	health_bar.value = hp
	if hp <= 0 and not inactive:
		inactive = true
		$Inactive.visible = true
		if sprite_frames.has_animation("off"):
			play("off")

		emit_signal("destroyed", owner_peer_id)
		print("Smart Center destroyed by peer:", owner_peer_id)
		
		# Fade out & end game
		await fade_and_end_game(owner_peer_id)
		return

	popup = damage_popup_scene.instantiate()
	get_tree().current_scene.add_child(popup)
	var jitter_x := randf_range(-6, 6)
	popup.show_damage(amount, global_position + Vector2(jitter_x, -20))

	# Flash red
	if not disabled:
		modulate = Color(1, 0, 0, 0.5)
		await get_tree().create_timer(0.08).timeout
		modulate = Color(1, 1, 1)
		


func repair_building(amount: int) -> void:
	print("repairing")
	if inactive:
		return
	amount = amount / 2
	if max_hp < (hp + amount):
		amount = max_hp - hp
		if amount == 0:
			return
	popup = damage_popup_scene.instantiate()
	get_tree().current_scene.add_child(popup)
	popup.get_node("Label").add_theme_color_override("font_color", Color(144, 238, 144))
	popup.get_node("Label").self_modulate = Color(0, 1, 0)
	var jitter_x := randf_range(-6, 6)
	popup.show_num(amount, global_position + Vector2(jitter_x, -20))

	hp = min(max_hp, hp + amount)
	health_bar.value = hp

func fade_and_end_game(destroyed_owner_id: int) -> void:
	var fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.size = get_viewport_rect().size
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(fade_rect)

	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, 2.0) # fade to black in 2s
	await tween.finished

	var winner_name: String
	if get_parent().board_owner == "player":
		Global.winner = "Opponent"
	else:
		Global.winner = "You"

	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")
