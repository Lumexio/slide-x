extends Spatial


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
onready var _character_loading_label = $"TaskBar/CharacterLoadingLabel"
onready var _character_anchor = $"CharacterAnchor"

var current_character = ""
var _focus_index = 0
var _loader = null
var _is_loading = false
var _finish_requested = false
var _active_loading_bar = null
var _active_loading_label = null
var _current_scene_path = ""
var _character_loader = null
var _character_finish_requested = false
var _character_scene_path = ""
var _character_instance = null
var _character_anim_player = null
var _available_anim_names = []
var _anim_index = 0
var _character_transition_tween = null
var _transition_old_instance = null
var _pending_character_direction = 0
var _pending_character_animate = true
var _level_preload_loader = null
var _level_preload_packed = null

const CHARACTER_ORDER = ["AkimboBoy", "KineticChad", "FairyFire"]
const CHARACTER_SCENES = {
	"AkimboBoy": "res://scenes/characters/menu/AkimboBoy.tscn",
	"KineticChad": "res://scenes/characters/menu/KineticChad.tscn",
	"FairyFire": "res://scenes/characters/menu/FairyFire.tscn",
}
const PREVIEW_ANIMATIONS = [
	"idle",
	"walk",
	"run",
	"punch",
	"kick",
	"punch-elbow",
	"punch-hard",
	"kick-tornado",
	"jumping",
	"jump-back",
]
const CHARACTER_SLIDE_DISTANCE = 2.4
const CHARACTER_SLIDE_TIME = 0.25
const LEVEL_SCENE_PATH = "res://scenes/levels/level_1.tscn"
const MAIN_MENU_SCENE_PATH = "res://gui/main_menu.tscn"
const LOADING_SCENE_PATH = "res://gui/loading_screen.tscn"


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_select_character("AkimboBoy", false)
	_focus_index = _find_initial_focus_index()
	_apply_focus()
	_update_process_state()


func _select_character(character_name, animate = true):
	var old_index = CHARACTER_ORDER.find(current_character)
	var new_index = CHARACTER_ORDER.find(character_name)
	_pending_character_direction = 0
	if old_index != -1 and new_index != -1:
		if new_index > old_index:
			_pending_character_direction = 1
		elif new_index < old_index:
			_pending_character_direction = -1
	_pending_character_animate = animate
	current_character = character_name
	_start_character_loading(character_name)


func _unhandled_input(event):
	if _is_loading:
		return
	if event.is_action_pressed("ui_cancel"):
		_on__Back_pressed()
		get_tree().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == 4:
			_cycle_preview_anim(-1)
			get_tree().set_input_as_handled()
			return
		elif event.button_index == 5:
			_cycle_preview_anim(1)
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
	if _loader != null:
		_poll_scene_loader()
		return
	if _character_loader != null:
		_poll_character_loader()
		return
	if _level_preload_loader != null:
		_poll_level_preload()
		return


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
	if _character_loader != null:
		_cancel_character_loading()
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
	_update_process_state()


func _update_process_state():
	set_process(_loader != null or _character_loader != null or _level_preload_loader != null)


func _poll_scene_loader():
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
			call_deferred("_finish_loading")
		return
	_log_loader_error(err)
	push_error("Loading failed with error code: " + str(err))
	_cancel_loading()


func _start_character_loading(character_name):
	var scene_path = CHARACTER_SCENES.get(character_name, "")
	if scene_path == "":
		push_error("Unknown character scene: " + str(character_name))
		_set_character_loading_ui(false)
		return
	if _character_loader != null:
		_character_loader = null
		_character_finish_requested = false
	var loader = ResourceLoader.load_interactive(scene_path)
	if loader == null:
		push_error("Failed to start character load: " + str(scene_path))
		_set_character_loading_ui(false)
		return
	_character_loader = loader
	_character_scene_path = scene_path
	_character_finish_requested = false
	_set_character_loading_ui(true)
	_update_process_state()


func _poll_character_loader():
	var err = _character_loader.poll()
	if err == OK:
		return
	if err == ERR_FILE_EOF:
		if not _character_finish_requested:
			_character_finish_requested = true
			call_deferred("_finish_character_loading")
		return
	push_error("Character loading failed with error code: " + str(err))
	_cancel_character_loading()


func _finish_character_loading():
	_character_finish_requested = false
	if _character_loader == null:
		return
	var packed = _character_loader.get_resource()
	_character_loader = null
	_update_process_state()
	if packed == null or not (packed is PackedScene):
		push_error("Character resource is not a PackedScene.")
		_set_character_loading_ui(false)
		return
	var instance = packed.instance()
	if instance == null:
		push_error("Failed to instance character scene.")
		_set_character_loading_ui(false)
		return
	_instance_character(instance)
	_set_character_loading_ui(false)
	_start_level_preload()


func _start_level_preload():
	if _level_preload_loader != null or _level_preload_packed != null:
		return
	var loader = ResourceLoader.load_interactive(LEVEL_SCENE_PATH)
	if loader == null:
		push_error("Failed to start level preload: " + str(LEVEL_SCENE_PATH))
		return
	_level_preload_loader = loader
	_update_process_state()


func _poll_level_preload():
	var err = _level_preload_loader.poll()
	if err == OK:
		return
	if err == ERR_FILE_EOF:
		_level_preload_packed = _level_preload_loader.get_resource()
		_level_preload_loader = null
		_update_process_state()
		return
	push_error("Level preload failed with error code: " + str(err))
	_level_preload_loader = null
	_update_process_state()


func _begin_loading_from_preload(loader, scene_path, loading_bar, loading_label):
	if _character_loader != null:
		_cancel_character_loading()
	_loader = loader
	_is_loading = true
	_current_scene_path = scene_path
	_active_loading_bar = loading_bar
	_active_loading_label = loading_label
	_set_loading_ui(true)
	_update_loading_bar()
	_update_process_state()


func _load_level_from_packed(packed):
	if packed == null or not (packed is PackedScene):
		push_error("Level preload is not a PackedScene.")
		return
	var controller = GameGlobal.get_game_controller()
	if controller != null and controller.has_method("change_world3d_scene_from_packed"):
		controller.change_world3d_scene_from_packed(packed)
	else:
		var _error = get_tree().change_scene_to(packed)


func _cancel_character_loading():
	_character_loader = null
	_character_finish_requested = false
	_set_character_loading_ui(false)
	_update_process_state()


func _instance_character(instance):
	var old_instance = null
	if _character_instance != null and _character_instance.is_inside_tree():
		old_instance = _character_instance
	_character_instance = instance
	_character_instance.translation = Vector3.ZERO
	_character_instance.rotation = Vector3.ZERO
	if _character_anchor != null:
		_character_anchor.add_child(_character_instance)
	_normalize_character_nodes(_character_instance)
	_character_anim_player = _find_anim_player_with_idle(_character_instance)
	_available_anim_names = _build_preview_anim_list(_character_anim_player)
	_anim_index = 0
	_play_preview_anim()
	_apply_character_transition(old_instance)


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
	_is_loading = false
	if packed == null or not (packed is PackedScene):
		push_error("Loaded resource is not a PackedScene.")
		_set_loading_ui(false)
		return

	var controller = GameGlobal.get_game_controller()
	if controller != null and controller.has_method("change_world3d_scene_from_packed"):
		var unload_mode = controller.UnloadMode.DELETE
		if _current_scene_path == MAIN_MENU_SCENE_PATH:
			unload_mode = controller.UnloadMode.DETACH
		controller.change_world3d_scene_from_packed(packed, unload_mode)
	else:
		var _error = get_tree().change_scene_to(packed)
	_set_loading_ui(false)
	_active_loading_bar = null
	_active_loading_label = null
	_update_process_state()


func _cancel_loading():
	_loader = null
	_is_loading = false
	_finish_requested = false
	_set_loading_ui(false)
	_update_process_state()


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


func _set_character_loading_ui(enabled):
	if _character_loading_label != null:
		_character_loading_label.visible = enabled


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


func _find_anim_player_with_idle(node):
	if node is AnimationPlayer and node.has_animation("idle"):
		return node
	for child in node.get_children():
		var found = _find_anim_player_with_idle(child)
		if found != null:
			return found
	return null


func _build_preview_anim_list(anim_player):
	var result = []
	if anim_player == null:
		return result
	for name in PREVIEW_ANIMATIONS:
		if anim_player.has_animation(name):
			result.append(name)
	return result


func _play_preview_anim():
	if _character_anim_player == null:
		return
	if _available_anim_names.size() == 0:
		return
	if _anim_index < 0 or _anim_index >= _available_anim_names.size():
		_anim_index = 0
	var anim_name = _available_anim_names[_anim_index]
	var anim = _character_anim_player.get_animation(anim_name)
	if anim != null:
		anim.loop = true
	_character_anim_player.play(anim_name)


func _cycle_preview_anim(step):
	if _character_anim_player == null:
		return
	if _available_anim_names.size() == 0:
		return
	_anim_index = (_anim_index + step) % _available_anim_names.size()
	if _anim_index < 0:
		_anim_index += _available_anim_names.size()
	_play_preview_anim()


func _normalize_character_nodes(root):
	if root == null:
		return
	var root_name = str(root.name)
	var entries = []
	var stack = [root]
	while stack.size() > 0:
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
			var name_str = str(child.name)
			if name_str.find("@") == -1:
				continue
			var parts = name_str.split("@")
			if parts.size() < 2:
				continue
			if parts[0] != root_name:
				continue
			parts.remove(0)
			if parts.size() == 0:
				continue
			var new_name = parts[parts.size() - 1]
			var parent_parts = []
			for i in range(parts.size() - 1):
				parent_parts.append(parts[i])
			var parent_path = "/".join(parent_parts)
			entries.append({"node": child, "new_name": new_name, "parent_path": parent_path, "depth": parts.size() - 1})
	if entries.size() == 0:
		return
	entries.sort_custom(self, "_sort_character_nodes_by_depth")
	for entry in entries:
		var child_node = entry.node
		var target_parent = root
		if entry.parent_path != "":
			target_parent = root.get_node_or_null(entry.parent_path)
		if target_parent == null:
			continue
		child_node.name = entry.new_name
		if child_node.get_parent() != target_parent:
			child_node.get_parent().remove_child(child_node)
			target_parent.add_child(child_node)


func _sort_character_nodes_by_depth(a, b):
	return int(a.depth) < int(b.depth)


func _apply_character_transition(old_instance):
	if old_instance != null and old_instance.is_inside_tree():
		if not _pending_character_animate or _pending_character_direction == 0:
			old_instance.queue_free()
		else:
			_transition_old_instance = old_instance
	if _pending_character_animate and _pending_character_direction != 0:
		var start_offset = Vector3(CHARACTER_SLIDE_DISTANCE * _pending_character_direction, 0, 0)
		_character_instance.translation = start_offset
		_start_character_transition_tween(_pending_character_direction)
	else:
		_character_instance.translation = Vector3.ZERO
		_clear_character_transition_tween()


func _start_character_transition_tween(direction):
	_clear_character_transition_tween()
	var tween = Tween.new()
	add_child(tween)
	_character_transition_tween = tween
	if _transition_old_instance != null:
		var old_target = Vector3(-CHARACTER_SLIDE_DISTANCE * direction, 0, 0)
		tween.interpolate_property(_transition_old_instance, "translation", _transition_old_instance.translation, old_target, CHARACTER_SLIDE_TIME, Tween.TRANS_SINE, Tween.EASE_IN)
	tween.interpolate_property(_character_instance, "translation", _character_instance.translation, Vector3.ZERO, CHARACTER_SLIDE_TIME, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.start()
	tween.connect("tween_all_completed", self, "_on_character_transition_done")


func _clear_character_transition_tween():
	if _character_transition_tween != null:
		_character_transition_tween.stop_all()
		_character_transition_tween.queue_free()
		_character_transition_tween = null


func _on_character_transition_done():
	if _transition_old_instance != null and _transition_old_instance.is_inside_tree():
		_transition_old_instance.queue_free()
	_transition_old_instance = null
	_clear_character_transition_tween()


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
	GameGlobal.set_pending_scene_path(LEVEL_SCENE_PATH)
	var controller = GameGlobal.get_game_controller()
	if controller != null and controller.has_method("change_world3d_scene"):
		controller.change_world3d_scene(LOADING_SCENE_PATH)
	else:
		var _error = get_tree().change_scene(LOADING_SCENE_PATH)
