extends Control

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	$".".hide()
	_set_loading_ui(false)


onready var _menu_buttons = [
	$"Panel/Resume",
	$"Panel/GoToMainMenu",
	$"Panel/Quit",
]
onready var _loading_bar = $"Panel/LoadingBar"
onready var _loading_label = $"Panel/LoadingLabel"

var _loader = null
var _is_loading = false
var _finish_requested = false

const MAIN_MENU_PATH = "res://gui/main_menu.tscn"


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
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_begin_loading(MAIN_MENU_PATH)



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
	if _loader != null:
		_poll_loader()
		return
	testEsc()


func _begin_loading(scene_path):
	if _is_loading:
		return
	var loader = ResourceLoader.load_interactive(scene_path)
	if loader == null:
		push_error("Failed to start loading scene: " + str(scene_path))
		return
	_loader = loader
	_is_loading = true
	_set_loading_ui(true)
	_update_loading_bar()
	set_process(true)


func _poll_loader():
	if _loader == null:
		return
	var err = _loader.poll()
	if err == OK:
		_update_loading_bar()
		return
	if err == ERR_FILE_EOF:
		_update_loading_bar()
		if _loading_bar != null:
			_loading_bar.value = 100.0
		if not _finish_requested:
			_finish_requested = true
			set_process(false)
			call_deferred("_finish_loading")
		return
	_log_loader_error(err)
	push_error("Loading failed with error code: " + str(err))
	_cancel_loading()


func _update_loading_bar():
	if _loading_bar == null or _loader == null:
		return
	var total = _loader.get_stage_count()
	if total <= 0:
		return
	var progress = float(_loader.get_stage()) / float(total)
	_loading_bar.value = clamp(progress * 100.0, 0.0, 100.0)


func _finish_loading():
	_finish_requested = false
	if _loader == null:
		_set_loading_ui(false)
		return
	var packed = _loader.get_resource()
	_loader = null
	set_process(false)
	_is_loading = false
	if packed == null or not (packed is PackedScene):
		push_error("Loaded resource is not a PackedScene.")
		_set_loading_ui(false)
		return

	var controller = GameGlobal.get_game_controller()
	if controller != null and controller.has_method("change_world3d_scene_from_packed"):
		controller.change_world3d_scene_from_packed(packed)
	else:
		var _error = get_tree().change_scene_to(packed)


func _cancel_loading():
	_loader = null
	set_process(false)
	_is_loading = false
	_finish_requested = false
	_set_loading_ui(false)


func _set_loading_ui(enabled):
	if _loading_label != null:
		_loading_label.visible = enabled
	if _loading_bar != null:
		_loading_bar.visible = enabled
		if enabled:
			_loading_bar.value = 0.0
	for button in _menu_buttons:
		if button != null:
			button.disabled = enabled


func _log_loader_error(err):
	var platform = OS.get_name()
	var stage = 0
	var total = 0
	if _loader != null:
		stage = _loader.get_stage()
		total = _loader.get_stage_count()
	if platform == "Vita":
		print("[Vita][Loader] error=", err, " stage=", stage, "/", total, " path=", MAIN_MENU_PATH)
	else:
		print("[Loader] error=", err, " stage=", stage, "/", total, " path=", MAIN_MENU_PATH)

