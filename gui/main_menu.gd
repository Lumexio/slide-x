extends Spatial


# Called when the node enters the scene tree for the first time.
func _ready():
	pass
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_Start_pressed():
	var controller = GameGlobal.get_game_controller()
	if controller != null:
		controller.change_world3d_scene("res://gui/menu_character.tscn")
	else:
		push_error("GameGlobal.get_game_controller() returned null in _on_Start_pressed(); falling back to direct scene change.")
		get_tree().change_scene("res://gui/menu_character.tscn")


func _on_Quit_pressed():
	get_tree().quit()
