extends AnimatedSprite2D

class_name Building

@export var max_hp: int = 100
var hp: int
@onready var health_bar = $Healthbar
var hp_not_init = true

# 1 is full damage, if they resist will be lower
var fire_resistance = 1 
var wind_resistance = 1
var water_resistance = 1
var sturdiness = 1 #earthquake/disruption res
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
	init_stats()
	hp = max_hp

	# Find the health bar safely
	if has_node("Healthbar"):
		health_bar = $Healthbar
	else:
		await get_tree().process_frame
		if has_node("Healthbar"):
			health_bar = $Healthbar

	# Initialize if it exists
	if health_bar:
		if health_bar.has_method("init_health"):
			health_bar.init_health(max_hp)
		health_bar.value = hp
	else:
		push_warning("⚠️ No Healthbar found in " + str(name))
	
	
func init_stats():
	pass


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
	print("Taking damage:", amount, "type:", damage_type, "HP before:", hp)
	if damage_type == "fire":
		amount = amount * fire_resistance
	elif damage_type == "water":
		amount = amount * water_resistance
	elif damage_type == "wind":
		amount = amount * wind_resistance
	elif damage_type == "quakes":
		amount = amount * sturdiness

	hp = max(0, hp - amount)
	health_bar.value = hp
	if hp <= 0:
		inactive = true
		$Inactive.visible = true
		if sprite_frames.has_animation("off"):
			play("off")
		emit_signal("destroyed", owner_peer_id)

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

func get_resistances() -> Dictionary:
	# return the current resistance values used by your buildings
	return {
		"fire": fire_resistance,
		"wind": wind_resistance,
		"water": water_resistance,
		"sturdiness": sturdiness
	}
