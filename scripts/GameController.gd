extends Node

enum UnloadMode {
	DELETE,
	HIDE,
	DETACH
}

export(NodePath) var world3d_path: NodePath
export(NodePath) var world2d_path: NodePath
export(NodePath) var ui_path: NodePath
export(bool) var free_vram_on_vita_scene_change := true

var world3d_container: Node = null
var world2d_container: Node = null
var ui_container: Node = null

var current_world3d_scene: Node = null
var current_world2d_scene: Node = null
var current_ui_scene: Node = null

var detached_world3d_scene: Node = null
var detached_world2d_scene: Node = null
var detached_ui_scene: Node = null
var detached_world3d_scene_path := ""
var detached_world2d_scene_path := ""
var detached_ui_scene_path := ""

# When true, change_world3d_scene_from_packed hides the old scene, renders
# one blank frame (so the user sees a cut-to-black), then calls add_child.
# This turns the 750 ms frozen frame into an imperceptible black flash.
export(bool) var use_deferred_scene_add: bool = true

var _transition_layer: CanvasLayer = null
var _transition_rect: ColorRect = null
var _deferred_swap_in_progress: bool = false

func _ready() -> void:
	_setup_transition_overlay()
	if not world3d_path:
		push_error("GameController: world3d_path is not set.")
	elif not has_node(world3d_path):
		push_error("GameController: no node found at world3d_path '" + str(world3d_path) + "'.")
	else:
		world3d_container = get_node(world3d_path)

	if not world2d_path:
		push_error("GameController: world2d_path is not set.")
	elif not has_node(world2d_path):
		push_error("GameController: no node found at world2d_path '" + str(world2d_path) + "'.")
	else:
		world2d_container = get_node(world2d_path)

	if not ui_path:
		push_error("GameController: ui_path is not set.")
	elif not has_node(ui_path):
		push_error("GameController: no node found at ui_path '" + str(ui_path) + "'.")
	else:
		ui_container = get_node(ui_path)

	GameGlobal.set_game_controller(self)

	if world3d_container != null:
		change_world3d_scene("res://gui/main_menu.tscn", UnloadMode.DELETE)

func change_world3d_scene(scene_path: String, unload_mode: int = UnloadMode.DELETE) -> void:
	current_world3d_scene = _change_scene(
		scene_path,
		world3d_container,
		current_world3d_scene,
		"world3d",
		unload_mode
	)

func change_world3d_scene_from_packed(packed_scene: PackedScene, unload_mode: int = UnloadMode.DELETE) -> void:
	if use_deferred_scene_add:
		_swap_scene_deferred(packed_scene, world3d_container, "world3d", unload_mode)
	else:
		current_world3d_scene = _change_scene_from_packed(
			packed_scene,
			world3d_container,
			current_world3d_scene,
			"world3d",
			unload_mode
		)

func change_world2d_scene(scene_path: String, unload_mode: int = UnloadMode.DELETE) -> void:
	current_world2d_scene = _change_scene(
		scene_path,
		world2d_container,
		current_world2d_scene,
		"world2d",
		unload_mode
	)

func change_ui_scene(scene_path: String, unload_mode: int = UnloadMode.DELETE) -> void:
	current_ui_scene = _change_scene(
		scene_path,
		ui_container,
		current_ui_scene,
		"ui",
		unload_mode
	)

func has_detached_scene(layer_name: String, scene_path: String) -> bool:
	var detached_scene = _get_detached_scene(layer_name)
	if detached_scene == null or not is_instance_valid(detached_scene):
		return false
	return _get_detached_scene_path(layer_name) == scene_path

func _change_scene(scene_path: String, container: Node, current_scene: Node, layer_name: String, unload_mode: int) -> Node:
	if container == null:
		push_error("GameController: container for layer '" + layer_name + "' is null; cannot change scene.")
		return current_scene

	var detached_scene = _get_detached_scene(layer_name)
	if detached_scene != null and is_instance_valid(detached_scene):
		if _get_detached_scene_path(layer_name) == scene_path:
			if current_scene != null and is_instance_valid(current_scene):
				_unload_current_scene(current_scene, container, layer_name, unload_mode)
			if detached_scene.get_parent() == null:
				container.add_child(detached_scene)
			_set_scene_visibility(detached_scene, true)
			_clear_detached_scene(layer_name)
			_debug_print_state(layer_name)
			return detached_scene

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

	# Drop all caches and preloads BEFORE instancing so nothing holds extra VRAM refs.
	if GameGlobal != null and GameGlobal.has_method("trim_preloaded_scene_cache"):
		GameGlobal.trim_preloaded_scene_cache()
	_free_all_detached_scenes()

	# New scene is confirmed valid — now safely unload the old one.
	if current_scene != null and is_instance_valid(current_scene):
		_unload_current_scene(current_scene, container, layer_name, unload_mode)

	container.add_child(new_scene)
	_debug_print_state(layer_name)
	return new_scene

func _change_scene_from_packed(packed_scene: PackedScene, container: Node, current_scene: Node, layer_name: String, unload_mode: int) -> Node:
	if container == null:
		push_error("GameController: container for layer '" + layer_name + "' is null; cannot change scene.")
		return current_scene

	if packed_scene == null or not (packed_scene is PackedScene):
		push_error("GameController: invalid PackedScene for layer '" + layer_name + "'.")
		_debug_print_state(layer_name)
		return current_scene

	var new_scene = packed_scene.instance()
	if new_scene == null:
		push_error("GameController: failed to instance PackedScene for layer '" + layer_name + "'.")
		_debug_print_state(layer_name)
		return current_scene

	# Drop all caches and preloads BEFORE instancing so nothing holds extra VRAM refs.
	if GameGlobal != null and GameGlobal.has_method("trim_preloaded_scene_cache"):
		GameGlobal.trim_preloaded_scene_cache()
	_free_all_detached_scenes()

	if current_scene != null and is_instance_valid(current_scene):
		_unload_current_scene(current_scene, container, layer_name, unload_mode)

	container.add_child(new_scene)
	_debug_print_state(layer_name)
	return new_scene

func _unload_current_scene(current_scene: Node, container: Node, layer_name: String, unload_mode: int) -> void:
	if free_vram_on_vita_scene_change and OS.get_name() == "Vita":
		if unload_mode == UnloadMode.DETACH or unload_mode == UnloadMode.HIDE:
			unload_mode = UnloadMode.DELETE

	if unload_mode == UnloadMode.DELETE:
		_clear_detached_if_same_scene(layer_name, current_scene)
		if current_scene.get_parent() == container:
			container.remove_child(current_scene)
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
	_clear_detached_if_same_scene(layer_name, current_scene)
	if current_scene.get_parent() == container:
		container.remove_child(current_scene)
	current_scene.queue_free()
	return


func _free_all_detached_scenes() -> void:
	for layer in ["world3d", "world2d", "ui"]:
		var detached = _get_detached_scene(layer)
		if detached != null and is_instance_valid(detached):
			if detached.get_parent() != null:
				detached.get_parent().remove_child(detached)
			detached.free()
		_clear_detached_scene(layer)


func _clear_detached_if_same_scene(layer_name: String, scene_node: Node) -> void:
	var detached_scene = _get_detached_scene(layer_name)
	if detached_scene == null:
		return
	if detached_scene == scene_node:
		_clear_detached_scene(layer_name)

func _set_scene_visibility(scene_node: Node, is_visible: bool) -> void:
	if scene_node is Spatial:
		scene_node.visible = is_visible
	elif scene_node is CanvasItem:
		scene_node.visible = is_visible
	# Also suspend/resume processing so hidden scenes don't consume CPU.
	_set_processing_recursive(scene_node, is_visible)

func _set_processing_recursive(node: Node, enabled: bool) -> void:
	node.set_process(enabled)
	node.set_physics_process(enabled)
	node.set_process_input(enabled)
	node.set_process_unhandled_input(enabled)
	for child in node.get_children():
		_set_processing_recursive(child, enabled)

func _set_detached_scene(layer_name: String, scene_node: Node) -> void:
	var previous_scene = _get_detached_scene(layer_name)
	if previous_scene != null and is_instance_valid(previous_scene):
		previous_scene.queue_free()
	_set_detached_scene_path(layer_name, _scene_path(scene_node))

	if layer_name == "world3d":
		detached_world3d_scene = scene_node
	elif layer_name == "world2d":
		detached_world2d_scene = scene_node
	elif layer_name == "ui":
		detached_ui_scene = scene_node
	else:
		push_error("Unknown layer name for detached scene: " + str(layer_name))

func _clear_detached_scene(layer_name: String) -> void:
	if layer_name == "world3d":
		detached_world3d_scene = null
		detached_world3d_scene_path = ""
	elif layer_name == "world2d":
		detached_world2d_scene = null
		detached_world2d_scene_path = ""
	elif layer_name == "ui":
		detached_ui_scene = null
		detached_ui_scene_path = ""
	else:
		push_error("Unknown layer name while clearing detached scene: " + str(layer_name))

func _set_detached_scene_path(layer_name: String, scene_path: String) -> void:
	if layer_name == "world3d":
		detached_world3d_scene_path = scene_path
	elif layer_name == "world2d":
		detached_world2d_scene_path = scene_path
	elif layer_name == "ui":
		detached_ui_scene_path = scene_path
	else:
		push_error("Unknown layer name for detached scene path: " + str(layer_name))

func _get_detached_scene_path(layer_name: String) -> String:
	if layer_name == "world3d":
		return detached_world3d_scene_path
	elif layer_name == "world2d":
		return detached_world2d_scene_path
	elif layer_name == "ui":
		return detached_ui_scene_path
	return ""

func _get_detached_scene(layer_name: String) -> Node:
	if layer_name == "world3d":
		return detached_world3d_scene
	elif layer_name == "world2d":
		return detached_world2d_scene
	elif layer_name == "ui":
		return detached_ui_scene
	push_error("Unknown layer name while reading detached scene: " + str(layer_name))
	return null

func _debug_print_state(layer_name: String) -> void:
	if not OS.is_debug_build():
		return
	print(
		"[SceneController] layer=", layer_name,
		" current3d=", _scene_name(current_world3d_scene),
		" current2d=", _scene_name(current_world2d_scene),
		" currentUI=", _scene_name(current_ui_scene),
		" detached3d=", _scene_name(detached_world3d_scene),
		" detached2d=", _scene_name(detached_world2d_scene),
		" detachedUI=", _scene_name(detached_ui_scene)
	)

func _scene_name(scene_node: Node) -> String:
	if scene_node != null and is_instance_valid(scene_node):
		return scene_node.name
	return "null"

func _scene_path(scene_node: Node) -> String:
	if scene_node != null and is_instance_valid(scene_node):
		return scene_node.filename
	return ""

# ---------------------------------------------------------------------------
# Deferred scene swap — eliminates the frozen-frame stall on add_child
# ---------------------------------------------------------------------------

# Coroutine: instances the new scene, unloads the old one, shows a black
# overlay, yields one frame so the engine renders the blank frame, then calls
# add_child (the expensive step) and hides the overlay.
func _swap_scene_deferred(packed_scene: PackedScene, container: Node, layer_name: String, unload_mode: int) -> void:
	if _deferred_swap_in_progress:
		push_warning("GameController: deferred swap already in progress; ignoring duplicate request on '" + layer_name + "'.")
		return
	if container == null:
		push_error("GameController: container for layer '" + layer_name + "' is null.")
		return
	if packed_scene == null:
		push_error("GameController: null PackedScene for deferred swap on layer '" + layer_name + "'.")
		return

	var new_scene: Node = packed_scene.instance()
	if new_scene == null:
		push_error("GameController: failed to instance PackedScene for layer '" + layer_name + "'.")
		return

	_deferred_swap_in_progress = true

	if GameGlobal != null and GameGlobal.has_method("trim_preloaded_scene_cache"):
		GameGlobal.trim_preloaded_scene_cache()
	_free_all_detached_scenes()

	var old_scene: Node = _get_current_scene(layer_name)
	if old_scene != null and is_instance_valid(old_scene):
		_unload_current_scene(old_scene, container, layer_name, unload_mode)

	# Register reference immediately so external code can query the new scene
	# even before it enters the tree.
	_set_current_scene(layer_name, new_scene)

	# Black overlay — gives the engine a frame to composite before the stall.
	_show_transition()
	yield(get_tree(), "idle_frame")

	# This is the expensive call: triggers _enter_tree + _ready on every node.
	if is_instance_valid(new_scene) and is_instance_valid(container):
		container.add_child(new_scene)

	# Hold the overlay for one more frame to mask any residual shader-
	# compilation stall on the first render of the new scene.
	yield(get_tree(), "idle_frame")
	_hide_transition()
	_deferred_swap_in_progress = false
	_debug_print_state(layer_name)


func _get_current_scene(layer_name: String) -> Node:
	if layer_name == "world3d":
		return current_world3d_scene
	elif layer_name == "world2d":
		return current_world2d_scene
	elif layer_name == "ui":
		return current_ui_scene
	return null


func _set_current_scene(layer_name: String, scene: Node) -> void:
	if layer_name == "world3d":
		current_world3d_scene = scene
	elif layer_name == "world2d":
		current_world2d_scene = scene
	elif layer_name == "ui":
		current_ui_scene = scene


func _setup_transition_overlay() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 128  # above everything
	add_child(_transition_layer)
	_transition_rect = ColorRect.new()
	_transition_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_transition_rect.anchor_left = 0.0
	_transition_rect.anchor_top = 0.0
	_transition_rect.anchor_right = 1.0
	_transition_rect.anchor_bottom = 1.0
	_transition_rect.margin_left = 0.0
	_transition_rect.margin_top = 0.0
	_transition_rect.margin_right = 0.0
	_transition_rect.margin_bottom = 0.0
	_transition_rect.visible = false
	_transition_layer.add_child(_transition_rect)


func _show_transition() -> void:
	if _transition_rect != null:
		_transition_rect.visible = true


func _hide_transition() -> void:
	if _transition_rect != null:
		_transition_rect.visible = false


func _print_memory() -> void:
	var static_mb = OS.get_static_memory_usage() / 1024.0 / 1024.0
	var dynamic_mb = OS.get_dynamic_memory_usage() / 1024.0 / 1024.0

	var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var tex_mb = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0
	var vtx_mb = Performance.get_monitor(Performance.RENDER_VERTEX_MEM_USED) / 1024.0 / 1024.0

	print("RAM static=", static_mb, "MB  dynamic=", dynamic_mb, "MB",
		  "  VRAM=", vram_mb, "MB  tex=", tex_mb, "MB  vtx=", vtx_mb, "MB")
