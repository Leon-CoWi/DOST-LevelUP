extends Building

class_name SandbagWarehouse

var cooldown_timer = 0.0
var effect_interval = 20.0

func init_stats():
	max_hp = 80
	hp = max_hp
	fire_resistance = 1.0    # Takes full fire damage
	wind_resistance = 1.0    # Takes full wind damage
	water_resistance = 0.7   # Takes 70% water damage
	sturdiness = 1.0        # Takes full earthquake damage
	attack = 0
	

func trigger_effect(delta):
	#for each adjacent plot every 20 seconds, increase their fire resistance by 0.02 (up to a max of 0.3)
	cooldown_timer += delta
	if cooldown_timer >= effect_interval:
		cooldown_timer = 0.0
		show_increase()
		var adjacent = get_parent().adjacent_plot_indices 
		var parent_node = get_parent().get_parent().get_parent()
		for adj_index in adjacent:
			var tile = parent_node.get_tile_at(adj_index)
			if tile and tile.is_occupied and tile.building_scene:
				tile.building_scene.water_resistance = max(tile.building_scene.water_resistance - 0.02, 0.3)
				

func show_increase() -> void:
	print("repairing")
	if inactive:
		return
	
	popup = damage_popup_scene.instantiate()
	get_tree().current_scene.add_child(popup)
	popup.get_node("Label").add_theme_color_override("font_color", Color(173, 216, 230))
	popup.get_node("Label").self_modulate = Color(0, 0, 1)
	#reduce size to 32
	popup.get_node("Label").add_theme_font_size_override("font_size", 48)
	var jitter_x := randf_range(-6, 6)
	popup.show_text("Adj W. Res++", global_position + Vector2(jitter_x, -20))
