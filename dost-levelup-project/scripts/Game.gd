extends Control

# Game.gd - manages card display, selection, and building placement
# Uses CardSlot functions properly for card display and selection

@onready var player_cards = $CanvasLayer/PlayerCards
@onready var opponent_cards = $CanvasLayer/OpponentCards
@onready var timer_label = $CanvasLayer/Label
var local_hand: Hand = null
var card_pool_meta := {}
var revealed_cards := {} # peer_id -> { slot_index: card_id }
var selected_card_id = null
var selected_card_slot_index = null
var seconds_passed = 0
@export var card_reveal_duration := 1.0 # Duration in seconds to show revealed cards
var game_timer: Timer = null

func _ready():
	# Inform the authoritative server that this client finished loading the Game scene.
	# Server will collect these signals and, when everyone is ready, spawn players and send hands.
	# If we're running as the server (host), call the handler directly. Clients should rpc_id the server.
	if Network and Network.multiplayer:
		Network.call_or_rpc_id(1, "rpc_client_loaded")

	# Optionally, initialize UI placeholders
	_clear_card_holders()
	# Connect plot slots so player can tap to place buildings
	_connect_plot_slots()
	# Start the game timer
	_start_game_timer()

func _start_game_timer() -> void:
	# Create and configure timer
	game_timer = Timer.new()
	game_timer.wait_time = 1.0  # 1 second
	game_timer.one_shot = false  # Repeat
	add_child(game_timer)
	game_timer.timeout.connect(_on_timer_timeout)
	game_timer.start()
	print("[Game] Timer started")

func _clear_card_holders():
	# Do not free slot nodes. Instead deactivate the item display inside each
	# existing slot so the layout remains intact and we avoid creating new slots.
	if player_cards and player_cards.get_child_count() > 0:
		for holder in player_cards.get_children():
			var layout = holder
			if holder.has_node("GridContainer"):
				layout = holder.get_node("GridContainer")
			for slot_node in layout.get_children():
				if slot_node.has_node("CenterContainer/Panel/itemDisplay"):
					slot_node.get_node("CenterContainer/Panel/itemDisplay").visible = false
				# remove any dynamic labels left from previous fills
				var panel = slot_node.get_node("CenterContainer/Panel")
				for child in panel.get_children():
					if child.name != "itemDisplay":
						child.queue_free()
	if opponent_cards and opponent_cards.get_child_count() > 0:
		for holder in opponent_cards.get_children():
			var layout2 = holder
			if holder.has_node("GridContainer"):
				layout2 = holder.get_node("GridContainer")
			for slot2_node in layout2.get_children():
				if slot2_node.has_node("CenterContainer/Panel/itemDisplay"):
					slot2_node.get_node("CenterContainer/Panel/itemDisplay").visible = false
				var panel2 = slot2_node.get_node("CenterContainer/Panel")
				for child2 in panel2.get_children():
					if child2.name != "itemDisplay":
						child2.queue_free()

func _highlight_playable_cards(current_energy: int):
	if not player_cards or local_hand == null:
		return
	var layout = player_cards.get_child(0)
	if layout.has_node("GridContainer"):
		layout = layout.get_node("GridContainer")
	for i in range(local_hand.slots.size()):
		var card_slot = local_hand.slots[i]
		var node = layout.get_child(i)
		# call UI method on slot node to set playable/dim state
		if card_slot.item != null:
			var cost = card_slot.item.cost if card_slot.item.has_method("cost") else 1
			node.call_deferred("set_playable", current_energy >= cost)
		else:
			node.call_deferred("set_playable", false)
		# reflect selection state
		if selected_card_slot_index != null and selected_card_slot_index == i:
			node.call_deferred("set_selected", true)
		else:
			node.call_deferred("set_selected", false)

func _on_card_clicked(slot_index: int) -> void:
	print("[Game] Card slot clicked:", slot_index)
	
	# First determine if this is a player or opponent card based on which container was clicked
	var in_player_cards := false
	
	# Check if clicked slot is in player_cards
	if player_cards and player_cards.get_child_count() > 0:
		var layout = player_cards.get_child(0)
		if layout.has_node("GridContainer"):
			layout = layout.get_node("GridContainer")
		if slot_index < layout.get_child_count():
			in_player_cards = true
	
	# If it's a player card, handle selection and validation
	if in_player_cards and local_hand != null and slot_index >= 0 and slot_index < local_hand.slots.size():
		var card_slot = local_hand.slots[slot_index]
		if card_slot.item != null:
			# Select the card if player has enough energy
			var card_cost = card_slot.item.cost if card_slot.item.has_method("cost") else 1
			var my_id = multiplayer.get_unique_id()
			var current_energy = Network.player_energy.get(my_id, 0)
			if current_energy >= card_cost:
				# Deselect previous selection
				if selected_card_slot_index != null and selected_card_slot_index >= 0:
					# clear previous visual
					var prev_layout = player_cards.get_child(0)
					if prev_layout.has_node("GridContainer"):
						prev_layout = prev_layout.get_node("GridContainer")
					if selected_card_slot_index < prev_layout.get_child_count():
						var prev_node = prev_layout.get_child(selected_card_slot_index)
						prev_node.call_deferred("set_selected", false)
				# set new selection
				selected_card_id = card_slot.item.id
				selected_card_slot_index = slot_index
				var layout = player_cards.get_child(0)
				if layout.has_node("GridContainer"):
					layout = layout.get_node("GridContainer")
				if slot_index < layout.get_child_count():
					var node = layout.get_child(slot_index)
					node.call_deferred("set_selected", true)
				print("[Game] Selected card id:", selected_card_id)
			else:
				print("[Game] Not enough energy to select card (cost: %d, current: %d)" % [card_cost, current_energy])
	# If it's an opponent card, request reveal
	elif not in_player_cards:
		var opp_id = _get_opponent_peer_id()
		if opp_id > 0:
			Network.request_reveal_peer_card(opp_id, slot_index)

func _replace_card(slot_index: int) -> void:
	if not Network or not Network.available_card_ids or Network.available_card_ids.is_empty():
		return
		
	# Pick a random card from available pool
	var available = Network.available_card_ids
	var new_id = available[randi() % available.size()]
	
	# Load the card resource
	var res_path = "res://cards/card_%d.tres" % new_id
	if ResourceLoader.exists(res_path):
		var card_res = ResourceLoader.load(res_path)
		if local_hand and slot_index >= 0 and slot_index < local_hand.slots.size():
			local_hand.slots[slot_index].item = card_res
			# Update UI
			_populate_card_holder(player_cards, [], true)

# Connect player plot buttons so taps can place buildings
func _connect_plot_slots() -> void:
	if not has_node("PlayerPlot"):
		return
	var player_plot = $PlayerPlot
	var container = player_plot.get_node("GridContainer")
	for i in range(container.get_child_count()):
		var btn = container.get_child(i)
		# bind them with their index [0,0 to 4,4]
		print("Asads")
		if btn:
			var plot_idx = [int(i % 5), int(i / 5)] # assuming 5x5 grid
			btn.set_plot_index(plot_idx)
			btn.current_building = null
			btn.board_owner = "player"
			var callable = Callable(self, "_on_plot_pressed").bind(plot_idx, btn)
			btn.pressed.connect(callable)
	
	var opponent_plot = $OpponentPlot
	container = opponent_plot.get_node("GridContainer")
	for i in range(container.get_child_count()):
		var btn = container.get_child(i)
		# bind them with their index [0,0 to 4,4]
		print("Asads")
		if btn:
			var plot_idx = [int(i % 5), int(i / 5)] # assuming 5x5 grid
			btn.set_plot_index(plot_idx)
			btn.current_building = null
			btn.board_owner = "opponent"
			var callable = Callable(self, "_on_enemy_plot_pressed").bind(plot_idx, btn)
			btn.pressed.connect(callable)


# Handler when a plot is pressed by the local player
func _on_plot_pressed(idx, btn) -> void:
	if not player_cards.current_selected_type == "Building":
		print("not a building lols")
		return

	print("asdakdjadja")
	var plot_index = idx
	if player_cards.current_selected == -1:
		print("[Game] No card selected to place")
		return
	if btn.is_occupied:
		print("[Game] Plot is already occupied")
		return

	var card_slot = local_hand.slots[player_cards.current_selected]
	var my_id = multiplayer.get_unique_id()
	var card_id = card_slot.item.id
	var card_cost = card_slot.item.cost
	var current_energy = Network.player_energy.get(my_id, 0)
	if current_energy < card_cost:
		print("[Game] Not enough energy to place building %d", current_energy)
		return
	# Request server to place building (server will validate and broadcast)
	if Network:
		print("this is reached or something lols")
		Network.call_or_rpc_id(1, "request_place_building", [my_id, plot_index, card_id])
	# Locally remove the card and schedule replacement
	local_hand.remove_from_slot(player_cards.current_selected)
	# clear selection visuals
	var layout = player_cards.get_child(0)
	if layout.has_node("GridContainer"):
		layout = layout.get_node("GridContainer")
	if player_cards.current_selected < layout.get_child_count():
		var node = layout.get_child(player_cards.current_selected)
		node.call_deferred("set_selected", false)
	# schedule replacement
	var timer = get_tree().create_timer(3.0)
	timer.timeout.connect(_replace_card.bind(player_cards.current_selected))
	_populate_card_holder(player_cards, [], true)
	player_cards.deselect_other_slots(-1)
	selected_card_id = null

func _on_enemy_plot_pressed(idx, btn) -> void:
	if not player_cards.current_selected_type == "Disaster":
		print("not a disaster lols")
		return

	print("asdakdjadja")
	var plot_index = idx
	if player_cards.current_selected == -1:
		print("No card selected to place")
		return

	var card_slot = local_hand.slots[player_cards.current_selected]
	var my_id = multiplayer.get_unique_id()
	var card_id = card_slot.item.id
	var card_cost = card_slot.item.cost
	var current_energy = Network.player_energy.get(my_id, 0)
	if current_energy < card_cost:
		print("Not enough energy to place building %d", current_energy)
		return
	# Request server to place building (server will validate and broadcast)
	if Network:
		print("this is reached or something lols")
		Network.call_or_rpc_id(1, "request_use_disaster", [my_id, plot_index, card_id])
	# Locally remove the card and schedule replacement
	local_hand.remove_from_slot(player_cards.current_selected)
	# clear selection visuals
	var layout = player_cards.get_child(0)
	if layout.has_node("GridContainer"):
		layout = layout.get_node("GridContainer")
	if player_cards.current_selected < layout.get_child_count():
		var node = layout.get_child(player_cards.current_selected)
		node.call_deferred("set_selected", false)
	# schedule replacement
	var timer = get_tree().create_timer(3.0)
	timer.timeout.connect(_replace_card.bind(player_cards.current_selected))
	_populate_card_holder(player_cards, [], true)
	player_cards.deselect_other_slots(-1)
	selected_card_id = null

func _get_opponent_peer_id() -> int:
	if not Network or not Network.players:
		return -1
	var my_id = multiplayer.get_unique_id()
	# In 2-player game, find first id that isn't ours
	for peer_id in Network.players.keys():
		if peer_id != my_id:
			return peer_id
	return -1

@rpc("any_peer", "reliable")
func rpc_receive_private_hand(hand: Array):
	# The server will send the array of card ids to the owning client
	# For each id we will try to load a Card resource (res://cards/card_<id>.tres)
	# and instantiate a card slot for it so the card graphic appears.
	# Build a Hand resource instance from the playerhand template and the received ids
	var template = ResourceLoader.load("res://cards/playerhand.tres")
	if template:
		# deep duplicate so we can modify slots safely
		local_hand = template.duplicate(true)
	else:
		# fallback: create minimal Hand instance
		local_hand = Hand.new()

	# Fill hand resource slots with Card resources where available
	for i in range(local_hand.slots.size()):
		if i < hand.size():
			var cid = hand[i]
			var res_path = "res://cards/card_%d.tres" % cid
			if ResourceLoader.exists(res_path):
				var card_res = ResourceLoader.load(res_path)
				local_hand.slots[i].item = card_res
			else:
				local_hand.slots[i].item = null
		else:
			local_hand.slots[i].item = null

	# Populate UI using the id array (keeps existing behavior) and keep local_hand for monitoring
	_populate_card_holder(player_cards, hand, true)

# Runs on all clients; provides how many cards each player has (public info)
@rpc("any_peer", "reliable")
func rpc_set_public_hand_counts(public_counts: Dictionary):
	# Use public_counts to populate opponent_cards with X placeholders for remote players
	print("[Game] Public counts: %s" % public_counts)
	# For a simple 2-player layout assume one opponent with peer id != local
	var my_id = multiplayer.get_unique_id()
	for peer_id in public_counts.keys():
		if peer_id == my_id:
			# our own UI is handled by rpc_receive_private_hand
			continue
		var count = public_counts[peer_id]
		_populate_card_holder(opponent_cards, Array(), false, count)

func _populate_card_holder(container: Node, _hand: Array, face_up: bool, count: int = -1):
	# Find the layout GridContainer inside the holder
	var layout_node: Node = container
	if container.has_node("GridContainer"):
		layout_node = container.get_node("GridContainer")

	# Determine how many slots to iterate: always prefer explicit count, otherwise 3
	var cards_to_create = 3
	if count >= 0:
		cards_to_create = count

	var existing = layout_node.get_child_count()
	if existing == 0:
		push_warning("Card holder has no child slots; expected at least one slot.")

	# Iterate over expected slots and update visuals based on local_hand (for player)
	for i in range(cards_to_create):
		if i >= existing:
			push_warning("Not enough slots in holder; expected %d but found %d" % [cards_to_create, existing])
			continue

		var slot_node: Node = layout_node.get_child(i)
		var panel = slot_node.get_node("CenterContainer/Panel")
		# remove dynamic labels
		for child in panel.get_children():
			if child.name != "itemDisplay":
				child.queue_free()

		# Set slot index if present
		slot_node.slot_index = i

		# Connect click signal once
		var click_callable = Callable(self, "_on_card_clicked")
		if not slot_node.is_connected("slot_clicked", click_callable):
			slot_node.connect("slot_clicked", click_callable)

		# For player holder: show item if local_hand has item in this slot
		if container == player_cards and local_hand != null:
			var s = local_hand.slots[i]
			slot_node.card_resource = s.item
			var itemDisplay = slot_node.get_node("CenterContainer/Panel/itemDisplay")
			# Prefer explicit face_up/face_down textures if defined on the Card resource
			var tex: Texture2D = null
			if s.item != null:
				if s.item and face_up and s.item.texture_face_up != null:
					tex = s.item.texture_face_up
				elif s.item and not face_up and s.item.texture_face_down != null:
					tex = s.item.texture_face_down
				slot_node.get_node("Cost").text = str(s.item.cost)
				
				

			if tex != null:
				itemDisplay.texture = tex
				itemDisplay.visible = true
			else:
				itemDisplay.visible = false
		else:
			# Opponent or face-down: show a card-back texture if available
			var itemDisplay2 = slot_node.get_node("CenterContainer/Panel/itemDisplay")
			var back_tex: Texture2D = null
			# Try to use card_pool_meta first
			if card_pool_meta.size() > 0:
				var first_key = card_pool_meta.keys()[0]
				var back_path = card_pool_meta[first_key]["path"]
				if ResourceLoader.exists(back_path):
					var back_res = ResourceLoader.load(back_path)
					if back_res and back_res.texture_face_down != null:
						back_tex = back_res.texture_face_down
					elif back_res and back_res.texture_face_up != null:
						back_tex = back_res.texture_face_up
			# Fallback to card_1
			# Prefer explicit Network.card_back if set
			if back_tex == null and Network and Network.card_back != null:
				back_tex = Network.card_back
			# Fallback to card_1 resource
			if back_tex == null and ResourceLoader.exists("res://cards/card_1.tres"):
				var fb = ResourceLoader.load("res://cards/card_1.tres")
				if fb and fb.texture_face_down != null:
					back_tex = fb.texture_face_down
				elif fb and fb.texture_face_up != null:
					back_tex = fb.texture_face_up
			# If this opponent slot has been revealed, show the revealed card face-up
			var my_id = multiplayer.get_unique_id()
			# Assume a single-opponent layout; find the peer id of the opponent if available
			var revealed_card_id = null
			for raw_key in revealed_cards.keys():
				var pid = int(raw_key)
				if pid != my_id:
					var map = revealed_cards[raw_key]
					if map.has(i):
						revealed_card_id = map[i]
						break
			if revealed_card_id != null:
				var res_path = "res://cards/card_%d.tres" % int(revealed_card_id)
				if ResourceLoader.exists(res_path):
					var card_res = ResourceLoader.load(res_path)
					if card_res and card_res.texture_face_up != null:
						itemDisplay2.texture = card_res.texture_face_up
						itemDisplay2.visible = true
						continue
			# No reveal for this slot: show back texture if available
			if back_tex != null:
				itemDisplay2.texture = back_tex
				itemDisplay2.visible = true
			else:
				itemDisplay2.visible = false


@rpc("any_peer", "reliable")
func rpc_set_player_names(names: Dictionary):
	# names is a dictionary mapping peer_id -> display name
	# RPC serialization can convert integer keys to strings, so coerce keys to int
	var my_id = multiplayer.get_unique_id()
	var my_name = null
	var opp_name = null
	for raw_key in names.keys():
		var pid = int(raw_key)
		var pname = names[raw_key]
		if pid == my_id:
			my_name = pname
		else:
			# take the first other peer as opponent (works for 2-player layout)
			if opp_name == null:
				opp_name = pname

	# Set local UI labels (PlayerName on left, OpponentName on right)
	if my_name != null and has_node("PlayerName"):
		$PlayerName.text = str(my_name)
	if opp_name != null and has_node("OpponentName"):
		$OpponentName.text = str(opp_name)




@rpc("any_peer", "reliable")
func rpc_update_energies(energies: Dictionary) -> void:
	# Update UI labels for player and opponent energy whenever the server broadcasts
	var my_id = multiplayer.get_unique_id()
	var my_energy = null
	var opp_energy = null
	for raw_key in energies.keys():
		var pid = int(raw_key)
		var val = energies[raw_key]
		if pid == my_id:
			my_energy = val
		else:
			if opp_energy == null:
				opp_energy = val

	if my_energy != null and has_node("PlayerEnergy"):
		$PlayerEnergy.text = "Energy: " + str(my_energy)
	if opp_energy != null and has_node("OpponentEnergy"):
		$OpponentEnergy.text = "Energy: " + str(opp_energy)


func rpc_set_card_pool(pool_meta: Dictionary) -> void:
	# Store the card pool metadata for UI/debug monitoring (id -> name/path/frequency)
	card_pool_meta = pool_meta.duplicate()
	print("[Game] Received card pool metadata: %s" % card_pool_meta)

func get_selected_card_id():
	return selected_card_id


@rpc("any_peer", "reliable")
func rpc_place_building(owner_peer_id: int, plot_index, card_id: int) -> void:
	print("[Game] rpc_place_building called owner=%d plot=%s card=%d" % [owner_peer_id, str(plot_index), card_id])

	var root = get_tree().get_current_scene()
	if not root:
		push_warning("[Game] rpc_place_building: no current scene")
		return

	# Determine which plot node belongs to the owner_peer_id.
	# Adjust node names to match your scene: PlayerPlot = local player's grid, OpponentPlot = other player's grid
	var target_plot_node: Node = null
	var my_id = multiplayer.get_unique_id()
	if owner_peer_id == my_id:
		if root.has_node("PlayerPlot"):
			target_plot_node = root.get_node("PlayerPlot")
	else:
		# remote player's plot (opponent)
		if root.has_node("OpponentPlot"):
			target_plot_node = root.get_node("OpponentPlot")

	if target_plot_node == null:
		push_warning("[Game] rpc_place_building: could not find plot node for owner %d" % owner_peer_id)
		return

	var container = target_plot_node
	if target_plot_node.has_node("GridContainer"):
		container = target_plot_node.get_node("GridContainer")

	# Load the card resource locally and get its building_scene
	var card_res_path = "res://cards/card_%d.tres" % card_id
	if not ResourceLoader.exists(card_res_path):
		push_warning("[Game] rpc_place_building: card resource not found: %s" % card_res_path)
		return
	var card_res = ResourceLoader.load(card_res_path)
	if card_res == null:
		push_warning("[Game] rpc_place_building: failed to load card resource %s" % card_res_path)
		return

	# Expect the Card resource to have a `building_scene` property (PackedScene)
	var building_scene: PackedScene = null
	building_scene = card_res.building_scene
	
	if building_scene == null:
		push_warning("[Game] rpc_place_building: no building_scene defined on card %d" % card_id)
		return

	# Find the matching button by plot_index and instantiate the building under it
	for i in range(container.get_child_count()):
		var btn = container.get_child(i)
		if not btn:
			continue
		var plot_idx = [int(i % 5), int(i / 5)]
		if plot_idx.size() == plot_index.size() and int(plot_idx[0]) == int(plot_index[0]) and int(plot_idx[1]) == int(plot_index[1]):
			var building_instance = building_scene.instantiate()
			btn.add_child(building_instance)
			btn.current_building = card_id
			btn.is_occupied = true
			btn.building_scene = building_instance
			btn.building_scene.plot_index = plot_idx
			# Center the building visually within the plot slot (uses Pivot or exported placement_offset if available)
			_align_building_on_plot(btn, building_instance)
			print("[Game] Placed building for owner %d at %s (btn idx %d)" % [owner_peer_id, str(plot_index), i])
			break

@rpc("any_peer", "reliable")
func rpc_use_disaster(owner_peer_id: int, plot_index, card_id: int) -> void:
	print("[Game] Disaster triggered by %d at plot %s" % [owner_peer_id, str(plot_index)])

	var root = get_tree().get_current_scene()
	if not root:
		return

	# Determine target plot (enemy’s land)
	var my_id = multiplayer.get_unique_id()
	var target_plot: Node = null
	if owner_peer_id == my_id:
		# If I'm the one casting it, target opponent's plot
		if root.has_node("OpponentPlot"):
			target_plot = root.get_node("OpponentPlot")
	else:
		# If opponent cast it, target my plot
		if root.has_node("PlayerPlot"):
			target_plot = root.get_node("PlayerPlot")

	if not target_plot:
		push_warning("Could not find target plot for disaster.")
		return

	# Load the card resource locally and get its building_scene
	var card_res_path = "res://cards/card_%d.tres" % card_id
	if not ResourceLoader.exists(card_res_path):
		push_warning("[Game] rpc_place_building: card resource not found: %s" % card_res_path)
		return
	var card_res = ResourceLoader.load(card_res_path)
	if card_res == null:
		push_warning("[Game] rpc_place_building: failed to load card resource %s" % card_res_path)
		return

	var disaster_scene = card_res.disaster_scene

	# Example effect: destroy or damage all buildings in target plot cell
	var container = target_plot.get_node("GridContainer")

	for i in range(container.get_child_count()):
		var btn = container.get_child(i)
		if not btn:
			continue
			
		var plot_idx = [int(i % 5), int(i / 5)]
		# element-wise compare to support arrays
		if plot_idx.size() == plot_index.size() and int(plot_idx[0]) == int(plot_index[0]) and int(plot_idx[1]) == int(plot_index[1]):
			var disaster_instance = disaster_scene.instantiate()
			btn.add_child(disaster_instance)
			btn.trigger_disaster(card_id, disaster_instance)
			print("lol disaster go boogsh")
			break

# Helper: align a Node2D building inside a Control plot button so it appears centered
func _align_building_on_plot(plot_btn: Control, building: Node) -> void:
	if plot_btn == null or building == null:
		return
	# Determine the local center of the plot button (Control uses size)
	var center := Vector2.ZERO
	if "size" in plot_btn:
		center = plot_btn.size * 0.5
	else:
		# Fallback: try rect_size (older APIs)
		center = plot_btn.get_rect().size * 0.5 if plot_btn.has_method("get_rect") else Vector2.ZERO

	var offset := Vector2.ZERO
	# If the building provides a Pivot node, align that to the center
	var pivot: Node = building.get_node_or_null("Pivot")
	if pivot and pivot is Node2D:
		offset = -(pivot as Node2D).position
	# Else, if the building exposes an exported placement_offset, use it
	elif "placement_offset" in building:
		offset = building.placement_offset

	# Apply final local position
	if "position" in building:
		building.position = center + offset

func _on_timer_timeout():
	seconds_passed += 1
	@warning_ignore("integer_division")
	var minutes = seconds_passed / 60
	var seconds = seconds_passed % 60
	timer_label.text = "Time: %02d:%02d" % [minutes, seconds]
