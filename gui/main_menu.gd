extends Spatial


onready var _menu_buttons: Array = [
	$"TaskBar/Quit",
	$"WindowStartGame/StartButton",
]

onready var _loading_bar: ProgressBar = $"WindowStartGame/LoadingBar"
onready var _loading_label: Label = $"WindowStartGame/LoadingLabel"

const NEXT_SCENE_PATH = "res://gui/menu_character.tscn"
const LOADING_SCENE_PATH = "res://gui/loading_screen.tscn"

var _focus_index := 0
var _loader: ResourceInteractiveLoader = null
var _is_loading := false
var _finish_requested := false
var _preload_loader: ResourceInteractiveLoader = null
var _preload_packed: PackedScene = null
var _preload_started_msec := 0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_focus_index = 0
	_apply_focus()
	_start_preload()
	

func _unhandled_input(event: InputEvent) -> void:
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


func _process(_delta: float) -> void:
	if _loader != null:
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
		return

	if _preload_loader != null:
		var preload_err = _preload_loader.poll()
		if preload_err == OK:
			return
		if preload_err == ERR_FILE_EOF:
			_preload_packed = _preload_loader.get_resource()
			_preload_loader = null
			set_process(false)
			return
		push_error("Preload failed with error code: " + str(preload_err))
		_preload_loader = null
		set_process(false)


func _find_initial_focus_index() -> int:
	return 0


func _apply_focus() -> void:
	if _menu_buttons.size() == 0:
		return
	var target = _menu_buttons[_focus_index]
	if target != null and target.is_inside_tree():
		target.grab_focus()


func _cycle_focus(step: int) -> void:
	if _menu_buttons.size() == 0:
		return
	_focus_index = (_focus_index + step) % _menu_buttons.size()
	if _focus_index < 0:
		_focus_index += _menu_buttons.size()
	_apply_focus()


func _begin_loading(scene_path: String) -> void:
	if _preload_loader != null:
		_loader = _preload_loader
		_preload_loader = null
	else:
		var loader = ResourceLoader.load_interactive(scene_path)
		if loader == null:
			push_error("Failed to start loading scene: " + str(scene_path))
			return
		_loader = loader
	_is_loading = true
	_set_loading_ui(true)
	_update_loading_bar()
	set_process(true)

func _start_preload() -> void:
	if _preload_loader != null or _preload_packed != null:
		return
	_preload_started_msec = OS.get_ticks_msec()
	_preload_loader = ResourceLoader.load_interactive(NEXT_SCENE_PATH)
	if _preload_loader == null:
		push_error("Failed to start preload for scene: " + str(NEXT_SCENE_PATH))
		return
	set_process(true)


func _update_loading_bar() -> void:
	if _loading_bar == null or _loader == null:
		return
	var total = _loader.get_stage_count()
	if total <= 0:
		return
	var progress = float(_loader.get_stage()) / float(total)
	_loading_bar.value = clamp(progress * 100.0, 0.0, 100.0)


func _finish_loading() -> void:
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


func _cancel_loading() -> void:
	_loader = null
	set_process(false)
	_is_loading = false
	_finish_requested = false
	_set_loading_ui(false)


func _set_loading_ui(enabled: bool) -> void:
	if _loading_label != null:
		_loading_label.visible = enabled
	if _loading_bar != null:
		_loading_bar.visible = enabled
		if enabled:
			_loading_bar.value = 0.0
	for button in _menu_buttons:
		if button != null:
			button.disabled = enabled


func _log_loader_error(err: int) -> void:
	var platform = OS.get_name()
	var stage = 0
	var total = 0
	if _loader != null:
		stage = _loader.get_stage()
		total = _loader.get_stage_count()
	if platform == "Vita":
		print("[Vita][Loader] error=", err, " stage=", stage, "/", total, " path=", NEXT_SCENE_PATH)
	else:
		print("[Loader] error=", err, " stage=", stage, "/", total, " path=", NEXT_SCENE_PATH)





func _on_Start_pressed() -> void:
	if _is_loading:
		return
	var controller = GameGlobal.get_game_controller()
	if controller != null and controller.has_method("has_detached_scene"):
		if controller.has_detached_scene("world3d", NEXT_SCENE_PATH):
			controller.change_world3d_scene(NEXT_SCENE_PATH)
			return
	if _preload_packed != null:
		if controller != null and controller.has_method("change_world3d_scene_from_packed"):
			controller.change_world3d_scene_from_packed(_preload_packed)
		else:
			var _error = get_tree().change_scene_to(_preload_packed)
		return
	GameGlobal.set_pending_scene_path(NEXT_SCENE_PATH)
	if controller != null and controller.has_method("change_world3d_scene"):
		controller.change_world3d_scene(LOADING_SCENE_PATH)
	else:
		var _error = get_tree().change_scene(LOADING_SCENE_PATH)
		


func _on_Quit_pressed() -> void:
	get_tree().quit()
