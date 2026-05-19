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
export(bool) var vita_perf_enabled := true
export(int) var vita_target_fps := 30
export(bool) var vita_reduce_physics_fps := true
export(int) var vita_physics_fps := 60
export(bool) var vita_disable_shadows := true
export(bool) var vita_force_baked_lights := true
export(bool) var vita_reduce_particles := true
export(float) var vita_particles_scale := 0.35
export(bool) var vita_simplify_materials := true
var _vita_perf_initialized := false

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
	# Preloading disabled: only the current scene should exist in VRAM.
	return


func get_preloaded_scene(scene_path: String) -> PackedScene:
	var cached = preload_cache.get(scene_path, null)
	if cached != null and cached is PackedScene:
		return cached as PackedScene
	return null


func trim_preloaded_scene_cache() -> void:
	# One-shot trim for heavy transitions: stop ongoing preload and drop strong refs.
	_preload_loader = null
	_preload_active = false
	_preload_started = false
	_preload_stage_index = 0
	_preload_item_index = -1
	_preload_current_path = ""
	_preload_stage_name = ""
	_preload_stages.clear()
	_preload_total_items = 0
	set_process(false)
	preload_cache.clear()
	if MenuCharacterCache != null:
		MenuCharacterCache.stop()


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


func _maybe_apply_vita_perf() -> void:
	if _vita_perf_initialized:
		return
	if not vita_perf_enabled or OS.get_name() != "Vita":
		return
	_vita_perf_initialized = true
	if vita_target_fps > 0:
		Engine.target_fps = vita_target_fps
	if vita_reduce_physics_fps and vita_physics_fps > 0:
		Engine.iterations_per_second = vita_physics_fps
	_apply_vita_perf_to_tree(get_tree().root)
	var _err = get_tree().connect("node_added", self, "_on_vita_node_added")


func _on_vita_node_added(node: Node) -> void:
	_apply_vita_perf_to_node(node)


func _apply_vita_perf_to_tree(root: Node) -> void:
	if root == null:
		return
	_apply_vita_perf_to_node(root)
	for child in root.get_children():
		_apply_vita_perf_to_tree(child)


func _apply_vita_perf_to_node(node: Node) -> void:
	if node == null:
		return
	if vita_disable_shadows:
		if node is Light and _has_property(node, "shadow_enabled"):
			node.set("shadow_enabled", false)
		if node is GeometryInstance and _has_property(node, "cast_shadow"):
			node.set("cast_shadow", GeometryInstance.SHADOW_CASTING_SETTING_OFF)
	if vita_force_baked_lights:
		if node is Light and _has_property(node, "bake_mode"):
			node.set("bake_mode", Light.BAKE_ALL)
	if vita_reduce_particles:
		if node is Particles or node is CPUParticles:
			_scale_particles_amount(node)
		elif node is Particles2D or node is CPUParticles2D:
			_scale_particles_amount(node)
	if vita_simplify_materials and node is MeshInstance:
		_simplify_mesh_materials(node)


func _scale_particles_amount(node: Node) -> void:
	if not _has_property(node, "amount"):
		return
	if node.has_meta("vita_original_amount"):
		return
	var original = int(node.get("amount"))
	node.set_meta("vita_original_amount", original)
	var scaled = max(1, int(round(float(original) * vita_particles_scale)))
	node.set("amount", scaled)


func _simplify_mesh_materials(mesh_instance: MeshInstance) -> void:
	if mesh_instance.material_override != null:
		_simplify_material(mesh_instance.material_override)
	var mesh = mesh_instance.mesh
	if mesh == null:
		return
	for i in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(i)
		if mat != null:
			_simplify_material(mat)


func _simplify_material(material: Material) -> void:
	if material == null:
		return
	if material.has_meta("vita_simplified"):
		return
	material.set_meta("vita_simplified", true)
	if material is SpatialMaterial:
		var sm = material as SpatialMaterial
		if _has_property(sm, "normal_enabled"):
			sm.normal_enabled = false
		if _has_property(sm, "normal_texture"):
			sm.normal_texture = null
		if _has_property(sm, "roughness_texture"):
			sm.roughness_texture = null
		if _has_property(sm, "metallic_texture"):
			sm.metallic_texture = null
		if _has_property(sm, "detail_enabled"):
			sm.detail_enabled = false
		if _has_property(sm, "detail_albedo"):
			sm.detail_albedo = null
		if _has_property(sm, "detail_normal"):
			sm.detail_normal = null
		if _has_property(sm, "clearcoat_enabled"):
			sm.clearcoat_enabled = false
		if _has_property(sm, "subsurf_scatter_enabled"):
			sm.subsurf_scatter_enabled = false
		if _has_property(sm, "refraction_enabled"):
			sm.refraction_enabled = false
		if _has_property(sm, "params_anisotropy_enabled"):
			sm.params_anisotropy_enabled = false


func _has_property(node: Object, prop_name: String) -> bool:
	for info in node.get_property_list():
		if info.name == prop_name:
			return true
	return false

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.one_shot = false
	add_child(t)
	var _timer_connect_err = t.connect("timeout", self, "_print_memory")
	_maybe_apply_vita_perf()
