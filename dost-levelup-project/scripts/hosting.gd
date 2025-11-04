extends Control

@onready var ip_display_label = null

func _ready():
	# Optional: listen for connection signals from the Network autoload
	if Engine.has_singleton("Network"):
		Network.connected.connect(_on_network_connected)
	
	# Try to find IP display label if it exists in the scene
	if has_node("IPDisplayLabel"):
		ip_display_label = $IPDisplayLabel

func _on_server_pressed():
	# Start the host (server + local player)
	Network.start_host()
	
	# Get local IP addresses
	var local_ips = _get_local_ip_addresses()
	var ip_message = "Host started!\n\nShare this info with other players:\n"
	if local_ips.size() > 0:
		ip_message += "IP: %s\n" % local_ips[0]
		for i in range(1, local_ips.size()):
			ip_message += "or: %s\n" % local_ips[i]
	else:
		ip_message += "Run 'ipconfig' in Command Prompt to find your IP\n"
	ip_message += "Port: %d" % Network.DEFAULT_PORT
	
	# Display in label if available
	if ip_display_label:
		ip_display_label.text = ip_message
		ip_display_label.visible = true
	
	# Print helpful join instructions to console
	print("========================================")
	print(ip_message)
	print("========================================")

func _get_local_ip_addresses() -> Array:
	var ips = []
	# Get all local IP addresses from network interfaces
	for ip in IP.get_local_addresses():
		# Filter out localhost and IPv6
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			ips.append(ip)
	return ips

func _on_network_connected(success, reason):
	if success:
		# Move to lobby where the MultiplayerSpawner can spawn the host player
		var lobby_path = "res://scenes/Lobby.tscn"
		if ResourceLoader.exists(lobby_path):
			get_tree().change_scene_to_file(lobby_path)
		else:
			print("Lobby scene not found at %s, but host started: %s" % [lobby_path, reason])
	else:
		push_error("Failed to start host: %s" % reason)
