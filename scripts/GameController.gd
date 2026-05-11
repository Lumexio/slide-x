extends Node

enum UnloadMode {
	DELETE,
	HIDE,
	DETACH
}

export (NodePath) var world3d_path
export (NodePath) var world2d_path
export (NodePath) var ui_path

var world3d_container = null
var world2d_container = null
var ui_container = null

var current_world3d_scene = null
var current_world2d_scene = null
var current_ui_scene = null

var detached_world3d_scene = null
var detached_world2d_scene = null
var detached_ui_scene = null

func _ready():
	world3d_container = get_node(world3d_path)
	world2d_container = get_node(world2d_path)
	ui_container = get_node(ui_path)
	GameGlobal.set_game_controller(self)
	change_world3d_scene("res://gui/main_menu.tscn", UnloadMode.DELETE)

func change_world3d_scene(scene_path, unload_mode = UnloadMode.DELETE):
	current_world3d_scene = _change_scene(
		scene_path,
		world3d_container,
		current_world3d_scene,
		"world3d",
		unload_mode
	)

func change_world2d_scene(scene_path, unload_mode = UnloadMode.DELETE):
	current_world2d_scene = _change_scene(
		scene_path,
		world2d_container,
		current_world2d_scene,
		"world2d",
		unload_mode
	)

func change_ui_scene(scene_path, unload_mode = UnloadMode.DELETE):
	current_ui_scene = _change_scene(
		scene_path,
		ui_container,
		current_ui_scene,
		"ui",
		unload_mode
	)

func _change_scene(scene_path, container, current_scene, layer_name, unload_mode):
	# Load and validate the new scene BEFORE unloading the old one.
	# This prevents a blank screen when the load fails.
	var loaded_resource = load(scene_path)
	if loaded_resource == null:
		push_error("Failed to load scene: " + str(scene_path))
		_debug_print_state(layer_name)
		return current_scene

	if not (loaded_resource is PackedScene):
		push_error("Loaded resource is not a PackedScene: " + str(scene_path))
		_debug_print_state(layer_name)
		return current_scene

	var new_scene = loaded_resource.instance()
	if new_scene == null:
		push_error("Failed to instance scene: " + str(scene_path))
		_debug_print_state(layer_name)
		return current_scene

	# New scene is confirmed valid — now safely unload the old one.
	if current_scene != null and is_instance_valid(current_scene):
		_unload_current_scene(current_scene, container, layer_name, unload_mode)

	container.add_child(new_scene)
	_debug_print_state(layer_name)
	return new_scene

func _unload_current_scene(current_scene, container, layer_name, unload_mode):
	if unload_mode == UnloadMode.DELETE:
		current_scene.queue_free()
		return

	if unload_mode == UnloadMode.HIDE:
		_set_scene_visibility(current_scene, false)
		return

	if unload_mode == UnloadMode.DETACH:
		if current_scene.get_parent() == container:
			container.remove_child(current_scene)
		_set_detached_scene(layer_name, current_scene)
		return

	push_error("Unknown unload mode: " + str(unload_mode) + ". Falling back to DELETE.")
	current_scene.queue_free()
	return

func _set_scene_visibility(scene_node, is_visible):
	if scene_node is Spatial:
		scene_node.visible = is_visible
	elif scene_node is CanvasItem:
		scene_node.visible = is_visible

func _set_detached_scene(layer_name, scene_node):
	var previous_scene = _get_detached_scene(layer_name)
	if previous_scene != null and is_instance_valid(previous_scene):
		previous_scene.queue_free()

	if layer_name == "world3d":
		detached_world3d_scene = scene_node
	elif layer_name == "world2d":
		detached_world2d_scene = scene_node
	elif layer_name == "ui":
		detached_ui_scene = scene_node
	else:
		push_error("Unknown layer name for detached scene: " + str(layer_name))

func _get_detached_scene(layer_name):
	if layer_name == "world3d":
		return detached_world3d_scene
	elif layer_name == "world2d":
		return detached_world2d_scene
	elif layer_name == "ui":
		return detached_ui_scene
	push_error("Unknown layer name while reading detached scene: " + str(layer_name))
	return null

func _debug_print_state(layer_name):
	print(
		"[SceneController] layer=", layer_name,
		" current3d=", _scene_name(current_world3d_scene),
		" current2d=", _scene_name(current_world2d_scene),
		" currentUI=", _scene_name(current_ui_scene),
		" detached3d=", _scene_name(detached_world3d_scene),
		" detached2d=", _scene_name(detached_world2d_scene),
		" detachedUI=", _scene_name(detached_ui_scene)
	)

func _scene_name(scene_node):
	if scene_node != null and is_instance_valid(scene_node):
		return scene_node.name
	return "null"
