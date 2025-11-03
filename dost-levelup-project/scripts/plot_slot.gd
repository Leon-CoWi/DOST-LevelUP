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
	
	# Make sure mouse filter is set to PASS so hover works on entire button
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Connect mouse signals
	if not mouse_entered.is_connected(on_mouse_entered):
		mouse_entered.connect(on_mouse_entered)
	if not mouse_exited.is_connected(on_mouse_exited):
		mouse_exited.connect(on_mouse_exited)

func _process(_delta: float) -> void:
	if _hovering and building_scene and is_instance_valid(building_scene):
		_update_hover_labels()

func _gui_input(event: InputEvent) -> void:
	# Additional hover detection for the entire button area
	if event is InputEventMouseMotion:
		if not _hovering and building_scene and is_occupied and is_instance_valid(building_scene):
			on_mouse_entered()

func on_mouse_entered() -> void:
	if hover and building_scene and is_occupied and is_instance_valid(building_scene):
		_hovering = true
		# Update immediately and show
		_update_hover_labels()
		hover.toggle(true)
		print("[PlotSlot] Mouse entered plot with building: ", building_scene.name)
	elif not building_scene or not is_occupied:
		print("[PlotSlot] Mouse entered empty plot")

func on_mouse_exited() -> void:
	_hovering = false
	if hover:
		hover.toggle(false)
		print("[PlotSlot] Mouse exited plot")

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
			"sturdiness": building_scene.sturdiness if "sturdiness" in building_scene else building_scene.sturdiness,
			"smart_center": building_scene.smart_center_res if "smart_center_res" in building_scene else null
		}
	if hover.has_node("VBoxContainer/SmartCenterLabel") and res.has("smart_center") and res["smart_center"] != null:
		var sc_val = res.get("smart_center", 1.0)
		hover.get_node("VBoxContainer/SmartCenterLabel").text = "SC Res: %.0f%%" % ((1.0 - sc_val) * 100.0)
		return
	if hover.has_node("VBoxContainer/FireLabel"):
		var fire_val = res.get("fire", 1.0)
		# Convert resistance: 1.0 = 0% resistance, 0.0 = 100% resistance
		hover.get_node("VBoxContainer/FireLabel").text = "Fire Res: %.0f%%" % ((1.0 - fire_val) * 100.0)
	if hover.has_node("VBoxContainer/WindLabel"):
		var wind_val = res.get("wind", 1.0)
		hover.get_node("VBoxContainer/WindLabel").text = "Wind Res: %.0f%%" % ((1.0 - wind_val) * 100.0)
	if hover.has_node("VBoxContainer/WaterLabel"):
		var water_val = res.get("water", 1.0)
		hover.get_node("VBoxContainer/WaterLabel").text = "Water Res: %.0f%%" % ((1.0 - water_val) * 100.0)
	if hover.has_node("VBoxContainer/SturdinessLabel"):
		var sturdy_val = res.get("sturdiness", 1.0)
		hover.get_node("VBoxContainer/SturdinessLabel").text = "Quake Res: %.0f%%" % ((1.0 - sturdy_val) * 100.0)

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
					if roll <= 45 and adjacent_plot_indices.size() > 0:
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
			13: #toxic surge, damage to one tile and reduce all res by 10%, and then slowly spread to the other adjacent tiles reducing their res by 5%
				await get_tree().create_timer(0.8).timeout
				var parent_node = get_parent().get_parent()
				if is_occupied and building_scene:
					building_scene.take_damage(15, "water")
					building_scene.fire_resistance = 1 if building_scene.fire_resistance + 0.1 > 1.0 else building_scene.fire_resistance + 0.1
					building_scene.wind_resistance = 1 if building_scene.wind_resistance + 0.1 > 1.0 else building_scene.wind_resistance + 0.1
					building_scene.water_resistance = 1 if building_scene.water_resistance + 0.1 > 1.0 else building_scene.water_resistance + 0.1
					building_scene.sturdiness = 1 if building_scene.sturdiness + 0.1 > 1.0 else building_scene.sturdiness + 0.1
				await get_tree().create_timer(0.8).timeout
				for adj_index in adjacent_plot_indices:
					var tile = parent_node.get_tile_at(adj_index)
					var card_res = ResourceLoader.load("res://cards/card_13.tres")
					var disaster_scene = card_res.disaster_scene
					var d_i = disaster_scene.instantiate()
					tile.add_child(d_i)
					if tile and tile.is_occupied and tile.building_scene:
						tile.building_scene.take_damage(7.5, "water")
						tile.building_scene.fire_resistance = 1 if tile.building_scene.fire_resistance + 0.05 > 1.0 else tile.building_scene.fire_resistance + 0.05
						tile.building_scene.wind_resistance = 1 if tile.building_scene.wind_resistance + 0.05 > 1.0 else tile.building_scene.wind_resistance + 0.05
						tile.building_scene.water_resistance = 1 if tile.building_scene.water_resistance + 0.05 > 1.0 else tile.building_scene.water_resistance + 0.05
						tile.building_scene.sturdiness = 1 if tile.building_scene.sturdiness + 0.05 > 1.0 else tile.building_scene.sturdiness + 0.05


@rpc("reliable")
func sync_tornado_roll(roll: int, new_index: Array):
	var card_res = ResourceLoader.load("res://cards/card_12.tres")
	var disaster_scene = card_res.disaster_scene

	if roll <= 45: #45% chance to move it 
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
		await get_tree().create_timer(0.1).timeout
		var disaster_instance = disaster_scene.instantiate()
		self.add_child(disaster_instance)
		trigger_disaster(12, disaster_instance)

func align_building_to_center(inst: Node) -> void:
	var center := Vector2(size.x / 2.0, size.y / 2.0)
	var offset := Vector2.ZERO
	if "placement_offset" in inst:
		offset = inst.placement_offset
	inst.position = center + offset
