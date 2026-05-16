extends Spatial


onready var _menu_buttons: Array = [
	$"TaskBar/FairyFire",
	$"TaskBar/AkimboBoy",
	$"TaskBar/Kinetic Chad",
	$"TaskBar/<- Back",
	$"Start Game",
]
onready var _loading_bar: ProgressBar = $"WindowStartGame/LoadingBar"
onready var _loading_label: Label = $"WindowStartGame/LoadingLabel"
onready var _back_loading_bar: ProgressBar = $"TaskBar/BackLoadingBar"
onready var _back_loading_label: Label = $"TaskBar/BackLoadingLabel"
onready var _character_loading_label: Label = $"TaskBar/CharacterLoadingLabel"
onready var _character_anchor: Spatial = $"CharacterAnchor"

var current_character := ""
var _focus_index := 0
var _loader: ResourceInteractiveLoader = null
var _is_loading := false
var _finish_requested := false
var _active_loading_bar: ProgressBar = null
var _active_loading_label: Label = null
var _current_scene_path := ""
var _character_loader: ResourceInteractiveLoader = null
var _character_finish_requested := false
var _character_scene_path := ""
var _character_instance: Spatial = null
var _character_anim_player: AnimationPlayer = null
var _available_anim_names: Array = []
var _anim_index := 0
var _character_transition_tween: Tween = null
var _transition_old_instance: Spatial = null
var _pending_character_direction := 0
var _pending_character_animate := true
var _level_preload_loader: ResourceInteractiveLoader = null
var _level_preload_packed: PackedScene = null
var _character_cache := {}
var _character_cache_order: Array = []
var _character_load_start_msec := 0
var _character_load_elapsed_msec := 0
var _character_last_sample_msec := 0
var _character_memory_peak_static := 0.0
var _character_memory_peak_dynamic := 0.0
var _character_memory_peak_vram := 0.0
var _character_memory_peak_tex := 0.0
var _character_memory_peak_vtx := 0.0
var _character_post_attach_remaining := 0.0
var _character_post_attach_token := 0
var _character_last_loaded_from_cache := false
var _loading_show_start_msec := 0
var _loading_finish_ready_msec := 0
var _pending_packed: PackedScene = null
var _character_loading_show_start_msec := 0
var _character_loading_hide_ready_msec := 0
var _character_loading_pending_hide := false

export(bool) var use_menu_lod := true
export(int) var character_cache_limit := 1
export(float) var character_memory_sample_interval := 0.2
export(float) var character_memory_post_attach_window := 1.0
export(bool) var menu_character_optimize := true
export(bool) var menu_character_hide_joints := true
export(bool) var menu_character_disable_shadows := true

const CHARACTER_ORDER = ["AkimboBoy", "KineticChad", "FairyFire"]
const CHARACTER_SCENES = {
	"AkimboBoy": "res://scenes/characters/menu/AkimboBoy.tscn",
	"KineticChad": "res://scenes/characters/menu/KineticChad.tscn",
	"FairyFire": "res://scenes/characters/menu/FairyFire.tscn",
}
const CHARACTER_LOD_SCENES = {
	"AkimboBoy": "res://scenes/characters/menu_lod/AkimboBoy.tscn",
	"KineticChad": "res://scenes/characters/menu_lod/KineticChad.tscn",
	"FairyFire": "res://scenes/characters/menu_lod/FairyFire.tscn",
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
const CHARACTER_VISIBILITY_RANGE_BEGIN = 0.0
const CHARACTER_VISIBILITY_RANGE_END = 12.0
const LEVEL_SCENE_PATH = "res://scenes/levels/level_1.tscn"
const MAIN_MENU_SCENE_PATH = "res://gui/main_menu.tscn"
const LOADING_SCENE_PATH = "res://gui/loading_screen.tscn"
const LOADING_MIN_SHOW_MSEC := 200
const CHARACTER_LOADING_MIN_SHOW_MSEC := 200


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_select_character("AkimboBoy", false)
	_focus_index = _find_initial_focus_index()
	_apply_focus()
	_update_process_state()


func _select_character(character_name: String, animate: bool = true) -> void:
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


func _unhandled_input(event: InputEvent) -> void:
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


func _process(_delta: float) -> void:
	if _loader != null:
		_poll_scene_loader()
	elif _pending_packed != null:
		_poll_packed_loading()
	elif _character_loader != null:
		_poll_character_loader()
	elif _level_preload_loader != null:
		_poll_level_preload()
	_maybe_finish_loading()
	_maybe_hide_character_loading()


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


func _begin_loading(scene_path: String, loading_bar: ProgressBar, loading_label: Label) -> void:
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
	_pending_packed = null
	_loading_show_start_msec = OS.get_ticks_msec()
	_loading_finish_ready_msec = _loading_show_start_msec + LOADING_MIN_SHOW_MSEC
	_finish_requested = false
	_set_loading_ui(true)
	_update_loading_bar()
	_update_process_state()


func _update_process_state() -> void:
	set_process(_loader != null or _pending_packed != null or _character_loader != null or _level_preload_loader != null or _character_loading_pending_hide)


func _poll_scene_loader() -> void:
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
			_loading_finish_ready_msec = _loading_show_start_msec + LOADING_MIN_SHOW_MSEC
		return
	_log_loader_error(err)
	push_error("Loading failed with error code: " + str(err))
	_cancel_loading()


func _start_character_loading(character_name: String) -> void:
	_invalidate_character_post_attach_sampling()
	_character_last_loaded_from_cache = false
	_character_load_start_msec = OS.get_ticks_msec()
	_character_load_elapsed_msec = 0
	_character_last_sample_msec = _character_load_start_msec
	_reset_character_memory_peak()
	_sample_character_memory_peak()
	_show_character_loading_ui()
	var scene_path = _resolve_character_scene_path(character_name)
	if scene_path == "":
		push_error("Unknown character scene: " + str(character_name))
		_request_character_loading_hide()
		return
	_character_scene_path = scene_path
	var cached := _get_cached_character_scene(scene_path)
	if cached != null:
		_character_loader = null
		_character_finish_requested = false
		var cached_instance := cached.instance()
		if cached_instance == null:
			push_error("Failed to instance cached character scene.")
			_request_character_loading_hide()
			_update_process_state()
			return
		_character_last_loaded_from_cache = true
		_instance_character(cached_instance)
		_character_load_elapsed_msec = OS.get_ticks_msec() - _character_load_start_msec
		_sample_character_memory_peak()
		_request_character_loading_hide()
		_start_character_post_attach_sampling()
		_start_level_preload()
		_update_process_state()
		return
	if _character_loader != null:
		_character_loader = null
		_character_finish_requested = false
	var loader = ResourceLoader.load_interactive(scene_path)
	if loader == null:
		push_error("Failed to start character load: " + str(scene_path))
		_request_character_loading_hide()
		return
	_character_loader = loader
	_character_finish_requested = false
	_update_process_state()


func _poll_character_loader() -> void:
	var now = OS.get_ticks_msec()
	var interval_msec = int(character_memory_sample_interval * 1000.0)
	if interval_msec <= 0:
		interval_msec = 1
	if now - _character_last_sample_msec >= interval_msec:
		_character_last_sample_msec = now
		_sample_character_memory_peak()
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


func _finish_character_loading() -> void:
	_character_finish_requested = false
	if _character_loader == null:
		return
	var packed = _character_loader.get_resource()
	_character_loader = null
	_update_process_state()
	if packed == null or not (packed is PackedScene):
		push_error("Character resource is not a PackedScene.")
		_request_character_loading_hide()
		return
	_cache_character_scene(_character_scene_path, packed)
	var instance = packed.instance()
	if instance == null:
		push_error("Failed to instance character scene.")
		_request_character_loading_hide()
		return
	_instance_character(instance)
	_character_load_elapsed_msec = OS.get_ticks_msec() - _character_load_start_msec
	_sample_character_memory_peak()
	_request_character_loading_hide()
	_start_character_post_attach_sampling()
	_start_level_preload()


func _start_level_preload() -> void:
	if _level_preload_loader != null or _level_preload_packed != null:
		return
	var loader = ResourceLoader.load_interactive(LEVEL_SCENE_PATH)
	if loader == null:
		push_error("Failed to start level preload: " + str(LEVEL_SCENE_PATH))
		return
	_level_preload_loader = loader
	_update_process_state()


func _poll_level_preload() -> void:
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


func _poll_packed_loading() -> void:
	if _active_loading_bar != null:
		_active_loading_bar.value = 100.0


func _maybe_finish_loading() -> void:
	var now = OS.get_ticks_msec()
	if _pending_packed != null:
		if now >= _loading_finish_ready_msec:
			_finish_loading_from_packed(_pending_packed)
		return
	if _finish_requested and now >= _loading_finish_ready_msec:
		_finish_loading()


func _maybe_hide_character_loading() -> void:
	if not _character_loading_pending_hide:
		return
	if _character_loader != null:
		return
	if OS.get_ticks_msec() < _character_loading_hide_ready_msec:
		return
	_set_character_loading_ui(false)
	_character_loading_pending_hide = false
	_update_process_state()


func _begin_loading_from_preload(loader: ResourceInteractiveLoader, scene_path: String, loading_bar: ProgressBar, loading_label: Label) -> void:
	if _character_loader != null:
		_cancel_character_loading()
	_loader = loader
	_is_loading = true
	_current_scene_path = scene_path
	_active_loading_bar = loading_bar
	_active_loading_label = loading_label
	_pending_packed = null
	_loading_show_start_msec = OS.get_ticks_msec()
	_loading_finish_ready_msec = _loading_show_start_msec + LOADING_MIN_SHOW_MSEC
	_finish_requested = false
	_set_loading_ui(true)
	_update_loading_bar()
	_update_process_state()


func _begin_loading_from_packed(packed: PackedScene, scene_path: String, loading_bar: ProgressBar, loading_label: Label) -> void:
	if _character_loader != null:
		_cancel_character_loading()
	_loader = null
	_pending_packed = packed
	_is_loading = true
	_current_scene_path = scene_path
	_active_loading_bar = loading_bar
	_active_loading_label = loading_label
	_loading_show_start_msec = OS.get_ticks_msec()
	_loading_finish_ready_msec = _loading_show_start_msec + LOADING_MIN_SHOW_MSEC
	_finish_requested = false
	_set_loading_ui(true)
	if _active_loading_bar != null:
		_active_loading_bar.value = 100.0
	_update_process_state()


func _load_level_from_packed(packed: PackedScene) -> void:
	if packed == null or not (packed is PackedScene):
		push_error("Level preload is not a PackedScene.")
		return
	var controller = GameGlobal.get_game_controller()
	if controller != null and controller.has_method("change_world3d_scene_from_packed"):
		controller.change_world3d_scene_from_packed(packed)
	else:
		var _error = get_tree().change_scene_to(packed)


func _resolve_character_scene_path(character_name: String) -> String:
	if use_menu_lod:
		var lod_path = CHARACTER_LOD_SCENES.get(character_name, "")
		if lod_path != "" and ResourceLoader.exists(lod_path):
			return lod_path
	return CHARACTER_SCENES.get(character_name, "")


func _get_cached_character_scene(scene_path: String) -> PackedScene:
	if character_cache_limit <= 0:
		return null
	var cached = _character_cache.get(scene_path, null)
	if cached != null and cached is PackedScene:
		_touch_character_cache(scene_path)
		return cached as PackedScene
	return null


func _cache_character_scene(scene_path: String, packed: PackedScene) -> void:
	if character_cache_limit <= 0:
		return
	if packed == null:
		return
	_character_cache[scene_path] = packed
	_touch_character_cache(scene_path)
	while _character_cache_order.size() > character_cache_limit:
		var evict_path = _character_cache_order[0]
		_character_cache_order.remove(0)
		_character_cache.erase(evict_path)


func _touch_character_cache(scene_path: String) -> void:
	var index = _character_cache_order.find(scene_path)
	if index != -1:
		_character_cache_order.remove(index)
	_character_cache_order.append(scene_path)


func _reset_character_memory_peak() -> void:
	_character_memory_peak_static = 0.0
	_character_memory_peak_dynamic = 0.0
	_character_memory_peak_vram = 0.0
	_character_memory_peak_tex = 0.0
	_character_memory_peak_vtx = 0.0


func _sample_character_memory_peak() -> void:
	var static_mb = OS.get_static_memory_usage() / 1024.0 / 1024.0
	var dynamic_mb = OS.get_dynamic_memory_usage() / 1024.0 / 1024.0
	var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var tex_mb = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0
	var vtx_mb = Performance.get_monitor(Performance.RENDER_VERTEX_MEM_USED) / 1024.0 / 1024.0
	_character_memory_peak_static = max(_character_memory_peak_static, static_mb)
	_character_memory_peak_dynamic = max(_character_memory_peak_dynamic, dynamic_mb)
	_character_memory_peak_vram = max(_character_memory_peak_vram, vram_mb)
	_character_memory_peak_tex = max(_character_memory_peak_tex, tex_mb)
	_character_memory_peak_vtx = max(_character_memory_peak_vtx, vtx_mb)


func _invalidate_character_post_attach_sampling() -> void:
	_character_post_attach_token += 1
	_character_post_attach_remaining = 0.0


func _start_character_post_attach_sampling() -> void:
	_invalidate_character_post_attach_sampling()
	if character_memory_post_attach_window <= 0.0:
		_print_character_metrics()
		return
	_character_post_attach_remaining = character_memory_post_attach_window
	var token = _character_post_attach_token
	call_deferred("_poll_character_post_attach_sampling", token)


func _poll_character_post_attach_sampling(token: int) -> void:
	var interval = character_memory_sample_interval
	if interval <= 0.0:
		interval = 0.05
	while token == _character_post_attach_token:
		yield(get_tree().create_timer(interval), "timeout")
		if token != _character_post_attach_token:
			return
		_character_post_attach_remaining -= interval
		_sample_character_memory_peak()
		if _character_post_attach_remaining <= 0.0:
			_print_character_metrics()
			return


func _print_character_metrics() -> void:
	var elapsed_ms = _character_load_elapsed_msec
	if elapsed_ms <= 0:
		elapsed_ms = OS.get_ticks_msec() - _character_load_start_msec
	var source = "load"
	if _character_last_loaded_from_cache:
		source = "cache"
	var lod_path = CHARACTER_LOD_SCENES.get(current_character, "")
	var is_lod = lod_path != "" and _character_scene_path == lod_path
	var prefix = "[MenuChar]"
	if OS.get_name() == "Vita":
		prefix = "[Vita][MenuChar]"
	print(prefix, " name=", current_character,
			" source=", source, " lod=", is_lod,
			" ms=", elapsed_ms, " scene=", _character_scene_path,
			" RAM static=", _character_memory_peak_static, "MB  dynamic=", _character_memory_peak_dynamic,
			"MB  VRAM=", _character_memory_peak_vram, "MB  tex=", _character_memory_peak_tex,
			"MB  vtx=", _character_memory_peak_vtx, "MB")


func _cancel_character_loading() -> void:
	_invalidate_character_post_attach_sampling()
	_character_loader = null
	_character_finish_requested = false
	_set_character_loading_ui(false)
	_character_loading_pending_hide = false
	_update_process_state()


func _instance_character(instance: Spatial) -> void:
	var old_instance = null
	if _character_instance != null and _character_instance.is_inside_tree():
		old_instance = _character_instance
	_character_instance = instance
	_character_instance.translation = Vector3.ZERO
	_character_instance.rotation = Vector3.ZERO
	if _character_anchor != null:
		_character_anchor.add_child(_character_instance)
	_normalize_character_nodes(_character_instance)
	_apply_character_visibility_range(_character_instance)
	if menu_character_optimize:
		_optimize_menu_character(_character_instance)
	_character_anim_player = _find_anim_player_with_idle(_character_instance)
	_available_anim_names = _build_preview_anim_list(_character_anim_player)
	_anim_index = 0
	_play_preview_anim()
	_apply_character_transition(old_instance)


func _update_loading_bar() -> void:
	if _active_loading_bar == null or _loader == null:
		return
	var total = _loader.get_stage_count()
	if total <= 0:
		return
	var progress = float(_loader.get_stage()) / float(total)
	_active_loading_bar.value = clamp(progress * 100.0, 0.0, 100.0)


func _finish_loading() -> void:
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


func _finish_loading_from_packed(packed: PackedScene) -> void:
	_pending_packed = null
	_finish_requested = false
	_is_loading = false
	if packed == null or not (packed is PackedScene):
		push_error("Loaded resource is not a PackedScene.")
		_set_loading_ui(false)
		_active_loading_bar = null
		_active_loading_label = null
		_update_process_state()
		return
	_load_level_from_packed(packed)
	_set_loading_ui(false)
	_active_loading_bar = null
	_active_loading_label = null
	_update_process_state()


func _cancel_loading() -> void:
	_loader = null
	_is_loading = false
	_finish_requested = false
	_pending_packed = null
	_set_loading_ui(false)
	_update_process_state()


func _set_loading_ui(enabled: bool) -> void:
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


func _set_character_loading_ui(enabled: bool) -> void:
	if _character_loading_label != null:
		_character_loading_label.visible = enabled


func _show_character_loading_ui() -> void:
	_character_loading_show_start_msec = OS.get_ticks_msec()
	_character_loading_hide_ready_msec = _character_loading_show_start_msec + CHARACTER_LOADING_MIN_SHOW_MSEC
	_character_loading_pending_hide = true
	_set_character_loading_ui(true)
	_update_process_state()


func _request_character_loading_hide() -> void:
	if OS.get_ticks_msec() >= _character_loading_hide_ready_msec:
		_set_character_loading_ui(false)
		_character_loading_pending_hide = false
		_update_process_state()
	else:
		_character_loading_pending_hide = true
		_update_process_state()


func _log_loader_error(err: int) -> void:
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


func _find_anim_player_with_idle(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer and node.has_animation("idle"):
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player_with_idle(child)
		if found != null:
			return found
	return null


func _build_preview_anim_list(anim_player: AnimationPlayer) -> Array:
	var result = []
	if anim_player == null:
		return result
	for name in PREVIEW_ANIMATIONS:
		if anim_player.has_animation(name):
			result.append(name)
	return result


func _play_preview_anim() -> void:
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


func _cycle_preview_anim(step: int) -> void:
	if _character_anim_player == null:
		return
	if _available_anim_names.size() == 0:
		return
	_anim_index = (_anim_index + step) % _available_anim_names.size()
	if _anim_index < 0:
		_anim_index += _available_anim_names.size()
	_play_preview_anim()


func _normalize_character_nodes(root: Node) -> void:
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


func _optimize_menu_character(root: Node) -> void:
	if root == null:
		return
	var stack = [root]
	while stack.size() > 0:
		var node = stack.pop_back()
		if node is MeshInstance:
			if menu_character_disable_shadows:
				node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			if menu_character_hide_joints:
				var node_name = str(node.name)
				if node_name.find("Alpha_Joints") != -1:
					node.visible = false
		for child in node.get_children():
			stack.append(child)


func _apply_character_visibility_range(root: Node) -> void:
	if root == null:
		return
	_apply_visibility_range_recursive(root, CHARACTER_VISIBILITY_RANGE_BEGIN, CHARACTER_VISIBILITY_RANGE_END)


func _apply_visibility_range_recursive(node: Node, range_begin: float, range_end: float) -> void:
	if node is VisualInstance:
		if _has_property(node, "visibility_range_begin"):
			node.set("visibility_range_begin", range_begin)
			node.set("visibility_range_end", range_end)
	for child in node.get_children():
		_apply_visibility_range_recursive(child, range_begin, range_end)


func _has_property(node: Object, prop_name: String) -> bool:
	for info in node.get_property_list():
		if info.name == prop_name:
			return true
	return false


func _sort_character_nodes_by_depth(a: Dictionary, b: Dictionary) -> bool:
	return int(a.depth) < int(b.depth)


func _apply_character_transition(old_instance: Spatial) -> void:
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


func _start_character_transition_tween(direction: int) -> void:
	_clear_character_transition_tween()
	var tween = Tween.new()
	add_child(tween)
	_character_transition_tween = tween
	if _transition_old_instance != null:
		var old_target = Vector3(-CHARACTER_SLIDE_DISTANCE * direction, 0, 0)
		tween.interpolate_property(_transition_old_instance, "translation", _transition_old_instance.translation, old_target, CHARACTER_SLIDE_TIME, Tween.TRANS_SINE, Tween.EASE_IN)
	tween.interpolate_property(_character_instance, "translation", _character_instance.translation, Vector3.ZERO, CHARACTER_SLIDE_TIME, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.start()
	var _connect_err: int = tween.connect("tween_all_completed", self, "_on_character_transition_done")


func _clear_character_transition_tween() -> void:
	if _character_transition_tween != null:
		var _stop_err: bool = _character_transition_tween.stop_all()
		_character_transition_tween.queue_free()
		_character_transition_tween = null


func _on_character_transition_done() -> void:
	if _transition_old_instance != null and _transition_old_instance.is_inside_tree():
		_transition_old_instance.queue_free()
	_transition_old_instance = null
	_clear_character_transition_tween()


func _on_AkimboBoy_pressed() -> void:
	_select_character("AkimboBoy")


func _on_Kinetic_Chad_pressed() -> void:
	_select_character("KineticChad")


func _on_FairyFire_pressed() -> void:
	_select_character("FairyFire")


func _on__Back_pressed() -> void:
	if _is_loading:
		return
	_begin_loading(MAIN_MENU_SCENE_PATH, _back_loading_bar, _back_loading_label)


func _on_Start_Game_pressed() -> void:
	if _is_loading:
		return
	if _level_preload_loader != null:
		var loader = _level_preload_loader
		_level_preload_loader = null
		_begin_loading_from_preload(loader, LEVEL_SCENE_PATH, _loading_bar, _loading_label)
		return
	if _level_preload_packed != null:
		_begin_loading_from_packed(_level_preload_packed, LEVEL_SCENE_PATH, _loading_bar, _loading_label)
		return
	_begin_loading(LEVEL_SCENE_PATH, _loading_bar, _loading_label)
