extends Control

signal plot_clicked(plot_index)

@export var is_player_plot: bool = true

func count_active_buildings():
	var active_count = 0
	var grid_container = $GridContainer
	for plot in grid_container.get_children():
		if plot.is_occupied and plot.building_scene:
			if not plot.building_scene.inactive:
				active_count += 1
	return (active_count - 1) #exc SC

func get_tile_at(index):
	#get grid container then get the plot at index
	for btn in $GridContainer.get_children():
		if btn.plot_index == index:
			return btn
	return null
