extends Control


export(String, FILE, "*.tscn") var target_scene_path := ""
export(int) var time_budget_msec := 8

onready var progress: ProgressBar = $"ProgressBar"
onready var status: Label = $"StatusLabel"

var loader: ResourceInteractiveLoader = null


func set_target_scene(path: String) -> void:
	target_scene_path = path


func _ready() -> void:
	if target_scene_path == "":
		if GameGlobal != null and GameGlobal.has_method("consume_pending_scene_path"):
			target_scene_path = GameGlobal.consume_pending_scene_path()
	if target_scene_path == "":
		push_error("No target_scene_path set.")
		return
	if status != null:
		status.text = "Loading..."
	loader = ResourceLoader.load_interactive(target_scene_path)
	if loader == null:
		push_error("Failed to start loader: " + str(target_scene_path))
		return
	if progress != null:
		progress.value = 0.0
	set_process(true)


func _process(_delta: float) -> void:
	if loader == null:
		return
	var start = OS.get_ticks_msec()
	while OS.get_ticks_msec() - start < time_budget_msec:
		var err = loader.poll()
		if err == OK:
			var stage = loader.get_stage()
			var total = max(loader.get_stage_count(), 1)
			var pct = float(stage) / float(total) * 100.0
			if progress != null:
				progress.value = pct
		elif err == ERR_FILE_EOF:
			if progress != null:
				progress.value = 100.0
			var packed = loader.get_resource()
			loader = null
			call_deferred("_swap_scene", packed)
			set_process(false)
			return
		else:
			push_error("Loader error: " + str(err))
			loader = null
			set_process(false)
			return


func _swap_scene(packed: PackedScene) -> void:
	if packed == null or not (packed is PackedScene):
		push_error("Loaded resource is not a PackedScene.")
		return
	get_tree().change_scene_to(packed)
