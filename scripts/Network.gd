extends Node

const VERSION = "v0.0.7MS"
const DEFAULT_PORT = 10567

const MAX_PEERS = 8

# Current players in lobby. Stored by server and used by players
var players = {}

# Lobby signals
## SceneTree Callbacks
func _player_connected(id):
	if get_tree().is_network_server():
		print("Player " + str(id) + " connected.")

func _player_disconnected(id):
	if not get_tree().is_network_server():
		# Close the card fight if your opponent leaves
		if $CardFight.opponent == id:
			$CardFight.visible = false
		
		return
		
	# Wipe opponent from challengers dict
	players.erase(id)
	print("Player " + str(id) + " left")
	
	rpc("update_player_list", players)


func _connected_ok():
	# Connected to server
	sLog("connected successfully, sending info")
	rpc_id(1, "register_player", {
		"name": $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/uname.text,
		"profile_pic": $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/ppSelect.get_item_text($Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/ppSelect.selected),
		"available": true
		})

func _connection_failed():
	sLog("connection failed!")
	get_tree().network_peer = null
	
func _server_disconnected():
	sLog("Server disconnected!")
	get_tree().network_peer = null
	
	$Lobby.clear_player_list()
	
	$CardFight.visible = false

## Actual game functions

func host_lobby():
	if not $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/uname.text:
		sLog("Please enter a username")
		return
	
	# Deck check
	var dFile = File.new()
	dFile.open($AllCards.deck_path + $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/dSelect.text + ".deck", File.READ)
	if len(parse_json(dFile.get_as_text())) == 0:
		sLog("Your deck is empty!")
		dFile.close()
		return
	dFile.close()
	
	if get_tree().network_peer:
		sLog("Cancelling existing hosting / connection attempt...")
		get_tree().network_peer = null
	
	var peer = NetworkedMultiplayerENet.new()
	peer.create_server(DEFAULT_PORT, MAX_PEERS)
	get_tree().network_peer = peer
	
	var localip = "Unknown"
	for ip in IP.get_local_addresses():
		if ip.begins_with("192"):
			localip = ip
	
	sLog("Lobby open with ip " + localip)
	
func connect_to_master(ip = "localhost"):
	if not ip:
		sLog("Please enter an IP")
		return
	if not $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/uname.text:
		sLog("Please enter a username")
		return
		
	# Deck check
	var dFile = File.new()
	dFile.open($AllCards.deck_path + $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/dSelect.text + ".deck", File.READ)
	if len(parse_json(dFile.get_as_text())) == 0:
		sLog("Your deck is empty!")
		dFile.close()
		return
	dFile.close()
	
	if get_tree().network_peer:
		sLog("Cancelling existing hosting / connection attempt...")
		get_tree().network_peer = null
	
	sLog("Attempting to connect to master server, please wait up to 1 minute")
	
	var peer = NetworkedMultiplayerENet.new()
	var err = peer.create_client(ip, DEFAULT_PORT)
	
	if not err:
		get_tree().network_peer = peer
	else:
		sLog("Error connecting to server! Error " + str(err))

#remote func challenge_refused():
#	sLog("Challenge refused!")
#
#remote func kicked_from_chat():
#	sLog("Challenge refused!")
#	emit_signal("kicked_from_game")

#remote func server_accepted_challenge():
#	sLog("Challenge accepted by server!")
##	$ChatRoom.visible = true
##	$ChatRoom.open()
#
#	# Opponent is server
#	opponent = 1
#
#	# Load deck from file and pass to the battle handler
#	var dFile = File.new()
#	dFile.open($AllCards.deck_path + $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/dSelect.text + ".deck", File.READ)
#	var ddata = parse_json(dFile.get_as_text())
#
#	$CardFight.initial_deck = ddata["cards"]
#	$CardFight.side_deck_index = ddata["side_deck"]
#
#	# Open the card battle window and initialise the match
#	$CardFight.visible = true
#	$CardFight.init_match(opponent)
#
#	pass


## UI funcs -> Server
#func _decline_challenge(index):
#	pass
#	# Inform opponent they are kicked
#	rpc_id(pids[index], "challenge_refused")
#
#	# Kick opponent from game
#	get_tree().network_peer.disconnect_peer(pids[index])	

#func _accept_challenge(index):
#	# Inform opponent their request was accepted
#	rpc_id(pids[index], "server_accepted_challenge")
#
#	# Set opponent
#	opponent = pids[index]
#
#	# Load deck from file and pass to the battle handler
#	var dFile = File.new()
#	dFile.open($AllCards.deck_path + $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/dSelect.text + ".deck", File.READ)
#	var ddata = parse_json(dFile.get_as_text())
#
#	$CardFight.initial_deck = ddata["cards"]
#	$CardFight.side_deck_index = ddata["side_deck"]
#
#	# Open the card battle window and initialise the match
#	$CardFight.visible = true
#	$CardFight.init_match(opponent)
#
#	pass



func debug_join():
	sLog("Attempting to join a local debug game!")

	# Set username
	$Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/uname.text = "CHALLENGER CLIENT"

	connect_to_master("localhost")

func _ready():
	randomize()
	
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self,"_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	get_tree().connect("connection_failed", self, "_connection_failed")
	get_tree().connect("server_disconnected", self, "_server_disconnected")
	
	$VersionLabel.text = VERSION
	
	if not OS.is_debug_build():
		return
	
	for option in OS.get_cmdline_args():
		if option == "listen":
			master_server()
		if option == "join":
			debug_join()


func sLog(text):
	$Lobby/HBoxContainer/VBoxContainer/console/log.text += text + "\n"


func master_server():
	print("Master server starting for game version ", VERSION)
	
	# Hide all
	for child in get_children():
		child.queue_free()
	
	var peer = NetworkedMultiplayerENet.new()
	peer.create_server(DEFAULT_PORT, MAX_PEERS)
	get_tree().network_peer = peer
	
	print("Master Server open")

func start_mp_battle(opp):
	# Do the same for the opponent
	rpc_id(opp, "join_mp_battle", get_tree().get_network_unique_id())
	
	# Load deck from file and pass to the battle handler
	var dFile = File.new()
	dFile.open($AllCards.deck_path + $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/dSelect.text + ".deck", File.READ)
	var ddata = parse_json(dFile.get_as_text())

	$CardFight.initial_deck = ddata["cards"]
	$CardFight.side_deck_index = ddata["side_deck"]

	# Open the card battle window and initialise the match
	$CardFight.visible = true
	$CardFight.init_match(opp, true)
	


remote func join_mp_battle(opp):
	# Load deck from file and pass to the battle handler
	var dFile = File.new()
	dFile.open($AllCards.deck_path + $Lobby/HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/dSelect.text + ".deck", File.READ)
	var ddata = parse_json(dFile.get_as_text())

	$CardFight.initial_deck = ddata["cards"]
	$CardFight.side_deck_index = ddata["side_deck"]

	# Open the card battle window and initialise the match
	$CardFight.visible = true
	$CardFight.init_match(opp, false)

# Server -> Register player
remote func register_player(p_object):
	if not get_tree().is_network_server():
		sLog("WRR")
		return
		
	players[get_tree().get_rpc_sender_id()] = p_object
	print("Player registered with data ", p_object)
	
	# Update list for all players
	rpc("update_player_list", players)
	

# Client -> Update player listing
remote func update_player_list(player_data):
	players = player_data
	sLog("Player data: " + str(players))
	
	# Remove myself from the list
	players.erase(get_tree().get_network_unique_id())
	
	sLog("Other player data: " + str(players))
	
	# Display player listing
	$Lobby.list_players(players)

