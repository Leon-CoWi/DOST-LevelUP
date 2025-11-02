extends TextureButton

@onready var hover = $PanelContainer

var plot_index = [0, 0]
var current_building = null
var is_occupied = false
var building_scene = null
var adjacent_plot_indices = [] # all adjacent plots, max of 8
var board_owner = ""
var _hovering := false

func _ready() -> void:
	# Ensure hover panel exists
	hover = get_node_or_null("PanelContainer")
	if not hover:
		push_error("Plot slot is missing PanelContainer for hover!")
		return
		
	# Connect mouse signals
	mouse_entered.connect(on_mouse_entered)
	mouse_exited.connect(on_mouse_exited)

func _process(delta: float) -> void:
	if _hovering and building_scene and is_instance_valid(building_scene):
		_update_hover_labels()

func on_mouse_entered() -> void:
	if hover and building_scene and is_occupied and is_instance_valid(building_scene):
		_hovering = true
		# Update immediately and show
		_update_hover_labels()
		hover.show()  # or hover.toggle(true) depending on your implementation

func on_mouse_exited() -> void:
	_hovering = false
	if hover:
		hover.hide()  # or hover.toggle(false)

func _update_hover_labels() -> void:
	# safe checks for nodes
	if not hover:
		return
	# name / basic info
	if hover.has_node("VBoxContainer/NameLabel"):
		hover.get_node("VBoxContainer/NameLabel").text = str(building_scene.name)
	if hover.has_node("VBoxContainer/HPLabel"):
		var hp_val = building_scene.hp
		if building_scene.has_method("get_hp"):
			hp_val = building_scene.get_hp()
		hover.get_node("VBoxContainer/HPLabel").text = "HP: %d/%d" % [hp_val, building_scene.max_hp]
	if hover.has_node("VBoxContainer/EnergyLabel"):
		hover.get_node("VBoxContainer/EnergyLabel").text = "Energy: %d" % building_scene.energy_consumption

	# resistances (uses get_resistances() if available)
	var res = {}
	if building_scene.has_method("get_resistances"):
		res = building_scene.get_resistances()
	else:
		# fallback to direct properties (guarded)
		res = {
			"fire": building_scene.fire_resistance if building_scene.has_method("fire_resistance") or "fire_resistance" in building_scene else building_scene.fire_resistance,
			"wind": building_scene.wind_resistance if "wind_resistance" in building_scene else building_scene.wind_resistance,
			"water": building_scene.water_resistance if "water_resistance" in building_scene else building_scene.water_resistance,
			"sturdiness": building_scene.sturdiness if "sturdiness" in building_scene else building_scene.sturdiness
		}

	if hover.has_node("VBoxContainer/FireLabel"):
		hover.get_node("VBoxContainer/FireLabel").text = "Fire: %s" % str(res.get("fire", "N/A"))
	if hover.has_node("VBoxContainer/WindLabel"):
		hover.get_node("VBoxContainer/WindLabel").text = "Wind: %s" % str(res.get("wind", "N/A"))
	if hover.has_node("VBoxContainer/WaterLabel"):
		hover.get_node("VBoxContainer/WaterLabel").text = "Water: %s" % str(res.get("water", "N/A"))
	if hover.has_node("VBoxContainer/SturdinessLabel"):
		hover.get_node("VBoxContainer/SturdinessLabel").text = "Sturdiness: %s" % str(res.get("sturdiness", "N/A"))

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

func align_building_to_center(inst: Node) -> void:
	var center := Vector2(size.x / 2.0, size.y / 2.0)
	var offset := Vector2.ZERO
	if "placement_offset" in inst:
		offset = inst.placement_offset
	inst.position = center + offset
