extends Spatial

# Groups whose children are identical PackedScene instances sharing the same
# mesh.  At runtime we bake each group into one MultiMeshInstance (per unique
# mesh) and hide the original MeshInstance nodes, reducing the draw-call count
# from N per group down to 1.  StaticBody / CollisionShape nodes inside each
# instance are untouched so physics still works.
const MULTIMESH_GROUPS := ["Sidewalks", "BuildingWalls", "Trees"]

export(bool) var use_multimesh_baking: bool = true

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
	if use_multimesh_baking:
		_bake_groups_to_multimesh()
	# NOTE: visibility_range_begin / _range_end are Godot 4 properties and do
	# not exist in Godot 3.5 GLES2.  _apply_visibility_range_recursive is a
	# no-op here; skip it to avoid O(nodes × properties) _has_property scans.
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
		# Guard: only write visible when the state actually changes.  Each
		# redundant write fires Godot's _apply_visibility notification cascade
		# (shadow-atlas updates, culling) even when nothing has changed.
		if node is Spatial and (node as Spatial).visible != is_visible:
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


# ---------------------------------------------------------------------------
# MultiMesh baking
# ---------------------------------------------------------------------------

# Convert each MULTIMESH_GROUPS entry from N individual draw calls to 1.
# The MultiMeshInstance is added as a child of the group node so that the
# existing LOD visibility system (which shows/hides the group Spatial node)
# automatically controls the MultiMeshInstance as well.
func _bake_groups_to_multimesh() -> void:
	for group_name in MULTIMESH_GROUPS:
		var group: Spatial = get_node_or_null(group_name) as Spatial
		if group == null:
			continue
		_bake_group(group)


func _bake_group(group_node: Spatial) -> void:
	var children := group_node.get_children()
	if children.empty():
		return

	# Gather (mesh_resource -> [MeshInstance, ...]) so that groups containing
	# mixed meshes (unlikely here, but safe) are each baked separately.
	var buckets := {}  # Mesh -> Array of MeshInstance
	for child in children:
		var mesh_node: MeshInstance = _find_first_mesh_in_subtree(child)
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var key: Mesh = mesh_node.mesh
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append({"child": child, "mesh_node": mesh_node})

	for mesh_res in buckets.keys():
		var entries: Array = buckets[mesh_res]
		if entries.empty():
			continue

		var ref_mesh_node: MeshInstance = entries[0].mesh_node
		var mat: Material = ref_mesh_node.get_surface_material(0)

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = entries.size()
		mm.mesh = mesh_res

		# Use global transforms so nested offsets inside packed scenes are
		# correctly accounted for; then express in group_node local space so
		# the MultiMeshInstance (added as a child of group_node) renders them
		# at the right world positions.
		var group_inv: Transform = group_node.global_transform.affine_inverse()
		for i in range(entries.size()):
			var mesh_node: MeshInstance = entries[i].mesh_node
			var world_t: Transform = mesh_node.global_transform
			mm.set_instance_transform(i, group_inv * world_t)
			# Remove the mesh from the tree and re-home any collision children
			# (StaticBody etc.) so VRAM is freed but physics is preserved.
			_remove_mesh_preserve_children(mesh_node)

		var mmi := MultiMeshInstance.new()
		mmi.name = "_MMI_" + mesh_res.resource_name if mesh_res.resource_name != "" else "_MMI"
		mmi.multimesh = mm
		if mat != null:
			mmi.material_override = mat
		group_node.add_child(mmi)


# Moves any non-MeshInstance children of mesh_node (e.g. StaticBody) to
# mesh_node's parent so collision is preserved, then frees the mesh visual.
# Global transforms of re-parented children are restored after the move.
func _remove_mesh_preserve_children(mesh_node: MeshInstance) -> void:
	var mesh_parent: Node = mesh_node.get_parent()
	if mesh_parent == null:
		mesh_node.queue_free()
		return

	# Snapshot global transforms while the nodes are still in the tree.
	var children_snapshot: Array = []
	for child in mesh_node.get_children():
		var gt: Transform = child.global_transform if child is Spatial else Transform()
		children_snapshot.append({"node": child, "gt": gt, "is_spatial": child is Spatial})

	# Re-parent each child to mesh_parent, then restore world position.
	for entry in children_snapshot:
		var child: Node = entry.node
		mesh_node.remove_child(child)
		mesh_parent.add_child(child)
		if entry.is_spatial:
			(child as Spatial).global_transform = entry.gt

	mesh_node.queue_free()


# Depth-first search for the first MeshInstance in a node's subtree.
func _find_first_mesh_in_subtree(node: Node) -> MeshInstance:
	if node is MeshInstance:
		return node as MeshInstance
	for child in node.get_children():
		var result: MeshInstance = _find_first_mesh_in_subtree(child)
		if result != null:
			return result
	return null

