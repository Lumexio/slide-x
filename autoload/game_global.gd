extends Node

var game_controller: Node = null
var pending_scene_path := ""

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
