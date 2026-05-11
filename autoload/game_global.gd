extends Node

var game_controller = null

func set_game_controller(controller):
	game_controller = controller

func get_game_controller():
	if game_controller == null:
		push_error("GameController is not initialized yet.")
		return null
	if not is_instance_valid(game_controller):
		push_error("GameController reference is no longer valid.")
		game_controller = null
		return null
	return game_controller
