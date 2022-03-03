extends Control

var pListingPrefab = preload("res://packed/pListing.tscn")
onready var selector_de = $HBoxContainer/VBoxContainer/PanelContainer/VBoxContainer/HBoxContainer2/dSelect
onready var network_manager = get_node("/root/Main")
onready var cardInfo = network_manager.get_node("AllCards")

func list_players(player_data):
	clear_player_list()
	
	for pid in player_data.keys():
		var pList = pListingPrefab.instance()
		pList.get_node("HBoxContainer/Challengername").text = player_data[pid]["name"]
		
		# Connect challenge button
		pList.get_node("HBoxContainer/ybtn").connect("pressed", self, "toggle_challenge", [pid, pList.get_node("HBoxContainer/ybtn")])
		pList.get_node("HBoxContainer/Challengerpfp").texture = load("res://gfx/portraits/portrait_" + player_data[pid]["profile_pic"] + ".png")
		
		# Is player in a game?
		if not player_data[pid]["available"]:
			pList.get_node("HBoxContainer/ybtn").text = "In-game"
			pList.get_node("HBoxContainer/ybtn").disabled = true
		
		$HBoxContainer/ScrollContainer/Challenges.add_child(pList)

func clear_player_list():
	for listing in $HBoxContainer/ScrollContainer/Challenges.get_children():
		listing.queue_free()

func _edit_deck():
	get_node("/root/Main/DeckEdit").visible = true
	get_node("/root/Main/DeckEdit").ensure_default_deck()
	get_node("/root/Main/DeckEdit").populate_deck_list()

func populate_deck_list():
	selector_de.clear()
	
	var dTest = Directory.new()
	dTest.open(cardInfo.deck_path)
	dTest.list_dir_begin()
	var fName = dTest.get_next()
	while fName != "":
		if not dTest.current_is_dir() and fName.ends_with(".deck"):
			selector_de.add_item(fName.split(".deck")[0])
		fName = dTest.get_next()

func toggle_challenge(pid, button):
	match button.text:
		
		"Challenge Player":
			button.text = "Cancel Challenge"
			
			rpc_id(pid, "set_challenge_status", true)
			
		"Cancel Challenge":
			button.text = "Challenge Player"
			
			rpc_id(pid, "set_challenge_status", false)
			
		"Accept Challenge":
			network_manager.sLog("Accepted Challenge")
			
			network_manager.start_mp_battle(pid)


remote func set_challenge_status(state):
	network_manager.sLog("Challenged by player " + str(get_tree().get_rpc_sender_id()))
	
	var btn = $HBoxContainer/ScrollContainer/Challenges.get_child(network_manager.players.keys().find(get_tree().get_rpc_sender_id())).get_node("HBoxContainer/ybtn")
	
	if state:
		btn.text = "Accept Challenge"
	else:
		btn.text = "Challenge Player"
