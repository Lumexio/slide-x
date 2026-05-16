extends Spatial

const DEFAULT_RANGE_BEGIN := 0.0
const DEFAULT_RANGE_END := 120.0
const RANGE_OVERRIDES := {
	"Trees": 70.0,
	"Sidewalks": 90.0,
	"Roads": 140.0,
	"BuildingWalls": 120.0,
	"PSX_Buildings": 120.0,
	"PSX_Buildings2": 120.0,
	"Car": 60.0,
	"Car2": 60.0,
	"Car3": 60.0,
	"street_light": 80.0,
	"Police_Telephone_Box": 90.0,
}

export(NodePath) var lod_target_path: NodePath
export(float) var lod_update_interval := 0.25

var _lod_timer := 0.0
var _lod_nodes: Array = []


func _ready() -> void:
	_apply_visibility_range_recursive(self, DEFAULT_RANGE_BEGIN, DEFAULT_RANGE_END)
	for node_name in RANGE_OVERRIDES.keys():
		var target := get_node_or_null(node_name)
		if target == null:
			continue
		_apply_visibility_range_recursive(target, DEFAULT_RANGE_BEGIN, float(RANGE_OVERRIDES[node_name]))
	_cache_lod_nodes()
	set_process(true)


func _process(delta: float) -> void:
	_lod_timer += delta
	if _lod_timer < lod_update_interval:
		return
	_lod_timer = 0.0
	_update_lod_visibility()


func _apply_visibility_range_recursive(node: Node, range_begin: float, range_end: float) -> void:
	if node is VisualInstance:
		if _has_property(node, "visibility_range_begin"):
			node.set("visibility_range_begin", range_begin)
			node.set("visibility_range_end", range_end)
	for child in node.get_children():
		_apply_visibility_range_recursive(child, range_begin, range_end)


func _cache_lod_nodes() -> void:
	_lod_nodes.clear()
	for node_name in RANGE_OVERRIDES.keys():
		var node := get_node_or_null(node_name)
		if node == null:
			continue
		_lod_nodes.append({"node": node, "dist": float(RANGE_OVERRIDES[node_name])})


func _update_lod_visibility() -> void:
	var target := _get_lod_target()
	if target == null:
		return
	var target_pos := target.global_transform.origin
	for entry in _lod_nodes:
		var node = entry.node
		if node == null or not is_instance_valid(node):
			continue
		var max_dist := float(entry.dist)
		var dist_sq := target_pos.distance_squared_to(node.global_transform.origin)
		var is_visible := dist_sq <= max_dist * max_dist
		if node is Spatial:
			(node as Spatial).visible = is_visible


func _get_lod_target() -> Spatial:
	if lod_target_path != null and String(lod_target_path) != "":
		var explicit_target := get_node_or_null(lod_target_path)
		if explicit_target is Spatial:
			return explicit_target as Spatial
	var camera := get_viewport().get_camera()
	if camera != null:
		return camera
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Spatial:
		return players[0] as Spatial
	return null


func _has_property(node: Object, prop_name: String) -> bool:
	for info in node.get_property_list():
		if info.name == prop_name:
			return true
	return false
