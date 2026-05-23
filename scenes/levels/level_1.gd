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
var _memory_post_attach_timer: Timer = null


func _ready() -> void:
	set_process(false)
	_set_env_loading_visible(false)
	_setup_post_attach_timer()
	call_deferred("_start_env_load")


func _exit_tree() -> void:
	_stop_post_attach_sampling()


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
	if GameGlobal != null and GameGlobal.has_method("get_preloaded_scene"):
		var cached = GameGlobal.get_preloaded_scene(ENV_SCENE_PATH)
		if cached != null:
			_instance_env(cached)
			_set_env_loading_visible(false)
			_start_post_attach_sampling()
			set_process(false)
			return
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
	if _memory_post_attach_timer != null:
		_memory_post_attach_timer.wait_time = _get_post_attach_interval()
		_memory_post_attach_timer.start()


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


func _setup_post_attach_timer() -> void:
	_memory_post_attach_timer = Timer.new()
	_memory_post_attach_timer.one_shot = false
	_memory_post_attach_timer.autostart = false
	_memory_post_attach_timer.wait_time = _get_post_attach_interval()
	add_child(_memory_post_attach_timer)
	var _connect_err = _memory_post_attach_timer.connect("timeout", self, "_on_post_attach_sample")


func _stop_post_attach_sampling() -> void:
	_memory_post_attach_active = false
	if _memory_post_attach_timer != null:
		_memory_post_attach_timer.stop()


func _on_post_attach_sample() -> void:
	if not _memory_post_attach_active:
		_stop_post_attach_sampling()
		return
	_memory_post_attach_remaining -= _memory_post_attach_timer.wait_time
	_sample_memory_peak()
	if _memory_post_attach_remaining <= 0.0:
		_stop_post_attach_sampling()
		_print_memory_peak()
		set_process(false)


func _get_post_attach_interval() -> float:
	if memory_sample_interval <= 0.0:
		return 0.05
	return memory_sample_interval
