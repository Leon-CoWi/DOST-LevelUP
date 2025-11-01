extends TextureButton

var plot_index = [0, 0]
var current_building = null
var is_occupied = false
var building_scene = null
var adjacent_plot_indices = [] # all adjacent plots, max of 8
var board_owner = ""

func check_occupied():
	return is_occupied

func set_plot_index(index: Array) -> void:
	plot_index = index
	adjacent_plot_indices.clear()
	for x_offset in range(-1, 2):
		for y_offset in range(-1, 2):
			if x_offset == 0 and y_offset == 0:
				continue
			if plot_index[0] + x_offset < 0 or plot_index[1] + y_offset < 0:
				continue
			if plot_index[0] + x_offset > 4 or plot_index[1] + y_offset > 4:
				continue
			var adjacent_index = [plot_index[0] + x_offset, plot_index[1] + y_offset]
			adjacent_plot_indices.append(adjacent_index)

func trigger_disaster(card_id: int, disaster_instance):
		match card_id:
			9: #blackout
				if is_occupied and building_scene:
					building_scene.blackout()
			10: #area 3x3 quakey
				await get_tree().create_timer(0.8).timeout
				var parent_node = get_parent().get_parent()
				for adj_index in adjacent_plot_indices:
					var tile = parent_node.get_tile_at(adj_index)
					if tile and tile.is_occupied and tile.building_scene:
						tile.building_scene.take_damage(30, "quakes")
				if is_occupied and building_scene:
					building_scene.take_damage(30, "quakes")
			11: #area 3x3 meterorrer
				await get_tree().create_timer(0.8).timeout
				var parent_node = get_parent().get_parent()
				for adj_index in adjacent_plot_indices:
					var tile = parent_node.get_tile_at(adj_index)
					if tile and tile.is_occupied and tile.building_scene:
						tile.building_scene.take_damage(30, "fire")
				if is_occupied and building_scene:
					building_scene.take_damage(30, "fire")
			12: #townaddooooooo
				await get_tree().create_timer(0.8).timeout
				if is_occupied and building_scene:
					building_scene.take_damage(5, "wind")

				await get_tree().create_timer(0.8).timeout

				if multiplayer.is_server():
					var roll = randi_range(1, 100)
					var new_index = []
					if roll <= 40 and adjacent_plot_indices.size() > 0:
						new_index = adjacent_plot_indices.pick_random()
					if board_owner == "player":
						var opponent_tile = get_tree().root.get_node("Game/OpponentPlot").get_tile_at(plot_index)
						opponent_tile.rpc("sync_tornado_roll", roll, new_index)
					else:
						var player_tile = get_tree().root.get_node("Game/PlayerPlot").get_tile_at(plot_index)
						player_tile.rpc("sync_tornado_roll", roll, new_index)
					sync_tornado_roll(roll, new_index)
				else:
					return


@rpc("reliable")
func sync_tornado_roll(roll: int, new_index: Array):
	var card_res = ResourceLoader.load("res://cards/card_12.tres")
	var disaster_scene = card_res.disaster_scene

	if roll <= 40: #40% chance to move it 
		if new_index.size() == 2:
			var parent_node = get_parent().get_parent()
			var target_tile = parent_node.get_tile_at(new_index)
			if target_tile:
				var disaster_instance = disaster_scene.instantiate()
				target_tile.add_child(disaster_instance)
				await get_tree().create_timer(0.3).timeout
				target_tile.trigger_disaster(12, disaster_instance)
	elif roll <= 60: # 20% chance to goney
		# dissipate
		pass
	else: #hahahaha again!!!!
		await get_tree().create_timer(0.8).timeout
		var disaster_instance = disaster_scene.instantiate()
		self.add_child(disaster_instance)
		trigger_disaster(12, disaster_instance)
