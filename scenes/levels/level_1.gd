extends Spatial


const ENV_SCENE_PATH = "res://scenes/levels/level_1_env.tscn"

onready var _env_anchor = $"EnvAnchor"
var _env_loader = null


func _ready():
	set_process(false)
	call_deferred("_start_env_load")


func _process(_delta):
	if _env_loader == null:
		return
	var err = _env_loader.poll()
	if err == OK:
		return
	if err == ERR_FILE_EOF:
		var packed = _env_loader.get_resource()
		_env_loader = null
		_instance_env(packed)
		set_process(false)
		return
	push_error("Env load failed with error code: " + str(err))
	_env_loader = null
	set_process(false)


func _start_env_load():
	if _env_loader != null:
		return
	_env_loader = ResourceLoader.load_interactive(ENV_SCENE_PATH)
	if _env_loader == null:
		push_error("Failed to start env loading: " + str(ENV_SCENE_PATH))
		return
	set_process(true)


func _instance_env(packed):
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
