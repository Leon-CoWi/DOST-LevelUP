extends Building

class_name SeismicReinforcementLab

var _buffed_positions = []
const EARTH_BUFF = 0.5

func _ready():
	max_hp = 150
	hp = max_hp
	# Stored values are "vulnerability": 1.0 = full damage taken, 0.0 = immune.
	# So sturdiness = 0.7 means actual protection = 30%.
	fire_resistance = 1
	wind_resistance = 1
	water_resistance = 1
	sturdiness = 0.7
	attack = 0
	production_rate = 0
	energy_consumption = 10

func _process(delta):
	pass
