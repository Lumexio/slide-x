extends Spatial


onready var _menu_buttons = [
	$"TaskBar/Quit",
	$"WindowStartGame/StartButton",
]

onready var _loading_bar = $"WindowStartGame/LoadingBar"

const NEXT_SCENE_PATH = "res://gui/menu_character.tscn"

var _focus_index = 0
var _loader = null
var _is_loading = false


# Called when the node enters the scene tree for the first time.
func _ready():
	_focus_index = 0
	_apply_focus()
	set_process(false)
	

func _unhandled_input(event):
	if _is_loading:
		return
	var move = 0
	if event.is_action_pressed("ui_left"):
		move = -1
	elif event.is_action_pressed("ui_right"):
		move = 1
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_DPAD_LEFT:
			move = -1
		elif event.button_index == JOY_DPAD_RIGHT:
			move = 1

	if move != 0:
		_cycle_focus(move)
		get_tree().set_input_as_handled()


func _process(_delta):
	if _loader == null:
		return
	var err = _loader.poll()
	if err == OK:
		_update_loading_bar()
		return
	if err == ERR_FILE_EOF:
		_update_loading_bar()
		_finish_loading()
		return
	push_error("Loading failed with error code: " + str(err))
	_cancel_loading()


func _find_initial_focus_index():
	return 0


func _apply_focus():
	if _menu_buttons.size() == 0:
		return
	var target = _menu_buttons[_focus_index]
	if target != null and target.is_inside_tree():
		target.grab_focus()


func _cycle_focus(step):
	if _menu_buttons.size() == 0:
		return
	_focus_index = (_focus_index + step) % _menu_buttons.size()
	if _focus_index < 0:
		_focus_index += _menu_buttons.size()
	_apply_focus()


func _begin_loading(scene_path):
	var loader = ResourceLoader.load_interactive(scene_path)
	if loader == null:
		push_error("Failed to start loading scene: " + str(scene_path))
		return
	_loader = loader
	_is_loading = true
	_set_loading_ui(true)
	_update_loading_bar()
	set_process(true)


func _update_loading_bar():
	if _loading_bar == null or _loader == null:
		return
	var total = _loader.get_stage_count()
	if total <= 0:
		return
	var progress = float(_loader.get_stage()) / float(total)
	_loading_bar.value = clamp(progress * 100.0, 0.0, 100.0)


func _finish_loading():
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
	_set_loading_ui(false)


func _set_loading_ui(enabled):
	if _loading_bar != null:
		_loading_bar.visible = enabled
		if enabled:
			_loading_bar.value = 0.0
	for button in _menu_buttons:
		if button != null:
			button.disabled = enabled





func _on_Start_pressed():
	if _is_loading:
		return
	_begin_loading(NEXT_SCENE_PATH)
		


func _on_Quit_pressed():
	get_tree().quit()
