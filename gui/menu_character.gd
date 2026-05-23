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
onready var _character_light: Light = $"SpotLight"
onready var _menu_env_anchor: Spatial = $"EnvAnchor"
onready var _menu_env_loading_label: Label = get_node_or_null("EnvCanvas/EnvLoadingLabel") as Label

var current_character := ""
var _focus_index := 0
var _loader: ResourceInteractiveLoader = null
var _is_loading := false
var _finish_requested := false
var _active_loading_bar: ProgressBar = null
var _active_loading_label: Label = null
var _current_scene_path := ""
var _character_scene_path := ""
var _character_instance: Spatial = null
var _character_anim_player: AnimationPlayer = null
var _available_anim_names: Array = []
var _anim_index := 0
var _level_preload_loader: ResourceInteractiveLoader = null
var _level_preload_packed: PackedScene = null
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
var _character_post_attach_last_sample_msec := 0
var _loading_show_start_msec := 0
var _loading_finish_ready_msec := 0
var _pending_packed: PackedScene = null
var _character_loading_show_start_msec := 0
var _character_loading_hide_ready_msec := 0
var _character_loading_pending_hide := false
var _level_thread: Thread = null
var _level_thread_mutex: Mutex = null
var _level_thread_done := false
var _level_thread_error := ""
var _level_thread_packed: PackedScene = null
var _waiting_for_level_preload := false
var _menu_env_loader: ResourceInteractiveLoader = null
var _menu_env_loaded := false

export(bool) var use_menu_lod := true
export(float) var character_memory_sample_interval := 0.2
export(float) var character_memory_post_attach_window := 1.0
export(bool) var menu_character_optimize := true
export(bool) var menu_character_hide_joints := true
export(bool) var menu_character_disable_shadows := true
export(bool) var use_threaded_level_load := true

const CHARACTER_PREVIEW_ROTATIONS = {
	"AkimboBoy": Vector3(0, 180, 0),
	"KineticChad": Vector3(0, 180, 0),
	"FairyFire": Vector3(0, 180, 0),
}
const PREVIEW_ANIMATIONS = [
	"idle",
	"walk",
	"run",
	"punch",
	"elbow",
	"kick",
	"punch-elbow",
	"punch-hard",
	"kick-tornado",
	"jumping",
	"jump-back",
]
const LEVEL_SCENE_PATH = "res://scenes/levels/level_1.tscn"
const MENU_ENV_SCENE_PATH = "res://scenes/levels/menu_env.tscn"
const MAIN_MENU_SCENE_PATH = "res://gui/main_menu.tscn"
const LOADING_SCENE_PATH = "res://gui/loading_screen.tscn"
const LOADING_MIN_SHOW_MSEC := 200
const CHARACTER_LOADING_MIN_SHOW_MSEC := 200


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_level_thread_mutex = Mutex.new()
	if MenuCharacterCache != null:
		MenuCharacterCache.character_cache_limit = 0
		MenuCharacterCache.use_threaded_character_load = true
		MenuCharacterCache.set_menu_lod(use_menu_lod)
		var _err_loaded = MenuCharacterCache.connect("character_loaded", self, "_on_character_cache_loaded")
		var _err_failed = MenuCharacterCache.connect("character_load_failed", self, "_on_character_cache_failed")
	_focus_index = _find_initial_focus_index()
	_apply_focus()
	_update_process_state()
	yield(get_tree(), "idle_frame")
	_select_character("AkimboBoy")


func _exit_tree() -> void:
	_stop_level_thread()
	if MenuCharacterCache != null:
		MenuCharacterCache.stop()


func _select_character(character_name: String) -> void:
	current_character = character_name
	_apply_character_light(character_name)
	_start_character_loading(character_name)


func _apply_character_light(character_name: String) -> void:
	if _character_light == null:
		return
	match character_name:
		"KineticChad":
			_character_light.light_color = Color(1, 0, 0, 1)
		"AkimboBoy":
			_character_light.light_color = Color(0, 1, 0, 1)
		"FairyFire":
			_character_light.light_color = Color(1, 0.4, 0.7, 1)
		_:
			pass


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


func _process(delta: float) -> void:
	if _loader != null:
		_poll_scene_loader()
	elif _pending_packed != null:
		_poll_packed_loading()
	elif MenuCharacterCache != null and MenuCharacterCache.is_loading():
		MenuCharacterCache.poll()
	elif _level_preload_loader != null:
		_poll_level_preload()
	elif _level_thread != null:
		_poll_level_thread()
	_maybe_finish_loading()
	_maybe_hide_character_loading()
	_poll_character_post_attach_sampling(delta)
	if _menu_env_loader != null:
		_poll_menu_env_loader()


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


func _start_menu_env_load() -> void:
	if _menu_env_loaded or _menu_env_loader != null:
		return
	if GameGlobal != null and GameGlobal.has_method("get_preloaded_scene"):
		var cached = GameGlobal.get_preloaded_scene(MENU_ENV_SCENE_PATH)
		if cached != null:
			_instance_menu_env(cached)
			_menu_env_loaded = true
			_set_menu_env_loading_visible(false)
			return
	var loader = ResourceLoader.load_interactive(MENU_ENV_SCENE_PATH)
	if loader == null:
		push_error("Failed to start menu environment loading: " + str(MENU_ENV_SCENE_PATH))
		_set_menu_env_loading_visible(false)
		return
	_menu_env_loader = loader
	_set_menu_env_loading_visible(true)
	_update_process_state()


func _poll_menu_env_loader() -> void:
	var err = _menu_env_loader.poll()
	if err == OK:
		return
	if err == ERR_FILE_EOF:
		var packed = _menu_env_loader.get_resource()
		_menu_env_loader = null
		_instance_menu_env(packed)
		_set_menu_env_loading_visible(false)
		_menu_env_loaded = true
		_update_process_state()
		return
	push_error("Menu environment load failed with error code: " + str(err))
	_menu_env_loader = null
	_set_menu_env_loading_visible(false)
	_update_process_state()


func _instance_menu_env(packed: PackedScene) -> void:
	if packed == null or not (packed is PackedScene):
		push_error("Menu environment resource is not a PackedScene.")
		return
	var instance = packed.instance()
	if instance == null:
		push_error("Failed to instance menu environment scene.")
		return
	if _menu_env_anchor != null:
		_menu_env_anchor.add_child(instance)
	else:
		add_child(instance)


func _set_menu_env_loading_visible(visible: bool) -> void:
	if _menu_env_loading_label != null:
		_menu_env_loading_label.visible = visible


func _update_process_state() -> void:
	set_process(_loader != null or _pending_packed != null or (MenuCharacterCache != null and MenuCharacterCache.is_loading()) or _level_preload_loader != null or _level_thread != null or _character_loading_pending_hide or _character_post_attach_remaining > 0.0 or _menu_env_loader != null)


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
	_log_vita_memory("character_load_begin " + character_name)
	var scene_path = ""
	if MenuCharacterCache != null:
		scene_path = MenuCharacterCache.resolve_character_scene_path(character_name)
	if scene_path == "":
		push_error("Unknown character scene: " + str(character_name))
		_request_character_loading_hide()
		return
	_character_scene_path = scene_path
	var cached: PackedScene = null
	if MenuCharacterCache != null:
		cached = MenuCharacterCache.get_cached_character_scene(scene_path)
	if cached == null and GameGlobal != null and GameGlobal.has_method("get_preloaded_scene"):
		cached = GameGlobal.get_preloaded_scene(scene_path)
		if cached != null and MenuCharacterCache != null:
			MenuCharacterCache.cache_character_scene(scene_path, cached)
	if cached != null:
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
		_log_vita_memory("character_load_cached " + character_name)
		_request_character_loading_hide()
		_start_character_post_attach_sampling()
		_start_level_preload()
		_start_menu_env_load()
		_update_process_state()
		return
	if MenuCharacterCache != null:
		MenuCharacterCache.start_load(character_name, scene_path)
	_update_process_state()


func _on_character_cache_loaded(packed: PackedScene) -> void:
	if packed == null or not (packed is PackedScene):
		push_error("Character resource is not a PackedScene.")
		_request_character_loading_hide()
		return
	if MenuCharacterCache != null:
		MenuCharacterCache.cache_character_scene(_character_scene_path, packed)
	var instance = packed.instance()
	if instance == null:
		push_error("Failed to instance character scene.")
		_request_character_loading_hide()
		return
	_instance_character(instance)
	_character_load_elapsed_msec = OS.get_ticks_msec() - _character_load_start_msec
	_sample_character_memory_peak()
	_log_vita_memory("character_load_done " + current_character)
	_request_character_loading_hide()
	_start_character_post_attach_sampling()
	_start_level_preload()
	_start_menu_env_load()


func _on_character_cache_failed(error_message: String) -> void:
	push_error("Character load failed: " + error_message)
	if MenuCharacterCache != null:
		MenuCharacterCache.start_interactive_load(_character_scene_path)
	_update_process_state()


func _start_level_preload() -> void:
	if _level_preload_loader != null or _level_preload_packed != null:
		return
	if use_threaded_level_load:
		_start_level_preload_thread()
		return
	var loader = ResourceLoader.load_interactive(LEVEL_SCENE_PATH)
	if loader == null:
		push_error("Failed to start level preload: " + str(LEVEL_SCENE_PATH))
		return
	_level_preload_loader = loader
	_update_process_state()


func _start_level_preload_thread() -> void:
	if _level_thread != null:
		return
	if _level_thread_mutex == null:
		_level_thread_mutex = Mutex.new()
	_level_thread_done = false
	_level_thread_error = ""
	_level_thread_packed = null
	_level_thread = Thread.new()
	var err = _level_thread.start(self, "_thread_load_level")
	if err != OK:
		push_error("Failed to start level preload thread: " + str(err))
		_level_thread = null
		return
	_update_process_state()


func _thread_load_level(_userdata = null) -> void:
	var loaded = load(LEVEL_SCENE_PATH)
	var packed: PackedScene = null
	var err = ""
	if loaded == null or not (loaded is PackedScene):
		err = "Level preload is not a PackedScene: " + str(LEVEL_SCENE_PATH)
	else:
		packed = loaded
	_level_thread_mutex.lock()
	_level_thread_packed = packed
	_level_thread_error = err
	_level_thread_done = true
	_level_thread_mutex.unlock()


func _poll_level_thread() -> void:
	if _level_thread == null:
		return
	var done = false
	var err = ""
	var packed: PackedScene = null
	_level_thread_mutex.lock()
	done = _level_thread_done
	err = _level_thread_error
	packed = _level_thread_packed
	_level_thread_mutex.unlock()
	if not done:
		return
	_level_thread.wait_to_finish()
	_level_thread = null
	_level_thread_done = false
	_level_thread_error = ""
	_level_thread_packed = null
	if err != "":
		push_error(err)
		_waiting_for_level_preload = false
		_cancel_loading()
		_update_process_state()
		return
	_level_preload_packed = packed
	if _waiting_for_level_preload:
		_waiting_for_level_preload = false
		_begin_loading_from_packed(_level_preload_packed, LEVEL_SCENE_PATH, _loading_bar, _loading_label)
	_update_process_state()


func _stop_level_thread() -> void:
	if _level_thread == null:
		return
	_level_thread.wait_to_finish()
	_level_thread = null
	_level_thread_done = false
	_level_thread_error = ""
	_level_thread_packed = null
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
	if MenuCharacterCache != null and MenuCharacterCache.is_loading():
		return
	if OS.get_ticks_msec() < _character_loading_hide_ready_msec:
		return
	_set_character_loading_ui(false)
	_character_loading_pending_hide = false
	_update_process_state()


func _begin_loading_from_preload(loader: ResourceInteractiveLoader, scene_path: String, loading_bar: ProgressBar, loading_label: Label) -> void:
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


func _begin_loading_wait_for_preload(scene_path: String, loading_bar: ProgressBar, loading_label: Label) -> void:
	_loader = null
	_pending_packed = null
	_is_loading = true
	_current_scene_path = scene_path
	_active_loading_bar = loading_bar
	_active_loading_label = loading_label
	_loading_show_start_msec = OS.get_ticks_msec()
	_loading_finish_ready_msec = _loading_show_start_msec + LOADING_MIN_SHOW_MSEC
	_finish_requested = false
	_set_loading_ui(true)
	_update_loading_bar()
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
	_character_post_attach_last_sample_msec = 0


func _start_character_post_attach_sampling() -> void:
	_invalidate_character_post_attach_sampling()
	if character_memory_post_attach_window <= 0.0:
		_print_character_metrics()
		return
	_character_post_attach_remaining = character_memory_post_attach_window
	_character_post_attach_last_sample_msec = OS.get_ticks_msec()
	_update_process_state()


func _poll_character_post_attach_sampling(delta: float) -> void:
	if _character_post_attach_remaining <= 0.0:
		return
	var interval = character_memory_sample_interval
	if interval <= 0.0:
		interval = 0.05
	var now = OS.get_ticks_msec()
	if now - _character_post_attach_last_sample_msec >= int(interval * 1000.0):
		_character_post_attach_last_sample_msec = now
		_sample_character_memory_peak()
	_character_post_attach_remaining -= delta
	if _character_post_attach_remaining <= 0.0:
		_character_post_attach_remaining = 0.0
		_print_character_metrics()
		_update_process_state()


func _print_character_metrics() -> void:
	var elapsed_ms = _character_load_elapsed_msec
	if elapsed_ms <= 0:
		elapsed_ms = OS.get_ticks_msec() - _character_load_start_msec
	var source = "cache" if _character_last_loaded_from_cache else "load"
	var prefix = "[Vita][MenuChar]" if OS.get_name() == "Vita" else "[MenuChar]"
	print(prefix, " name=", current_character,
			" source=", source,
			" ms=", elapsed_ms, " scene=", _character_scene_path,
			" RAM static=", _character_memory_peak_static, "MB  dynamic=", _character_memory_peak_dynamic,
			"MB  VRAM=", _character_memory_peak_vram, "MB  tex=", _character_memory_peak_tex,
			"MB  vtx=", _character_memory_peak_vtx, "MB")


func _cancel_character_loading() -> void:
	_invalidate_character_post_attach_sampling()
	if MenuCharacterCache != null:
		MenuCharacterCache.stop()
	_set_character_loading_ui(false)
	_character_loading_pending_hide = false
	_update_process_state()


func _instance_character(instance: Spatial) -> void:
	if _character_instance != null and _character_instance.is_inside_tree():
		_character_instance.queue_free()
	_character_instance = instance
	_character_instance.translation = Vector3.ZERO
	_character_instance.rotation = Vector3.ZERO
	_apply_character_rotation(_character_instance, current_character)
	if _character_anchor != null:
		_character_anchor.add_child(_character_instance)
	_normalize_character_nodes(_character_instance)
	if menu_character_optimize:
		_optimize_menu_character(_character_instance)
	_character_anim_player = _find_anim_player_with_idle(_character_instance)
	_available_anim_names = _build_preview_anim_list(_character_anim_player)
	_anim_index = 0
	_play_preview_anim()


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


func _log_vita_memory(tag: String) -> void:
	var static_mb = OS.get_static_memory_usage() / 1024.0 / 1024.0
	var dynamic_mb = OS.get_dynamic_memory_usage() / 1024.0 / 1024.0
	var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var tex_mb = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0
	var vtx_mb = Performance.get_monitor(Performance.RENDER_VERTEX_MEM_USED) / 1024.0 / 1024.0
	print("[Vita][MenuChar]", tag,
			" RAM static=", static_mb, "MB  dynamic=", dynamic_mb,
			"MB  VRAM=", vram_mb, "MB  tex=", tex_mb, "MB  vtx=", vtx_mb, "MB")


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


func _apply_character_rotation(instance: Spatial, character_name: String) -> void:
	if instance == null:
		return
	var rotation_degrees = CHARACTER_PREVIEW_ROTATIONS.get(character_name, null)
	if rotation_degrees == null:
		return
	instance.rotation_degrees = rotation_degrees


func _sort_character_nodes_by_depth(a: Dictionary, b: Dictionary) -> bool:
	return int(a.depth) < int(b.depth)


func _on_AkimboBoy_pressed() -> void:
	_select_character("AkimboBoy")


func _on_Kinetic_Chad_pressed() -> void:
	_select_character("KineticChad")


func _on_FairyFire_pressed() -> void:
	_select_character("FairyFire")


func _on__Back_pressed() -> void:
	if _is_loading:
		return
	_waiting_for_level_preload = false
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
	if use_threaded_level_load and _level_thread != null:
		_waiting_for_level_preload = true
		_begin_loading_wait_for_preload(LEVEL_SCENE_PATH, _loading_bar, _loading_label)
		return
	_begin_loading(LEVEL_SCENE_PATH, _loading_bar, _loading_label)
