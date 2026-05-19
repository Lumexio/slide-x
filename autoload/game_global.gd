extends Node

signal preload_progress(stage_name, stage_index, stage_count, item_index, item_count, overall_progress, scene_path)
signal preload_done
signal preload_stopped(reason)

var game_controller: Node = null
var pending_scene_path := ""
var preload_cache := {}
var _preload_started := false
var _preload_active := false
var _preload_stages: Array = []
var _preload_stage_index := 0
var _preload_item_index := -1
var _preload_total_items := 0
var _preload_loader: ResourceInteractiveLoader = null
var _preload_current_path := ""
var _preload_stage_name := ""
var preload_vram_cap_mb := 24.0
var preload_tex_cap_mb := 22.0

func set_game_controller(controller: Node) -> void:
	game_controller = controller

func get_game_controller() -> Node:
	if game_controller == null:
		push_error("GameController is not initialized yet.")
		return null
	if not is_instance_valid(game_controller):
		push_error("GameController reference is no longer valid.")
		game_controller = null
		return null
	return game_controller


func set_pending_scene_path(scene_path: String) -> void:
	pending_scene_path = scene_path


func consume_pending_scene_path() -> String:
	var path = pending_scene_path
	pending_scene_path = ""
	return path


func start_staged_preload() -> void:
	if _preload_started:
		return
	_preload_started = true
	_build_preload_stages()
	_preload_total_items = _count_preload_items()
	_preload_stage_index = 0
	_preload_item_index = -1
	_preload_active = true
	_start_next_preload()


func get_preloaded_scene(scene_path: String) -> PackedScene:
	var cached = preload_cache.get(scene_path, null)
	if cached != null and cached is PackedScene:
		return cached as PackedScene
	return null


func _build_preload_stages() -> void:
	var menu_paths = ["res://gui/menu_character.tscn"]
	var character_paths = [
		"res://scenes/characters/menu_lod/AkimboBoy.tscn",
		"res://scenes/characters/menu_lod/KineticChad.tscn",
		"res://scenes/characters/menu_lod/FairyFire.tscn",
		"res://scenes/characters/menu/kinetic-chad.tscn",
	]
	var level_env_paths = ["res://scenes/levels/level_1_env.tscn"]
	_preload_stages = [
		{"name": "menu", "paths": _filter_existing_paths(menu_paths)},
		{"name": "characters", "paths": _filter_existing_paths(character_paths)},
		{"name": "level_env", "paths": _filter_existing_paths(level_env_paths)},
	]


func _filter_existing_paths(paths: Array) -> Array:
	var result: Array = []
	var seen := {}
	for path in paths:
		if path == "" or seen.has(path):
			continue
		if ResourceLoader.exists(path):
			result.append(path)
			seen[path] = true
	return result


func _count_preload_items() -> int:
	var total := 0
	for stage in _preload_stages:
		var items = stage.get("paths", [])
		if items is Array:
			total += items.size()
	return total


func _start_next_preload() -> void:
	while _preload_stage_index < _preload_stages.size():
		var stage = _preload_stages[_preload_stage_index]
		var paths: Array = stage.get("paths", [])
		_preload_stage_name = str(stage.get("name", "stage"))
		if _preload_item_index + 1 < paths.size():
			_preload_item_index += 1
			_preload_current_path = str(paths[_preload_item_index])
			if preload_cache.has(_preload_current_path):
				_emit_preload_progress()
				continue
			var loader = ResourceLoader.load_interactive(_preload_current_path)
			if loader == null:
				_emit_preload_progress()
				continue
			_preload_loader = loader
			set_process(true)
			return
		_preload_stage_index += 1
		_preload_item_index = -1
	_preload_active = false
	set_process(false)
	emit_signal("preload_done")


func _emit_preload_progress() -> void:
	var done_items := 0
	for i in range(_preload_stage_index):
		var stage = _preload_stages[i]
		var items = stage.get("paths", [])
		if items is Array:
			done_items += items.size()
	if _preload_item_index >= 0:
		done_items += _preload_item_index
	var total = max(_preload_total_items, 1)
	var overall = float(done_items) / float(total)
	emit_signal(
		"preload_progress",
		_preload_stage_name,
		_preload_stage_index,
		_preload_stages.size(),
		_preload_item_index,
		_preload_total_items,
		overall,
		_preload_current_path
	)


func _process(_delta: float) -> void:
	if _preload_loader == null:
		return
	var err = _preload_loader.poll()
	if err == OK:
		return
	if err == ERR_FILE_EOF:
		var packed = _preload_loader.get_resource()
		_preload_loader = null
		if packed != null and packed is PackedScene:
			preload_cache[_preload_current_path] = packed
		_emit_preload_progress()
		if _is_over_preload_cap():
			_preload_active = false
			set_process(false)
			emit_signal("preload_stopped", "memory_cap")
			return
		_start_next_preload()
		return
	_preload_loader = null
	_emit_preload_progress()
	_start_next_preload()


func _is_over_preload_cap() -> bool:
	if OS.get_name() != "Vita":
		return false
	var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var tex_mb = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0
	if preload_vram_cap_mb > 0.0 and vram_mb > preload_vram_cap_mb:
		return true
	if preload_tex_cap_mb > 0.0 and tex_mb > preload_tex_cap_mb:
		return true
	return false


func _print_memory() -> void:
	var static_mb = OS.get_static_memory_usage() / 1024.0 / 1024.0
	var dynamic_mb = OS.get_dynamic_memory_usage() / 1024.0 / 1024.0

	var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var tex_mb = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0
	var vtx_mb = Performance.get_monitor(Performance.RENDER_VERTEX_MEM_USED) / 1024.0 / 1024.0

	print("RAM static=", static_mb, "MB  dynamic=", dynamic_mb, "MB",
		  "  VRAM=", vram_mb, "MB  tex=", tex_mb, "MB  vtx=", vtx_mb, "MB")

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.one_shot = false
	add_child(t)
	t.connect("timeout", self, "_print_memory")
