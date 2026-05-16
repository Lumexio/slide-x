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


func _ready() -> void:
	_apply_visibility_range_recursive(self, DEFAULT_RANGE_BEGIN, DEFAULT_RANGE_END)
	for node_name in RANGE_OVERRIDES.keys():
		var target := get_node_or_null(node_name)
		if target == null:
			continue
		_apply_visibility_range_recursive(target, DEFAULT_RANGE_BEGIN, float(RANGE_OVERRIDES[node_name]))


func _apply_visibility_range_recursive(node: Node, range_begin: float, range_end: float) -> void:
	if node is VisualInstance:
		if _has_property(node, "visibility_range_begin"):
			node.set("visibility_range_begin", range_begin)
			node.set("visibility_range_end", range_end)
	for child in node.get_children():
		_apply_visibility_range_recursive(child, range_begin, range_end)


func _has_property(node: Object, prop_name: String) -> bool:
	for info in node.get_property_list():
		if info.name == prop_name:
			return true
	return false
