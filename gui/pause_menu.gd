extends Control

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	$".".hide()


func resume():
	get_tree().paused=false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	$".".hide()
func pause():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused=true
	$".".show()
	

func quitToMainMenu():
	get_tree().paused=false
	var controller = GameGlobal.get_game_controller()
	if controller != null:
		controller.change_world3d_scene("res://gui/main_menu.tscn")
	else:
		push_error("GameGlobal.get_game_controller() returned null; falling back to direct scene change to main menu.")
		get_tree().change_scene("res://gui/main_menu.tscn")



func testEsc():
	
	if Input.is_action_just_pressed("pause_game") and get_tree().paused==false:
		pause()
	elif Input.is_action_just_pressed("pause_game") and get_tree().paused==true:
		resume()


func _on_Resume_pressed():
	resume()


func _on_Quit_pressed():
	get_tree().quit()

func _on_GoToMainMenu_pressed():
	quitToMainMenu()

func _process(_delta):
	testEsc()

