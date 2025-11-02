extends Building

var heal_timer = 0
var heal_cooldown = 6


func init_stats():
	max_hp = 80
	hp = max_hp
	fire_resistance = 1.0    # Takes full fire damage
	wind_resistance = 0.7    # Takes 70% wind damage
	water_resistance = 1.0   # Takes full water damage
	sturdiness = 1.0        # Takes full earthquake damage
	attack = 0
	production_rate = 0
	energy_consumption = 10

# this is called every secon! trigger effect func
func trigger_effect(delta: float) -> void:
	heal_timer += delta
	if heal_timer > heal_cooldown:
		heal_timer = 0
		var plot = get_parent().get_parent().get_parent()

		var directions = [
			[0, 1], [0, -1], [1, 0], [-1, 0]
		]

		for dir in directions:
			var target_index = [plot_index[0] + dir[0], plot_index[1] + dir[1]]
			print(target_index)
			var tile = plot.get_tile_at(target_index)
			if tile and tile.is_occupied and tile.building_scene:
				tile.building_scene.repair_building(5)
