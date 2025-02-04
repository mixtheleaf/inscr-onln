extends Node

var all_sigils = []
var all_cards = []
var banned_cards = []
var deck_path = "decks/"

func _ready():
	read_game_info()
	
	if OS.get_name() == "OSX":
		deck_path = "user://decks/"

func read_game_info():
	var file = File.new()
	file.open("res://data/gameInfo.json", File.READ)
	var file_content = file.get_as_text()
	var content_as_object = parse_json(file_content)
	all_sigils = content_as_object["sigils"]
	all_cards = content_as_object["cards"]
	banned_cards = content_as_object["banned_cards"]
