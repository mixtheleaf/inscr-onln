extends Control

# Side decks
const side_decks = [
	[29, 29, 29, 29, 29, 29, 29, 29, 29, 29],
	[78, 78, 78, 78, 78, 78, 78, 78, 78, 78],
	[97, 97, 97, 98, 98, 98, 99, 99, 99, 99]
]
const side_deck_names = [
	"Squirrels",
	"Skeletons",
	"Mox"
]

# Carryovers from lobby
var opponent = -100
var initial_deck = []
var side_deck_index = null

# Game components
onready var handManager = $HandsContainer/Hands
onready var playerSlots = $CardSlots/PlayerSlots
onready var enemySlots = $CardSlots/EnemySlots
onready var allCards = get_node("/root/Main/AllCards")
onready var slotManager = $CardSlots
var cardPrefab = preload("res://packed/playingCard.tscn")

# Game state
enum GameStates {
	DRAWPILE,
	NORMAL,
	SACRIFICE,
	FORCEPLAY,
	BATTLE,
	HAMMER
}
var state = GameStates.NORMAL

# Health
var advantage = 0
var lives = 2
var opponent_lives = 2
var damage_stun = false

# Resources
var bones = 0
var opponent_bones = 0

var energy = 0
var max_energy = 0
var opponent_energy = 0
var opponent_max_energy = 0

# Decks
var deck = []
var side_deck = []

# Starvation
var turns_starving = 0

# Network match state
var want_rematch = false

func init_match(opp_id: int):
	opponent = opp_id
	
	# Hide rematch UI
	$WinScreen.visible = false
	want_rematch = false
	$WinScreen/Panel/VBoxContainer/HBoxContainer/RematchBtn.text = "Rematch (0/2)"
	
	# Reset decks
	deck = initial_deck.duplicate()
	deck.shuffle()
	side_deck = side_decks[side_deck_index].duplicate()
	side_deck.shuffle()
	$DrawPiles/YourDecks/Deck.visible = true
	$DrawPiles/YourDecks/SideDeck.visible = true
	$DrawPiles/YourDecks/SideDeck.text = side_deck_names[side_deck_index]
	
	# Reset game state
	advantage = 0
	lives = 2
	opponent_lives = 2
	damage_stun = false
	turns_starving = 0
	
	bones = 0
	opponent_bones = 0
	add_bones(0)
	add_opponent_bones(0)
	
	set_max_energy(int(get_tree().is_network_server()))
	set_energy(max_energy)
	set_opponent_max_energy(int(not get_tree().is_network_server()))
	set_opponent_energy(opponent_max_energy)
	
	state = GameStates.NORMAL
	
	# Clean up hands and field
	handManager.clear_hands()
	slotManager.clear_slots()
		
	# Draw starting hands
	for _i in range(4):
		draw_card(deck.pop_front())
		
		# Some interaction here if your deck has less than 3 cards. Don't punish I guess?
		if deck.size() == 0:
			$DrawPiles/YourDecks/Deck.visible = false
			break
		
	draw_card(side_deck.pop_front())
	
	$WaitingBlocker.visible = not get_tree().is_network_server()


# Gameplay functions
## LOCAL
func commence_combat():
	if not state in [GameStates.NORMAL, GameStates.SACRIFICE]:
		return
	
	# Lower all cards
	handManager.lower_all_cards()
	
	# Remove sacrifice effect from all cards
	slotManager.clear_sacrifices()
	
	# Initiate combat first
	state = GameStates.BATTLE
	slotManager.initiate_combat()

func draw_maindeck():
	if state == GameStates.DRAWPILE:
		
		draw_card(deck.pop_front())
		
		state = GameStates.NORMAL
		$DrawPiles/Notify.visible = false
		
		if deck.size() == 0:
			$DrawPiles/YourDecks/Deck.visible = false
			# Communicate this with opponent
	
	starve_check()
	

func draw_sidedeck():
	if state == GameStates.DRAWPILE:
		draw_card(side_deck.pop_front(), $DrawPiles/YourDecks/SideDeck)
		state = GameStates.NORMAL
		$DrawPiles/Notify.visible = false
		
		if side_deck.size() == 0:
			$DrawPiles/YourDecks/SideDeck.visible = false
		
		starve_check()

func starve_check():
	if deck.size() == 0 and side_deck.size() == 0:
		turns_starving += 1
		
		# Give opponent a starvation
		rpc_id(opponent, "force_draw_starv", turns_starving)
		return true
	return false

func draw_card(idx, source = $DrawPiles/YourDecks/Deck):
	var nCard = cardPrefab.instance()
	nCard.from_data(allCards.all_cards[idx])
	source.add_child(nCard)
	
	nCard.rect_position = Vector2.ZERO
	
	# Animate the card
	nCard.move_to_parent(handManager.get_node("PlayerHand"))
	
	rpc_id(opponent, "_opponent_drew_card", str(source.get_path()).split("YourDecks")[1])
	
	return nCard

func play_card(slot):
	
	# Is a card ready to be played?
	if handManager.raisedCard:
		
		# Only allow playing cards in the NORMAL or FORCEPLAY states
		if state in [GameStates.NORMAL, GameStates.FORCEPLAY]:
			rpc_id(opponent, "_opponent_played_card", allCards.all_cards.find(handManager.raisedCard.card_data), slot.get_position_in_parent())
			
			# Bone cost
			add_bones(-handManager.raisedCard.card_data["bone_cost"])
			
			# Energy cost
			set_energy(energy -handManager.raisedCard.card_data["energy_cost"])
			
			# SIGILS
			for sigil in handManager.raisedCard.card_data["sigils"]:
				if sigil == "Fecundity":
					draw_card(allCards.all_cards.find(handManager.raisedCard.card_data))
				if sigil == "Rabbit Hole":
					draw_card(20)
				if sigil == "Battery Bearer":
					if max_energy < 6:
						set_max_energy(max_energy + 1)
					set_energy(min(max_energy, energy + 1))
			
			# Starvation, inflict damage if 9th onwards
			if handManager.raisedCard.card_data["name"] == "Starvation" and handManager.raisedCard.attack >= 9:
				# Ramp damage over time so the game actually ends
				inflict_damage(handManager.raisedCard.attack - 8)
			
			handManager.raisedCard.move_to_parent(slot)
			handManager.raisedCard = null
			state = GameStates.NORMAL
			
			

# Hammer Time
func hammer_mode():
	# Use inverted values for button value, as this happens before its state is toggled
	# Janky hack m8
	
	if slotManager.get_available_slots() == 4:
		$LeftSideUI/HammerButton.pressed = true
		return
	
	if state == GameStates.NORMAL:
		state = GameStates.HAMMER
	elif state == GameStates.HAMMER:
		state = GameStates.NORMAL
	
	if state == GameStates.HAMMER:
		$LeftSideUI/HammerButton.pressed = false
	else:
		$LeftSideUI/HammerButton.pressed = true

## REMOTE
remote func _opponent_drew_card(source_path):
	var nCard = cardPrefab.instance()
	get_node("DrawPiles/EnemyDecks/" + source_path).add_child(nCard)
	nCard.move_to_parent(handManager.get_node("EnemyHand"))

remote func _opponent_played_card(card, slot):
	
	var card_dt = allCards.all_cards[card]
	
	# Special case: Starvation
	if card == 0:
		card_dt["attack"] = turns_starving
		if turns_starving >= 5:
			card_dt["sigils"].append("Mighty Leap")
		
		# Inflict starve damage
		if turns_starving >= 9:
			inflict_damage(-turns_starving + 8)
		
	handManager.opponentRaisedCard.from_data(card_dt)
	handManager.opponentRaisedCard.move_to_parent(enemySlots.get_child(slot))
	
	# Costs
	add_opponent_bones(-allCards.all_cards[card]["bone_cost"])
	set_opponent_energy(opponent_energy -allCards.all_cards[card]["energy_cost"])
	
	# Energy Cell Sigil
	if "Battery Bearer" in allCards.all_cards[card]["sigils"]:
		if opponent_max_energy < 6:
			set_opponent_max_energy(opponent_max_energy + 1)
		set_opponent_energy(min(opponent_energy + 1, opponent_max_energy))
	

remote func force_draw_starv(strength):
	var starv_card = draw_card(0)
	
	var starv_data = allCards.all_cards[0]
	starv_data["attack"] = strength
	if strength >= 5:
		starv_data["sigils"].append("Mighty Leap")
	
	starv_card.from_data(starv_data)
	
# Called during attack animation
func inflict_damage(dmg):
	if damage_stun:
		return
	
	advantage += dmg
	
	if advantage >= 5:
		opponent_lives -= 1
		advantage = 0
		damage_stun = true
	
	if advantage <= -5:
		lives -= 1
		advantage = 0
		damage_stun = true
		
	$LeftSideUI/OpponentLivesLabel.text = "Opponent Lives: " + str(opponent_lives)
	$LeftSideUI/LivesLabel.text = "Lives: " + str(lives)
	$LeftSideUI/AdvantageLabel.text = "Advantage: " + str(advantage)
	
	# Win condition
	if lives == 0:
		$WinScreen/Panel/VBoxContainer/WinLabel.text = "You Lose!"
		$WinScreen.visible = true
	
	if opponent_lives == 0:
		$WinScreen/Panel/VBoxContainer/WinLabel.text = "You Win!"
		$WinScreen.visible = true


# Resource visualisation and management
func add_bones(bone_no):
	bones += bone_no
	$LeftSideUI/BonesLabel.text = "Bones: " + str(bones)

func add_opponent_bones(bone_no):
	opponent_bones += bone_no
	$LeftSideUI/OpponentBonesLabel.text = "Opponent Bones: " + str(opponent_bones)

func set_energy(ener_no):
	energy = ener_no
	$LeftSideUI/EnergyLabel.text = "Energy: " + str(energy)
	
func set_opponent_energy(ener_no):
	opponent_energy = ener_no
	$LeftSideUI/OpponentEnergyLabel.text = "Opponent Energy: " + str(opponent_energy)

func set_max_energy(ener_no):
	max_energy = ener_no
	$LeftSideUI/MaxEnergyLabel.text = "Max Energy: " + str(max_energy)
	
func set_opponent_max_energy(ener_no):
	opponent_max_energy = ener_no
	$LeftSideUI/OpponentMaxEnergyLabel.text = "Opponent Max Energy: " + str(opponent_max_energy)


# Network interactions
## LOCAL
func request_rematch():
	want_rematch = true
	rpc_id(opponent, "_rematch_requested")
	$WinScreen/Panel/VBoxContainer/HBoxContainer/RematchBtn.text = "Rematch (1/2)"

func end_turn():
	$WaitingBlocker.visible = true
	damage_stun = false
	
	# Bump opponent's energy
	if opponent_max_energy < 6:
		set_opponent_max_energy(opponent_max_energy + 1)
	set_opponent_energy(opponent_max_energy)
	
	rpc_id(opponent, "start_turn")

func surrender():
	$WinScreen/Panel/VBoxContainer/WinLabel.text = "You Surrendered!"
	$WinScreen.visible = true
	
	rpc_id(opponent, "_opponent_surrendered")

func quit_match():
	# Tell opponent I surrendered
	rpc_id(opponent, "_opponent_quit")
	
	# Force a disconnect if I'm server
	if get_tree().is_network_server():
		get_tree().network_peer.disconnect_peer(opponent)
	else:
		get_tree().network_peer = null
		visible = false
## REMOTE
remote func _opponent_quit():
	# Quit network
	get_tree().network_peer = null
	visible = false

remote func _opponent_surrendered():
	# Force the game to end
	$WinScreen/Panel/VBoxContainer/WinLabel.text = "Your opponent Surrendered!"
	$WinScreen.visible = true

remote func _rematch_requested():
	if want_rematch:
		rpc_id(opponent, "_rematch_occurs")
		
		init_match(opponent)
	else:
		$WinScreen/Panel/VBoxContainer/HBoxContainer/RematchBtn.text = "Rematch (1/2)"	

remote func _rematch_occurs():
	init_match(opponent)

remote func start_turn():
	damage_stun = false
	$WaitingBlocker.visible = false
	
	# Draw yer cards, if you have any
	if starve_check():
		state = GameStates.NORMAL
	else:
		state = GameStates.DRAWPILE
		$DrawPiles/Notify.visible = true
	
	# Increment energy
	if max_energy < 6:
		set_max_energy(max_energy + 1)
	set_energy(max_energy)




# Connect in-game signals
func _ready():
	for slot in playerSlots.get_children():
		slot.connect("pressed", self, "play_card", [slot])
