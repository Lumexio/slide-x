extends Node

# Signals for menu_character.gd to listen to
signal character_loaded(packed_scene)
signal character_load_failed(error_message)
signal character_load_progress  # Emitted when polling

# Public config (can be set by menu_character.gd)
var character_cache_limit := 1
var use_threaded_character_load := true

# Cache state
var _character_cache := {}
var _character_cache_order: Array = []

# Threading state
var _character_thread: Thread = null
var _character_thread_mutex: Mutex = null
var _character_thread_done := false
var _character_thread_error := ""
var _character_thread_packed: PackedScene = null
var _character_thread_token := 0
var _character_thread_result_token := -1
var _character_thread_scene_path := ""
var _character_thread_pending_scene_path := ""

# Interactive loading state
var _character_loader: ResourceInteractiveLoader = null
var _character_finish_requested := false

# Constants
const CHARACTER_ORDER = ["AkimboBoy", "KineticChad", "FairyFire"]
const CHARACTER_SCENES = {
	"AkimboBoy": "res://scenes/characters/menu/AkimboBoy.tscn",
	"KineticChad": "res://scenes/characters/menu/kinetic-chad.tscn",
	"FairyFire": "res://scenes/characters/menu/FairyFire.tscn",
}
const CHARACTER_LOD_SCENES = {
	"AkimboBoy": "res://scenes/characters/menu_lod/AkimboBoy.tscn",
	"KineticChad": "res://scenes/characters/menu_lod/KineticChad.tscn",
	"FairyFire": "res://scenes/characters/menu_lod/FairyFire.tscn",
}

var _use_menu_lod := true


func _ready() -> void:
	_character_thread_mutex = Mutex.new()


func set_menu_lod(enabled: bool) -> void:
	_use_menu_lod = enabled


func resolve_character_scene_path(character_name: String) -> String:
	if _use_menu_lod:
		var lod_path = CHARACTER_LOD_SCENES.get(character_name, "")
		if lod_path != "" and ResourceLoader.exists(lod_path):
			return lod_path
	return CHARACTER_SCENES.get(character_name, "")


func get_cached_character_scene(scene_path: String) -> PackedScene:
	if character_cache_limit <= 0:
		return null
	var cached = _character_cache.get(scene_path, null)
	if cached != null and cached is PackedScene:
		_touch_character_cache(scene_path)
		return cached as PackedScene
	return null


func cache_character_scene(scene_path: String, packed: PackedScene) -> void:
	if character_cache_limit <= 0:
		return
	if packed == null:
		return
	_character_cache[scene_path] = packed
	_touch_character_cache(scene_path)
	while _character_cache_order.size() > character_cache_limit:
		var evict_path = _character_cache_order[0]
		_character_cache_order.remove(0)
		var _erased = _character_cache.erase(evict_path)


func _touch_character_cache(scene_path: String) -> void:
	var index = _character_cache_order.find(scene_path)
	if index != -1:
		_character_cache_order.remove(index)
	_character_cache_order.append(scene_path)


func start_load(character_name: String, scene_path: String) -> void:
	if use_threaded_character_load:
		_start_character_thread(character_name, scene_path)
	else:
		_start_character_interactive(scene_path)


func start_interactive_load(scene_path: String) -> void:
	_start_character_interactive(scene_path)


func poll() -> void:
	if _character_loader != null:
		_poll_character_loader()
	elif _character_thread != null:
		_poll_character_thread()


func is_loading() -> bool:
	return _character_loader != null or _character_thread != null


func stop() -> void:
	_stop_character_thread()
	_character_loader = null
	_character_finish_requested = false


func _start_character_thread(_character_name: String, scene_path: String) -> void:
	if _character_thread != null:
		_character_thread_pending_scene_path = scene_path
		return
	if _character_thread_mutex == null:
		_character_thread_mutex = Mutex.new()
	_character_thread_token += 1
	_character_thread_scene_path = scene_path
	_character_thread_done = false
	_character_thread_error = ""
	_character_thread_packed = null
	_character_thread_result_token = -1
	_character_thread = Thread.new()
	var err = _character_thread.start(self, "_thread_load_character", {"scene_path": scene_path, "token": _character_thread_token})
	if err != OK:
		push_error("Failed to start character thread: " + str(err))
		_character_thread = null
		_start_character_interactive(scene_path)


func _thread_load_character(userdata) -> void:
	var scene_path = ""
	var token = 0
	if typeof(userdata) == TYPE_DICTIONARY:
		scene_path = str(userdata.get("scene_path", ""))
		token = int(userdata.get("token", 0))
	var loaded = null
	if scene_path != "":
		loaded = load(scene_path)
	var packed: PackedScene = null
	var err = ""
	if loaded == null or not (loaded is PackedScene):
		err = "Character preload is not a PackedScene: " + str(scene_path)
	else:
		packed = loaded
	_character_thread_mutex.lock()
	_character_thread_packed = packed
	_character_thread_error = err
	_character_thread_done = true
	_character_thread_result_token = token
	_character_thread_mutex.unlock()


func _poll_character_thread() -> void:
	if _character_thread == null:
		return
	var done = false
	var err = ""
	var packed: PackedScene = null
	var result_token = -1
	_character_thread_mutex.lock()
	done = _character_thread_done
	err = _character_thread_error
	packed = _character_thread_packed
	result_token = _character_thread_result_token
	_character_thread_mutex.unlock()
	if not done:
		return
	_character_thread.wait_to_finish()
	_character_thread = null
	_character_thread_done = false
	_character_thread_error = ""
	_character_thread_packed = null
	_character_thread_result_token = -1
	if result_token != _character_thread_token:
		_process_pending_character_thread_request()
		return
	if err != "":
		emit_signal("character_load_failed", err)
		_start_character_interactive(_character_thread_scene_path)
		_character_thread_pending_scene_path = ""
		return
	emit_signal("character_loaded", packed)
	_process_pending_character_thread_request()


func _process_pending_character_thread_request() -> void:
	if _character_thread_pending_scene_path == "":
		return
	var pending_scene = _character_thread_pending_scene_path
	_character_thread_pending_scene_path = ""
	_start_character_thread("", pending_scene)


func _stop_character_thread() -> void:
	if _character_thread == null:
		return
	_character_thread.wait_to_finish()
	_character_thread = null
	_character_thread_done = false
	_character_thread_error = ""
	_character_thread_packed = null
	_character_thread_result_token = -1


func _start_character_interactive(scene_path: String) -> void:
	if scene_path == "":
		emit_signal("character_load_failed", "Empty scene path")
		return
	_character_loader = null
	_character_finish_requested = false
	var loader = ResourceLoader.load_interactive(scene_path)
	if loader == null:
		push_error("Failed to start character load: " + str(scene_path))
		emit_signal("character_load_failed", "Failed to open file: " + scene_path)
		return
	_character_loader = loader


func _poll_character_loader() -> void:
	var err = _character_loader.poll()
	if err == OK:
		emit_signal("character_load_progress")
		return
	if err == ERR_FILE_EOF:
		if not _character_finish_requested:
			_character_finish_requested = true
			call_deferred("_finish_character_loading")
		return
	push_error("Character loading failed with error code: " + str(err))
	emit_signal("character_load_failed", "Load error: " + str(err))
	_character_loader = null


func _finish_character_loading() -> void:
	_character_finish_requested = false
	if _character_loader == null:
		return
	var packed = _character_loader.get_resource()
	_character_loader = null
	if packed != null and packed is PackedScene:
		emit_signal("character_loaded", packed)
	else:
		emit_signal("character_load_failed", "Loaded resource is not a PackedScene")
