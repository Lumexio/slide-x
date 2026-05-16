extends Spatial


const ENV_SCENE_PATH = "res://scenes/levels/level_1_env.tscn"

onready var _env_anchor: Spatial = $"EnvAnchor"
onready var _env_loading_label: Label = $"CanvasLayer/EnvLoadingLabel"
var _env_loader: ResourceInteractiveLoader = null
export(float) var memory_sample_interval := 0.3
export(float) var memory_post_attach_window := 2.0
var _memory_sample_accum := 0.0
var _memory_peak_static := 0.0
var _memory_peak_dynamic := 0.0
var _memory_peak_vram := 0.0
var _memory_peak_tex := 0.0
var _memory_peak_vtx := 0.0
var _memory_post_attach_remaining := 0.0
var _memory_post_attach_active := false


func _ready() -> void:
	set_process(false)
	_set_env_loading_visible(false)
	call_deferred("_start_env_load")


func _process(_delta: float) -> void:
	if _env_loader == null:
		return
	_memory_sample_accum += _delta
	if _memory_sample_accum >= memory_sample_interval:
		_memory_sample_accum = 0.0
		_sample_memory_peak()
	var err = _env_loader.poll()
	if err == OK:
		return
	if err == ERR_FILE_EOF:
		var packed = _env_loader.get_resource()
		_env_loader = null
		_instance_env(packed)
		_set_env_loading_visible(false)
		_start_post_attach_sampling()
		set_process(false)
		return
	push_error("Env load failed with error code: " + str(err))
	_env_loader = null
	_set_env_loading_visible(false)
	set_process(false)


func _start_env_load() -> void:
	if _env_loader != null:
		return
	_reset_memory_peak()
	_env_loader = ResourceLoader.load_interactive(ENV_SCENE_PATH)
	if _env_loader == null:
		push_error("Failed to start env loading: " + str(ENV_SCENE_PATH))
		_set_env_loading_visible(false)
		return
	_sample_memory_peak()
	_set_env_loading_visible(true)
	set_process(true)


func _instance_env(packed: PackedScene) -> void:
	if packed == null or not (packed is PackedScene):
		push_error("Env resource is not a PackedScene.")
		return
	var instance = packed.instance()
	if instance == null:
		push_error("Failed to instance env scene.")
		return
	if _env_anchor != null:
		_env_anchor.add_child(instance)
	else:
		add_child(instance)


func _set_env_loading_visible(visible: bool) -> void:
	if _env_loading_label != null:
		_env_loading_label.visible = visible


func _start_post_attach_sampling() -> void:
	_memory_post_attach_remaining = memory_post_attach_window
	_memory_post_attach_active = true
	set_process(true)
	call_deferred("_poll_post_attach_sampling")


func _poll_post_attach_sampling() -> void:
	while _memory_post_attach_active:
		yield(get_tree().create_timer(memory_sample_interval), "timeout")
		_memory_post_attach_remaining -= memory_sample_interval
		_sample_memory_peak()
		if _memory_post_attach_remaining <= 0.0:
			_memory_post_attach_active = false
			_print_memory_peak()
			set_process(false)


func _reset_memory_peak() -> void:
	_memory_sample_accum = 0.0
	_memory_peak_static = 0.0
	_memory_peak_dynamic = 0.0
	_memory_peak_vram = 0.0
	_memory_peak_tex = 0.0
	_memory_peak_vtx = 0.0


func _sample_memory_peak() -> void:
	var static_mb = OS.get_static_memory_usage() / 1024.0 / 1024.0
	var dynamic_mb = OS.get_dynamic_memory_usage() / 1024.0 / 1024.0
	var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var tex_mb = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0
	var vtx_mb = Performance.get_monitor(Performance.RENDER_VERTEX_MEM_USED) / 1024.0 / 1024.0
	_memory_peak_static = max(_memory_peak_static, static_mb)
	_memory_peak_dynamic = max(_memory_peak_dynamic, dynamic_mb)
	_memory_peak_vram = max(_memory_peak_vram, vram_mb)
	_memory_peak_tex = max(_memory_peak_tex, tex_mb)
	_memory_peak_vtx = max(_memory_peak_vtx, vtx_mb)


func _print_memory_peak() -> void:
	var scene_path := "unknown"
	if get_tree() != null and get_tree().current_scene != null:
		scene_path = get_tree().current_scene.filename
	print("ENV peak scene=", scene_path,
			" RAM static=", _memory_peak_static, "MB  dynamic=", _memory_peak_dynamic,
			"MB  VRAM=", _memory_peak_vram, "MB  tex=", _memory_peak_tex, "MB  vtx=",
			_memory_peak_vtx, "MB")
