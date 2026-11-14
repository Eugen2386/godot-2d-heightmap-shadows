extends Node2D

@export var shadow_rect: ColorRect
@export var day_night_color: Gradient
@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var height_viewport: SubViewport = $HeightmapViewport
@onready var height_camera: Camera2D = $HeightmapViewport/HeightCamera
@onready var main_camera: Camera2D = $Player/Camera2D

@export var day_duration_seconds: float = 20.0
@export var max_shadow_length: float = 150.0
@export var min_shadow_length: float = 30.0
@export var dynamic_shadow_length: bool = true
@export var dynamic_day_night_color: bool = true
@export var multimesh_grass: bool = true
@export var max_height_z: float = 20.0
var current_angle: float = 0.785

enum ShadowMode {
	SHADOW_OBJECT,
	SHADOW_CAST_ONLY,
	SHADOW_RECEIVE_ONLY,
	ZERO_SHADOW
}

class HeightEntry:
	var orig: Node2D
	var clone: Node2D
	var is_dynamic: bool
	var is_sprite: bool
	var is_anim_sprite: bool
	var has_custom_shader: bool

	func _init(p_orig: Node2D, p_clone: Node2D, p_dynamic: bool) -> void:
		orig = p_orig
		clone = p_clone
		is_dynamic = p_dynamic
		is_sprite = orig is Sprite2D
		is_anim_sprite = orig is AnimatedSprite2D
		has_custom_shader = orig.material is ShaderMaterial and clone.material is ShaderMaterial

var dynamic_entries: Array[HeightEntry] = []
var static_entries: Array[HeightEntry] = []
var node_to_entry: Dictionary = {}
var additive_shader_cache: Dictionary = {}

const SILHOUETTE_SHADER_CODE = """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 height_color = vec4(0.0, 0.5, 0.0, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	if (tex.a < 0.05) { discard; }
	COLOR = vec4(height_color.rgb, tex.a);
}
"""

const SILHOUETTE_ADD_SHADER_CODE = """
shader_type canvas_item;
render_mode unshaded, blend_add;
uniform vec4 height_color = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	if (tex.a < 0.05) { discard; }
	COLOR = vec4(height_color.rgb * tex.a, 1.0);
}
"""

var silhouette_shader: Shader
var silhouette_add_shader: Shader


func _ready() -> void:
	process_priority = 10

	silhouette_shader = Shader.new()
	silhouette_shader.code = SILHOUETTE_SHADER_CODE

	silhouette_add_shader = Shader.new()
	silhouette_add_shader.code = SILHOUETTE_ADD_SHADER_CODE

	height_viewport.world_2d = World2D.new()
	height_viewport.canvas_cull_mask = 2
	height_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	height_viewport.transparent_bg = true

	var margin: int = int(ceil(max_shadow_length * main_camera.zoom.x)) + 50
	var win_size = Vector2i(get_viewport().get_visible_rect().size)
	var target_vp_size = win_size + Vector2i(margin * 2, margin * 2)
	if win_size.x > 0 and win_size.y > 0:
		height_viewport.size = target_vp_size

	height_camera.position_smoothing_enabled = false
	height_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	height_camera.enabled = true

	if multimesh_grass:
		_spawn_test_multimesh()

	_setup_auto_heightmaps()

	var mat = shadow_rect.material as ShaderMaterial
	mat.set_shader_parameter("heightmap_tex", height_viewport.get_texture())

	if target_vp_size.x > 0 and target_vp_size.y > 0:
		mat.set_shader_parameter("heightmap_uv_scale", Vector2(win_size) / Vector2(target_vp_size))
		mat.set_shader_parameter("heightmap_uv_offset", Vector2(margin, margin) / Vector2(target_vp_size))


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("Esc"):
		get_tree().quit()

	height_camera.global_position = main_camera.get_screen_center_position()
	height_camera.zoom = main_camera.zoom
	height_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER

	var margin: int = int(ceil(max_shadow_length * main_camera.zoom.x)) + 50
	var win_size = Vector2i(get_viewport().get_visible_rect().size)
	var target_vp_size = win_size + Vector2i(margin * 2, margin * 2)

	if height_viewport.size != target_vp_size and win_size.x > 0 and win_size.y > 0:
		height_viewport.size = target_vp_size

	for i in range(dynamic_entries.size() - 1, -1, -1):
		var entry = dynamic_entries[i]
		if not is_instance_valid(entry.orig) or not is_instance_valid(entry.clone):
			_cleanup_entry(entry)
			continue
		_sync_entry(entry)

	var rotation_speed = (2.0 * PI) / day_duration_seconds
	current_angle = wrapf(current_angle + rotation_speed * delta, 0.0, TAU)
	var sun_dir = Vector2(cos(current_angle), sin(current_angle)).normalized()

	if canvas_modulate:
		if dynamic_day_night_color and day_night_color:
			var day_progress = current_angle / TAU
			canvas_modulate.color = day_night_color.sample(day_progress)
		else:
			canvas_modulate.color = Color.WHITE

	var current_shadow_length = max_shadow_length
	if dynamic_shadow_length:
		var length_factor = absf(cos(current_angle))
		current_shadow_length = lerpf(min_shadow_length, max_shadow_length, length_factor)

	var zoomed_shadow_length = current_shadow_length * main_camera.zoom.x

	var mat = shadow_rect.material as ShaderMaterial
	mat.set_shader_parameter("sun_direction", sun_dir)
	mat.set_shader_parameter("max_ray_distance", zoomed_shadow_length)

	if target_vp_size.x > 0 and target_vp_size.y > 0:
		mat.set_shader_parameter("heightmap_uv_scale", Vector2(win_size) / Vector2(target_vp_size))
		mat.set_shader_parameter("heightmap_uv_offset", Vector2(margin, margin) / Vector2(target_vp_size))


func register_shadow_node(target: Node, group_override: String = "", recursive: bool = true) -> void:
	if not is_instance_valid(target) or target == height_viewport or height_viewport.is_ancestor_of(target):
		return

	var effective_group = _get_node_shadow_group(target)
	if effective_group.is_empty():
		effective_group = group_override

	if _is_visual_node(target) and not node_to_entry.has(target):
		var mode = _mode_from_group_name(effective_group)
		_create_height_clone(target as Node2D, mode)

	if recursive:
		for child in target.get_children():
			register_shadow_node(child, effective_group, true)


func unregister_shadow_nodes(targets: Variant) -> void:
	if targets is Array:
		for item in targets:
			if item is Node:
				_unregister_single_recursive(item)
	elif targets is Node:
		_unregister_single_recursive(targets)


func _unregister_single_recursive(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node_to_entry.has(node):
		_cleanup_entry(node_to_entry[node])
	for child in node.get_children():
		_unregister_single_recursive(child)


func _cleanup_entry(entry: HeightEntry) -> void:
	if is_instance_valid(entry.orig):
		node_to_entry.erase(entry.orig)
		if entry.orig.tree_exiting.is_connected(_on_orig_tree_exiting):
			entry.orig.tree_exiting.disconnect(_on_orig_tree_exiting)
	else:
		for key in node_to_entry.keys():
			if node_to_entry[key] == entry:
				node_to_entry.erase(key)
				break

	if is_instance_valid(entry.clone):
		entry.clone.queue_free()

	if entry.is_dynamic:
		dynamic_entries.erase(entry)
	else:
		static_entries.erase(entry)


func _on_orig_tree_exiting(orig: Node2D) -> void:
	if node_to_entry.has(orig):
		_cleanup_entry(node_to_entry[orig])


func _sync_entry(entry: HeightEntry) -> void:
	var orig = entry.orig
	var clone = entry.clone

	clone.global_transform = orig.global_transform
	clone.visible = orig.is_visible_in_tree()
	clone.modulate.a = _get_effective_alpha(orig)

	if entry.is_anim_sprite:
		var o_anim = orig as AnimatedSprite2D
		var c_anim = clone as AnimatedSprite2D
		if c_anim.sprite_frames != o_anim.sprite_frames:
			c_anim.sprite_frames = o_anim.sprite_frames
		if c_anim.animation != o_anim.animation:
			c_anim.animation = o_anim.animation
		if c_anim.frame != o_anim.frame:
			c_anim.frame = o_anim.frame
		c_anim.frame_progress = o_anim.frame_progress
		c_anim.flip_h = o_anim.flip_h
		c_anim.flip_v = o_anim.flip_v
		c_anim.offset = o_anim.offset
		c_anim.centered = o_anim.centered

	elif entry.is_sprite:
		var o_spr = orig as Sprite2D
		var c_spr = clone as Sprite2D
		if c_spr.texture != o_spr.texture:
			c_spr.texture = o_spr.texture
		if c_spr.hframes != o_spr.hframes:
			c_spr.hframes = o_spr.hframes
		if c_spr.vframes != o_spr.vframes:
			c_spr.vframes = o_spr.vframes
		if c_spr.frame != o_spr.frame:
			c_spr.frame = o_spr.frame
		c_spr.flip_h = o_spr.flip_h
		c_spr.flip_v = o_spr.flip_v
		c_spr.offset = o_spr.offset
		c_spr.centered = o_spr.centered
		c_spr.region_enabled = o_spr.region_enabled
		if o_spr.region_enabled:
			c_spr.region_rect = o_spr.region_rect

	if entry.has_custom_shader:
		var o_mat = orig.material as ShaderMaterial
		var c_mat = clone.material as ShaderMaterial
		if o_mat.shader:
			var param_list = RenderingServer.get_shader_parameter_list(o_mat.shader.get_rid())
			for p in param_list:
				var p_name: String = p["name"]
				if p_name != "height_color" and p_name != "heightmap_mode" and p_name != "additive_heightmap":
					c_mat.set_shader_parameter(p_name, o_mat.get_shader_parameter(p_name))


func _setup_auto_heightmaps() -> void:
	var root_node = get_tree().current_scene
	if not root_node:
		root_node = self
	_scan_nodes_recursive(root_node, "")


func _scan_nodes_recursive(node: Node, inherited_group: String) -> void:
	if node == height_viewport:
		return

	var current_group = _get_node_shadow_group(node)
	if current_group.is_empty():
		current_group = inherited_group

	if _is_visual_node(node) and not node_to_entry.has(node):
		var mode = _mode_from_group_name(current_group)
		_create_height_clone(node as Node2D, mode)

	for child in node.get_children():
		_scan_nodes_recursive(child, current_group)


func _get_node_shadow_group(node: Node) -> String:
	if node.is_in_group("ShadowObject"):
		return "ShadowObject"
	if node.is_in_group("ShadowCastOnly"):
		return "ShadowCastOnly"
	if node.is_in_group("ShadowReceiveOnly"):
		return "ShadowReceiveOnly"
	if node.is_in_group("ZeroShadow"):
		return "ZeroShadow"
	return ""


func _mode_from_group_name(group_name: String) -> ShadowMode:
	match group_name:
		"ShadowObject":
			return ShadowMode.SHADOW_OBJECT
		"ShadowCastOnly":
			return ShadowMode.SHADOW_CAST_ONLY
		"ShadowReceiveOnly":
			return ShadowMode.SHADOW_RECEIVE_ONLY
		_:
			return ShadowMode.ZERO_SHADOW


func _is_visual_node(node: Node) -> bool:
	return (
		node is Sprite2D or
		node is AnimatedSprite2D or
		node is MultiMeshInstance2D or
		node is Polygon2D or
		node is TileMapLayer or
		node is TileMap or
		node is MeshInstance2D or
		node is Line2D or
		node is CPUParticles2D or
		node is GPUParticles2D
	)


func _is_dynamic_node(node: Node) -> bool:
	if node.is_in_group("StaticShadow"):
		return false
	if node is TileMapLayer or node is TileMap or node is MultiMeshInstance2D:
		return node.is_in_group("DynamicShadow")
	return true
func _get_effective_alpha(item: CanvasItem) -> float:
	var a = item.self_modulate.a * item.modulate.a
	var parent = item.get_parent()
	while parent is CanvasItem:
		a *= parent.modulate.a
		parent = parent.get_parent()
	return a


func _get_total_z_index(item: CanvasItem) -> int:
	var total_z = item.z_index
	var parent = item.get_parent()
	while parent is CanvasItem:
		if not item.z_as_relative:
			break
		total_z += parent.z_index
		item = parent
		parent = parent.get_parent()
	return total_z


func _create_height_clone(visual_node: Node2D, mode: ShadowMode) -> void:
	var height_clone = visual_node.duplicate(0) as Node2D
	if not height_clone:
		return

	for c in height_clone.get_children():
		c.free()

	height_clone.set_script(null)
	height_clone.name = "AutoHeight_" + visual_node.name
	height_clone.visibility_layer = 2
	height_clone.use_parent_material = false

	var total_z = _get_total_z_index(visual_node)
	height_clone.z_index = total_z
	height_clone.z_as_relative = false

	var z_height = clampf(float(total_z) / max_height_z, 0.01, 1.0) if total_z > 0 else 0.0

	var target_color: Color
	var is_additive = false

	match mode:
		ShadowMode.SHADOW_OBJECT:
			target_color = Color(z_height, z_height, 0.0, 1.0)
		ShadowMode.SHADOW_CAST_ONLY:
			target_color = Color(z_height, 0.0, 1.0, 1.0)
		ShadowMode.SHADOW_RECEIVE_ONLY:
			target_color = Color(0.0, z_height, 0.0, 1.0)
		ShadowMode.ZERO_SHADOW:
			target_color = Color(0.0, 0.0, 1.0, 1.0)
			is_additive = true

	var sil_mat: ShaderMaterial
	if visual_node.material is ShaderMaterial and (visual_node.material as ShaderMaterial).shader != null:
		sil_mat = (visual_node.material as ShaderMaterial).duplicate() as ShaderMaterial
		if is_additive:
			var orig_shader = sil_mat.shader
			if additive_shader_cache.has(orig_shader):
				sil_mat.shader = additive_shader_cache[orig_shader]
			else:
				var add_shader = orig_shader.duplicate() as Shader
				add_shader.code = _inject_blend_add(add_shader.code)
				additive_shader_cache[orig_shader] = add_shader
				sil_mat.shader = add_shader
		sil_mat.set_shader_parameter("heightmap_mode", true)
		sil_mat.set_shader_parameter("additive_heightmap", is_additive)
	else:
		sil_mat = ShaderMaterial.new()
		sil_mat.shader = silhouette_add_shader if is_additive else silhouette_shader

	sil_mat.set_shader_parameter("height_color", target_color)
	height_clone.material = sil_mat
	height_clone.modulate = Color(1.0, 1.0, 1.0, _get_effective_alpha(visual_node))
	height_clone.self_modulate = Color.WHITE

	height_clone.remove_from_group("ShadowObject")
	height_clone.remove_from_group("ShadowCastOnly")
	height_clone.remove_from_group("ShadowReceiveOnly")
	height_clone.remove_from_group("ZeroShadow")

	height_viewport.add_child(height_clone)
	height_clone.global_transform = visual_node.global_transform
	height_clone.visible = visual_node.is_visible_in_tree()

	var is_dyn = _is_dynamic_node(visual_node)
	var entry = HeightEntry.new(visual_node, height_clone, is_dyn)

	node_to_entry[visual_node] = entry
	if is_dyn:
		dynamic_entries.append(entry)
	else:
		static_entries.append(entry)

	visual_node.tree_exiting.connect(_on_orig_tree_exiting.bind(visual_node))


func _inject_blend_add(code: String) -> String:
	var regex = RegEx.new()
	regex.compile("render_mode\\s+([^;]+);")
	var result = regex.search(code)
	if result:
		var modes = result.get_string(1)
		if not modes.contains("blend_add"):
			modes = modes.replace("blend_mix", "").replace("blend_sub", "").replace("blend_mul", "")
			modes = modes.strip_edges().trim_prefix(",").trim_suffix(",").strip_edges()
			var new_modes = "blend_add" if modes.is_empty() else modes + ", blend_add"
			return code.substr(0, result.get_start()) + "render_mode " + new_modes + ";" + code.substr(result.get_end())
		return code

	var type_regex = RegEx.new()
	type_regex.compile("shader_type\\s+canvas_item\\s*;")
	var type_res = type_regex.search(code)
	if type_res:
		return code.substr(0, type_res.get_end()) + "\nrender_mode blend_add;" + code.substr(type_res.get_end())

	return code


func _spawn_test_multimesh() -> void:
	var tree_tex: Texture2D = load("res://assets/Grass.png")
	var random_color: Array[Color] = [
		Color(0.324, 0.51, 0.223, 1.0),
		Color(0.272, 0.388, 0.205, 1.0),
		Color(0.473, 0.536, 0.209, 1.0),
		Color(0.454, 0.453, 0.139, 1.0)
	]

	var quad = QuadMesh.new()
	quad.size = tree_tex.get_size() if tree_tex else Vector2(64, 64)
	quad.flip_faces = true

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 5000

	for i in range(5000):
		var random_pos = Vector2(randf_range(-1000.0, 1000.0), randf_range(-1000.0, 1000.0))
		var t = Transform2D(0.0, random_pos)
		mm.set_instance_transform_2d(i, t)
		mm.set_instance_color(i, random_color.pick_random())

	var mmi = MultiMeshInstance2D.new()
	mmi.name = "TestTreeMultiMesh"
	mmi.multimesh = mm
	mmi.texture = tree_tex
	mmi.z_index = 1

	mmi.add_to_group("ShadowObject")

	add_child(mmi)
