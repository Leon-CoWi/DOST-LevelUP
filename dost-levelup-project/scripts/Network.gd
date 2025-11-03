extends Node

const DEFAULT_IP := "localhost"
const DEFAULT_PORT := 12345
@export var MAX_PLAYERS: int = 2

signal player_joined(peer_id)
signal player_left(peer_id)
signal connected(success, reason)
signal player_list_updated(players)
signal game_started

var peer: ENetMultiplayerPeer
var started = false
var players := {} # peer_id -> name
var player_instances := {} # peer_id -> NodePath (server-side reference)
var player_hands := {} # peer_id -> Array[int] (authoritative hands)
var has_drawn_full_hand := {}
var ready_peers := {} # peer_id -> true when that peer has loaded the Game scene
var player_energy := {} # peer_id -> int (server-authoritative energy values)
var energy_rate:= 1.2 #one per 1.2 secs
var _energy_timer: Timer = null
var card_pool := {} # id -> {path: String, name: String, frequency: int}
@export var available_card_ids: Array = [1,2,3,4,5,6,9, 10, 11, 12, 13] # list of card ids the server can draw from (set in inspector or code)
@export var card_back: Texture2D = null # optional explicit card back texture used for opponents

# Programmatic helpers to control the available card pool at runtime
func set_available_card_ids(ids: Array) -> void:
	# Overwrite the available_card_ids used by the server for dealing
	available_card_ids = ids.duplicate()
	print("[Network] available_card_ids set to %s" % available_card_ids)

func set_available_card_ids_from_scanned_pool() -> void:
	# Build card_pool if empty and copy keys into available_card_ids (ids found under res://cards)
	_build_card_pool()
	var keys = card_pool.keys()
	# keys() returns an Array of ids (as ints or strings depending on serialization), coerce to ints
	var int_keys := []
	for k in keys:
		int_keys.append(int(k))
	available_card_ids = int_keys
	print("avail cards: " % available_card_ids)

func get_available_card_ids() -> Array:
	return available_card_ids.duplicate()

# Utility: call locally if target_peer is self, otherwise rpc_id the remote peer.
func call_or_rpc_id(target_peer: int, method_name: String, args: Array = []) -> void:
	var my_id = multiplayer.get_unique_id()
	if my_id == target_peer:
		# Call local method on this node if it exists
		if has_method(method_name):
			# Use call_deferred to mimic async network delivery, unpack args
			match args.size():
				0:
					call_deferred(method_name)
				1:
					call_deferred(method_name, args[0])
				2:
					call_deferred(method_name, args[0], args[1])
				3:
					call_deferred(method_name, args[0], args[1], args[2])
				4:
					call_deferred(method_name, args[0], args[1], args[2], args[3])
				5:
					call_deferred(method_name, args[0], args[1], args[2], args[3], args[4])
				_:
					# Fallback: pass the args array as single parameter
					call_deferred(method_name, args)
		else:
			push_warning("Network: local method '%s' not found" % method_name)
	else:
		# Use rpc_id to call the method on the remote peer
		# Unpack args array into the rpc_id call
		match args.size():
			0:
				rpc_id(target_peer, method_name)
			1:
				rpc_id(target_peer, method_name, args[0])
			2:
				rpc_id(target_peer, method_name, args[0], args[1])
			3:
				rpc_id(target_peer, method_name, args[0], args[1], args[2])
			4:
				rpc_id(target_peer, method_name, args[0], args[1], args[2], args[3])
			5:
				rpc_id(target_peer, method_name, args[0], args[1], args[2], args[3], args[4])
			_:
				# Generic fallback for more args
				rpc_id(target_peer, method_name, args)

func _ready():
	# Connect multiplayer signals to forward events
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)

func start_host(port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to create server: %s" % err)
		emit_signal("connected", false, "create_server_failed")
		return
	multiplayer.multiplayer_peer = peer
	
	# Add host to players list
	var host_id = multiplayer.get_unique_id()
	players[host_id] = "Host"
	# Print current available_card_ids so user knows what the server will draw from
	print("[Network] available_card_ids = %s (count=%d)" % [available_card_ids, available_card_ids.size()])
	# initialize energy for host
	player_energy[host_id] = 3
	broadcast_player_list()
	
	print("Server started on port %d" % port)
	emit_signal("connected", true, "host_started")

func stop_host() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
		peer = null
		print("Server stopped")
		emit_signal("connected", false, "host_stopped")
		# stop energy timer if running
		if _energy_timer:
			_energy_timer.stop()
			_energy_timer.queue_free()
			_energy_timer = null
		player_energy.clear()

func join_host(ip: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to create client: %s" % err)
		emit_signal("connected", false, "create_client_failed")
		return
	multiplayer.multiplayer_peer = peer
	print("Attempting connection to %s:%d" % [ip, port])

func leave_host() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
		peer = null
		print("Left host / disconnected")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	# Enforce player cap on server
	if multiplayer.is_server():
		var current := players.size()
		if current >= MAX_PLAYERS:
			print("Max players reached (%d). Disconnecting peer %d" % [MAX_PLAYERS, id])
			# Disconnect the peer (ENet uses peer IDs)
			if peer:
				peer.disconnect_peer(id)
			return
		# Assign a default name and broadcast
		players[id] = "Player %d" % id
		# initialize energy for the new player
		player_energy[id] = 3
		broadcast_player_list()
	emit_signal("player_joined", id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	# Remove from player list on server and broadcast
	if multiplayer.is_server():
		if id in players:
			players.erase(id)
			if id in player_energy:
				player_energy.erase(id)
			broadcast_player_list()
	emit_signal("player_left", id)

func _on_connection_succeeded() -> void:
	print("Connection succeeded")
	emit_signal("connected", true, "connected")

func _on_connection_failed() -> void:
	print("Connection failed")
	emit_signal("connected", false, "failed")

func broadcast_player_list() -> void:
	# Send the current player dictionary to all peers
	print("Broadcasting player list: %s" % players)
	# update local copy and emit
	emit_signal("player_list_updated", players)
	# Use multiplayer RPC to update clients
	if multiplayer.get_multiplayer_peer():
		# Send to all peers (including server) via node-level RPC
		rpc("rpc_update_player_list", players)


@rpc("any_peer", "reliable")
func request_player_list() -> void:
	# Called by clients to ask the server to broadcast the current player list
	if not multiplayer.is_server():
		return
	broadcast_player_list()

# Clients call this (via rpc_id to server) to request a name change
@rpc("any_peer", "reliable")
func request_name_change(peer_id: int, new_name: String) -> void:
	if not multiplayer.is_server():
		return
	print("Server received name change for %d -> %s" % [peer_id, new_name])
	players[peer_id] = new_name
	broadcast_player_list()
	# Send an acknowledgement directly to the requesting peer so their UI can react quickly
	# rpc_id is invoked on the server's Network node to call the client-side handler
	print("[Network] Name change ack for %d -> %s" % [peer_id, new_name])
	players[peer_id] = new_name
	emit_signal("player_list_updated", players)
	# If the game already started, also update names in the active Game scene for all peers
	if started:
		rpc("rpc_set_player_names", players)
		call_deferred("rpc_set_player_names", players)

@rpc("any_peer", "reliable")
func rpc_update_player_list(remote_players: Dictionary) -> void:
	# Update local view of players when server broadcasts
	players = remote_players.duplicate()
	emit_signal("player_list_updated", players)
	print("[Network] Received player list update: %s" % players)



# RPC function to start the game
@rpc("any_peer", "call_local", "reliable")
func start_game():
	# Server entry point to start the game. This version deals cards and performs a
	# handshake so that the server only spawns player instances and sends hands when
	# every peer (including the server) has finished loading the Game scene.
	if not multiplayer.is_server():
		return

	print("[Network] Starting game (deal + scene change)")
	started = true
	emit_signal("game_started")

	# Deal and change scene for all players. We'll use Game.tscn in /scenes.
	deal_and_start_game("res://scenes/Game.tscn")


@rpc("any_peer", "reliable")
func rpc_change_scene(scene_path: String) -> void:
	print("rpc_change_scene called: %s" % scene_path)
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		push_warning("Scene path not found: %s" % scene_path)


# --------------------
# Game / dealing helpers
# --------------------

func deal_and_start_game(game_scene_path: String = "res://scenes/Game.tscn") -> void:
	_build_card_pool()

	player_hands.clear()
	player_energy.clear()

	for peer_id in players.keys():
		player_hands[peer_id] = []
		player_energy[peer_id] = 3

	rpc("rpc_update_energies", player_energy)
	call_deferred("rpc_update_energies", player_energy)

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# Build the draw pool, excluding card_0
	var pool := []
	for id in available_card_ids:
		if id != 0:
			pool.append(id)
	pool.shuffle()

	# --- Give only card_0 first ---
	for peer_id in players.keys():
		player_hands[peer_id] = [0]  # only card_0
	# --- End first hand setup ---

	# Sync pool metadata (same as before)
	var pool_meta := {}
	for k in card_pool.keys():
		pool_meta[k] = {"path": card_pool[k].path, "name": card_pool[k].name, "frequency": card_pool[k].frequency}
	rpc("rpc_set_card_pool", pool_meta)
	call_deferred("rpc_set_card_pool", pool_meta)

	# Switch to game scene
	if multiplayer.get_multiplayer_peer():
		rpc("rpc_change_scene", game_scene_path)
	get_tree().change_scene_to_file(game_scene_path)

	var server_id = multiplayer.get_unique_id()
	ready_peers[server_id] = true
	_check_and_spawn_after_ready()



@rpc("any_peer", "reliable")
func rpc_client_loaded() -> void:
	# This is called by clients (rpc_id to server) to announce they finished loading Game scene
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	print("[Network] rpc_client_loaded from %d" % sender)
	ready_peers[sender] = true
	# Check if all players are ready; if so, proceed to spawn and send hands
	_check_and_spawn_after_ready()


func _check_and_spawn_after_ready() -> void:
	# Only server runs the spawn logic
	if not multiplayer.is_server():
		return
	# Ensure every player in players.keys() is marked ready
	for peer_id in players.keys():
		if not ready_peers.has(peer_id):
			return # still waiting

	# All ready: spawn player nodes and distribute hands
	_server_spawn_players_and_send_hands()


func _build_card_pool() -> void:
	# Scan res://cards for card_*.tres and load card resources into card_pool
	card_pool.clear()
	var dir = DirAccess.open("res://cards")
	if not dir:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			if fname.begins_with("card_") and fname.ends_with(".tres"):
				var id_str = fname.replace("card_", "").replace(".tres", "")
				var id = int(id_str)
				var path = "res://cards/%s" % fname
				var res = ResourceLoader.load(path)
				if res and res is Resource:
					var freq = 1
					if res and res.card_frequency != null:
						freq = int(res.card_frequency)
					card_pool[id] = {"path": path, "name": str(res.name), "frequency": freq}
		fname = dir.get_next()
	dir.list_dir_end()


func _server_spawn_players_and_send_hands() -> void:
	# Server-side: spawn Player nodes under a 'Players' container in the active scene
	var root = get_tree().get_current_scene()
	if not root:
		push_error("No current scene when spawning players")
		return
	if not root.has_node("Players"):
		push_error("Game scene must have a 'Players' node to parent player instances")
		return
	var players_container = root.get_node("Players")

	# Load the player scene if available; if missing, we won't instantiate scene objects but still send hands
	var player_scene = ResourceLoader.load("res://scenes/Player.tscn")
	player_instances.clear()

	# Re-broadcast card pool metadata now that clients should be in the Game scene
	# This ensures the Game scene receives the pool_meta (some clients may have ignored
	# earlier pool broadcasts while still in the Lobby scene).
	var pool_meta := {}
	for k in card_pool.keys():
		pool_meta[k] = {"path": card_pool[k].path, "name": card_pool[k].name, "frequency": card_pool[k].frequency}
	rpc("rpc_set_card_pool", pool_meta)
	call_deferred("rpc_set_card_pool", pool_meta)

	for peer_id in players.keys():
		# Instantiate a player node if the scene exists
		if player_scene:
			var inst = player_scene.instantiate()
			inst.name = "Player_%d" % peer_id
			players_container.add_child(inst)
			inst.set_multiplayer_authority(peer_id)
			player_instances[peer_id] = inst.get_path()
		else:
			player_instances[peer_id] = ""

		# Send the private hand to the owning peer (rpc_id -> client-side handler)
		if player_hands.has(peer_id):
			# Use helper that calls locally for the host, rpc_id for remote peers
			call_or_rpc_id(peer_id, "rpc_receive_private_hand", [player_hands[peer_id]])
		else:
			call_or_rpc_id(peer_id, "rpc_receive_private_hand", [[]])

	# Broadcast public counts so each client can show face-down cards for opponents
	var public_counts := {}
	var cards_per_player := 4
	for peer_id in players.keys():
		public_counts[peer_id] = cards_per_player
	rpc("rpc_set_public_hand_counts", public_counts)
	# Ensure local server also receives the forwarded RPCs (rpc doesn't always call locally)
	call_deferred("rpc_set_public_hand_counts", public_counts)

	# Also broadcast player names so clients can update name labels in the Game scene
	rpc("rpc_set_player_names", players)
	call_deferred("rpc_set_player_names", players)
	# Start server-side periodic energy updates (every 2s)
	_start_energy_timer()


@rpc("any_peer", "reliable")
func request_reveal_peer_card(target_peer_id: int, slot_index: int) -> void:
	# Clients can call this on the server to request revealing a specific card of a player.
	# Server validates and broadcasts the revealed card id to all peers.
	if not multiplayer.is_server():
		return
	if not player_hands.has(target_peer_id):
		push_warning("request_reveal_peer_card: target peer %d has no hand" % target_peer_id)
		return
	var hand = player_hands[target_peer_id]
	if slot_index < 0 or slot_index >= hand.size():
		push_warning("request_reveal_peer_card: invalid slot index %d for peer %d" % [slot_index, target_peer_id])
		return
	var card_id = int(hand[slot_index])
	# Broadcast to all clients the revealed card id for that peer's slot
	rpc("rpc_reveal_public_card", target_peer_id, slot_index, card_id)
	call_deferred("rpc_reveal_public_card", target_peer_id, slot_index, card_id)


# --------------------
# Client-side forwarders
# These RPCs are invoked on the Network autoload by the server (rpc/rpc_id).
# Forward them to the active scene (Game.gd) which contains the actual handlers/UI.
@rpc("any_peer", "reliable")
func rpc_receive_private_hand(hand: Array) -> void:
	# This runs on clients. Forward to the current scene if it has the handler.
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("rpc_receive_private_hand"):
		scene.rpc_receive_private_hand(hand)
	else:
		push_warning("No handler for rpc_receive_private_hand on current scene")

@rpc("any_peer", "reliable")
func rpc_set_public_hand_counts(public_counts: Dictionary) -> void:
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("rpc_set_public_hand_counts"):
		scene.rpc_set_public_hand_counts(public_counts)
	else:
		push_warning("No handler for rpc_set_public_hand_counts on current scene")

@rpc("any_peer", "reliable")
func rpc_set_player_names(names: Dictionary) -> void:
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("rpc_set_player_names"):
		scene.rpc_set_player_names(names)
	else:
		push_warning("No handler for rpc_set_player_names on current scene")


@rpc("any_peer", "reliable")
func rpc_set_card_pool(pool_meta: Dictionary) -> void:
	# Forward card pool metadata to active scene UI for monitoring
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("rpc_set_card_pool"):
		scene.rpc_set_card_pool(pool_meta)
	else:
		push_warning("No handler for rpc_set_card_pool on current scene")


@rpc("any_peer", "reliable")
func rpc_reveal_public_card(peer_id: int, slot_index: int, card_id: int) -> void:
	# Forward reveal broadcasts to the active scene which handles UI updates
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("rpc_reveal_public_card"):
		scene.rpc_reveal_public_card(peer_id, slot_index, card_id)
		# Start a timer to automatically hide it after 1 second
		get_tree().create_timer(1.0).timeout.connect(
			func():
				if scene and scene.has_method("rpc_hide_public_card"):
					scene.rpc_hide_public_card(peer_id, slot_index)
		)
	else:
		push_warning("No handler for rpc_reveal_public_card on current scene")


@rpc("any_peer", "reliable")
func rpc_place_building(owner_peer_id: int, plot_index, card_id: int) -> void:
	# Forward building placement broadcasts to the active scene which handles UI updates
	print("dsdasdsda")
	var scene = get_tree().get_current_scene()
	scene.rpc_place_building(owner_peer_id, plot_index, card_id)
	
@rpc("any_peer", "reliable")
func rpc_use_disaster(owner_peer_id: int, plot_index, card_id: int) -> void:
	# Forward the disaster shi sa sceenee
	print("dsdasdsda")
	var scene = get_tree().get_current_scene()
	scene.rpc_use_disaster(owner_peer_id, plot_index, card_id)


# Server-side periodic energy updates
func _start_energy_timer() -> void:
	if not multiplayer.is_server():
		return
	# Clean up existing timer if any
	if _energy_timer:
		_energy_timer.stop()
		_energy_timer.queue_free()
		_energy_timer = null
	# Create new timer
	_energy_timer = Timer.new()
	_energy_timer.wait_time = energy_rate
	_energy_timer.one_shot = false
	add_child(_energy_timer)
	_energy_timer.timeout.connect(_on_energy_timer_timeout)
	_energy_timer.start()

func _on_energy_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	# Increment each player's energy by 1 every timeout and broadcast
	for peer_id in players.keys():
		if not player_energy.has(peer_id):
			player_energy[peer_id] = 0
			print("Initialized energy for player %d" % peer_id)
		# Clamp energy to a maximum of 10 (adjustable)
		var max_energy = 10
		player_energy[peer_id] = min(player_energy[peer_id] + 1, max_energy)
	
	# Broadcast updated energies to all peers
	rpc("rpc_update_energies", player_energy)
	# Ensure the server/local also receives the forwarded RPC 
	call_deferred("rpc_update_energies", player_energy)


@rpc("any_peer", "reliable")
func request_use_card(owner_peer_id: int, _slot_index: int, _card_id: int, cost: int) -> void:
	# Client requests server to use a card and deduct energy
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	# only allow sender to request for their own player
	if sender != owner_peer_id:
		push_warning("Player %d attempted to use card for owner %d" % [sender, owner_peer_id])
		return
	
	# Check energy
	var current_energy = player_energy.get(owner_peer_id, 0)
	if current_energy < cost:
		push_warning("Not enough energy for player %d (cost: %d, current: %d)" % [owner_peer_id, cost, current_energy])
		return
	
	# Deduct energy and broadcast update
	player_energy[owner_peer_id] = max(0, current_energy - cost)
	rpc("rpc_update_energies", player_energy)
	call_deferred("rpc_update_energies", player_energy)
	

@rpc("any_peer", "reliable")
func request_place_building(owner_peer_id: int, plot_index, card_id: int) -> void:
	print("request_place_building called")
	var sender = multiplayer.get_remote_sender_id()

	# allow server self-call (sender==0)
	if sender != 0 and sender != owner_peer_id:
		push_warning("Player %d attempted to place for owner %d" % [sender, owner_peer_id])
		return

	# ensure energy entry exists
	if not player_energy.has(owner_peer_id):
		player_energy[owner_peer_id] = 10

	# load cost
	var cost = 1
	var res_path = "res://cards/card_%d.tres" % int(card_id)
	if ResourceLoader.exists(res_path):
		var cre = ResourceLoader.load(res_path)
		cost = int(cre.cost)

	var current_energy = player_energy.get(owner_peer_id, 0)
	if current_energy < cost:
		print("[Network] not enough energy for", owner_peer_id)
		rpc_id(owner_peer_id, "rpc_place_failed", plot_index, card_id, "not_enough_energy")
		return

	player_energy[owner_peer_id] = max(0, current_energy - cost)
	print("[Network] energy reduced:", player_energy)
	rpc("rpc_update_energies", player_energy)
	call_deferred("rpc_update_energies", player_energy)

	print("[Network] broadcasting rpc_place_building")
	rpc("rpc_place_building", owner_peer_id, plot_index, card_id)
	call_deferred("rpc_place_building", owner_peer_id, plot_index, card_id)

@rpc("any_peer", "reliable")
func request_use_disaster (owner_peer_id: int, plot_index, card_id: int) -> void:
	print("requsedis called")
	var sender = multiplayer.get_remote_sender_id()

	# allow server self-call (sender==0)
	if sender != 0 and sender != owner_peer_id:
		print("huh")
		push_warning("Player %d attempted to place for owner %d" % [sender, owner_peer_id])
		return

	# ensure energy entry exists
	if not player_energy.has(owner_peer_id):
		player_energy[owner_peer_id] = 10

	# load cost
	var cost = 1
	var res_path = "res://cards/card_%d.tres" % int(card_id)
	if ResourceLoader.exists(res_path):
		var cre = ResourceLoader.load(res_path)
		cost = int(cre.cost)

	var current_energy = player_energy.get(owner_peer_id, 0)
	if current_energy < cost:
		print("[Network] not enough energy for", owner_peer_id)
		rpc_id(owner_peer_id, "rpc_place_failed", plot_index, card_id, "not_enough_energy")
		return

	player_energy[owner_peer_id] = max(0, current_energy - cost)
	print("[Network] energy reduced:", player_energy)
	rpc("rpc_update_energies", player_energy)
	call_deferred("rpc_update_energies", player_energy)

	print("[Network] broadcasting rpc_use_disaster")
	rpc("rpc_use_disaster", owner_peer_id, plot_index, card_id)
	call_deferred("rpc_use_disaster", owner_peer_id, plot_index, card_id)


@rpc("any_peer", "reliable")
func rpc_update_energies(energies: Dictionary) -> void:
	player_energy = energies
	print("[Network] Synced player_energy:", player_energy)

	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("rpc_update_energies"):
		scene.rpc_update_energies(energies)
	else:
		push_warning("No handler for rpc_update_energies on current scene")

@rpc("authority", "reliable")
func request_full_hand_draw(player_id: int) -> void:
	# This must run on server only.
	# Only the server should actually process the draw logic
	if not multiplayer.is_server():
		print("[Network] Client tried to draw — passing to server.")
		rpc_id(1, "request_full_hand_draw", player_id)
		return

	# Guard: only once per player
	if has_drawn_full_hand.get(player_id, false):
		print("[Network] player %d already drew full hand" % player_id)
		return
	has_drawn_full_hand[player_id] = true

	print("[Network] request_full_hand_draw for player", player_id)

	# Build a shuffled pool copy and draw up to 4 cards
	var pool := available_card_ids.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	pool.shuffle()

	var new_hand := []
	for i in range(4):
		if pool.size() == 0:
			break
		new_hand.append(pool.pop_back())

	# Store authoritative hand if you use player_hands server-side
	player_hands[player_id] = new_hand

	# Send the private hand to the player. Use call_or_rpc_id so host receives it locally.
	call_or_rpc_id(player_id, "rpc_receive_private_hand", [new_hand])

	# Broadcast public counts (so opponent UI shows correct counts)
	var public_counts := {}
	# if you want only this player to have 4 and others keep existing counts:
	for pid in players.keys():
		if pid == player_id:
			public_counts[pid] = new_hand.size()
		else:
			# fallback: if server has player_hands for others use that length, else 1
			public_counts[pid] = player_hands[pid].size() if player_hands.has(pid) else 1
	rpc("rpc_set_public_hand_counts", public_counts)
	call_deferred("rpc_set_public_hand_counts", public_counts) # ensure local handled too
