extends Spatial


onready var KineticChad=$"KineticChad"
onready var AkimboBoy=$"AkimboBoy"
onready var FairyFire=$"FairyFire"
onready var _menu_buttons = [
	$"TaskBar/FairyFire",
	$"TaskBar/AkimboBoy",
	$"TaskBar/Kinetic Chad",
	$"TaskBar/<- Back",
	$"Start Game",
]
onready var _loading_bar = $"WindowStartGame/LoadingBar"
onready var _loading_label = $"WindowStartGame/LoadingLabel"
onready var _back_loading_bar = $"TaskBar/BackLoadingBar"
onready var _back_loading_label = $"TaskBar/BackLoadingLabel"
var selection_tween = Tween.new()
var current_character = ""
var _focus_index = 0
var _loader = null
var _is_loading = false
var _finish_requested = false
var _active_loading_bar = null
var _active_loading_label = null
var _current_scene_path = ""

export var hide_unselected_characters = true

const CHARACTER_ORDER = ["AkimboBoy", "KineticChad", "FairyFire"]
onready var CHARACTER_NODES = [AkimboBoy, KineticChad, FairyFire]
const CHARACTER_SPACING = 3.0
const CHARACTER_MOVE_TIME = 0.35
const LEVEL_SCENE_PATH = "res://scenes/levels/level_1.tscn"
const MAIN_MENU_SCENE_PATH = "res://gui/main_menu.tscn"

# Called when the node enters the scene tree for the first time.
func _ready():
	add_child(selection_tween)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_select_character("AkimboBoy", false)
	_focus_index = _find_initial_focus_index()
	_apply_focus()
	set_process(false)
	


func _select_character(character_name, animate = true):
	current_character = character_name

	var selected_index = CHARACTER_ORDER.find(character_name)
	if selected_index == -1:
		return

	selection_tween.stop_all()
	selection_tween.remove_all()

	for index in range(CHARACTER_NODES.size()):
		var character = CHARACTER_NODES[index]
		var distance_from_selected = index - selected_index
		var target_x = distance_from_selected * CHARACTER_SPACING
		var target_translation = Vector3(target_x, character.translation.y, character.translation.z)

		if animate:
			selection_tween.interpolate_property(
				character,
				"translation",
				character.translation,
				target_translation,
				CHARACTER_MOVE_TIME,
				Tween.TRANS_QUAD,
				Tween.EASE_OUT
			)
		else:
			character.translation = target_translation
		_set_character_active(character, index == selected_index)

	if animate:
		selection_tween.start()

func _set_character_active(character, active):
	if character == null:
		return
	if hide_unselected_characters:
		character.visible = active
	var anim = _get_character_anim(character)
	if anim == null:
		return
	if active:
		if anim.has_animation("idle"):
			anim.play("idle")
		elif anim.current_animation != "":
			anim.play(anim.current_animation)
	else:
		anim.stop()

func _get_character_anim(character):
	return character.get_node_or_null("meele-guy/AnimationPlayer")

func _unhandled_input(event):
	if _is_loading:
		return
	if event.is_action_pressed("ui_cancel"):
		_on__Back_pressed()
		get_tree().set_input_as_handled()
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
		if _active_loading_bar != null:
			_active_loading_bar.value = 100.0
		if not _finish_requested:
			_finish_requested = true
			set_process(false)
			call_deferred("_finish_loading")
		return
	_log_loader_error(err)
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

func _begin_loading(scene_path, loading_bar, loading_label):
	var loader = ResourceLoader.load_interactive(scene_path)
	if loader == null:
		push_error("Failed to start loading scene: " + str(scene_path))
		return
	_loader = loader
	_is_loading = true
	_current_scene_path = scene_path
	_active_loading_bar = loading_bar
	_active_loading_label = loading_label
	_set_loading_ui(true)
	_update_loading_bar()
	set_process(true)

func _update_loading_bar():
	if _active_loading_bar == null or _loader == null:
		return
	var total = _loader.get_stage_count()
	if total <= 0:
		return
	var progress = float(_loader.get_stage()) / float(total)
	_active_loading_bar.value = clamp(progress * 100.0, 0.0, 100.0)

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
	if enabled:
		if _active_loading_label != null:
			_active_loading_label.visible = true
		if _active_loading_bar != null:
			_active_loading_bar.visible = true
			_active_loading_bar.value = 0.0
		if _loading_label != null and _loading_label != _active_loading_label:
			_loading_label.visible = false
		if _back_loading_label != null and _back_loading_label != _active_loading_label:
			_back_loading_label.visible = false
		if _loading_bar != null and _loading_bar != _active_loading_bar:
			_loading_bar.visible = false
		if _back_loading_bar != null and _back_loading_bar != _active_loading_bar:
			_back_loading_bar.visible = false
	else:
		if _loading_label != null:
			_loading_label.visible = false
		if _back_loading_label != null:
			_back_loading_label.visible = false
		if _loading_bar != null:
			_loading_bar.visible = false
		if _back_loading_bar != null:
			_back_loading_bar.visible = false
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
		print("[Vita][Loader] error=", err, " stage=", stage, "/", total, " path=", _current_scene_path)
	else:
		print("[Loader] error=", err, " stage=", stage, "/", total, " path=", _current_scene_path)


func _on_AkimboBoy_pressed():
	_select_character("AkimboBoy")

func _on_Kinetic_Chad_pressed():
	_select_character("KineticChad")

func _on_FairyFire_pressed():
	_select_character("FairyFire")


func _on__Back_pressed():
	if _is_loading:
		return
	_begin_loading(MAIN_MENU_SCENE_PATH, _back_loading_bar, _back_loading_label)

func _on_Start_Game_pressed():
	if _is_loading:
		return
	_begin_loading(LEVEL_SCENE_PATH, _loading_bar, _loading_label)
