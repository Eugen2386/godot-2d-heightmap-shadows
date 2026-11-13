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

var height_pairs: Array[Array] = []

enum ShadowMode {
	SHADOW_OBJECT,
	SHADOW_CAST_ONLY,
	SHADOW_RECEIVE_ONLY,
	ZERO_SHADOW
}

const SILHOUETTE_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 height_color = vec4(0.0, 0.5, 0.0, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(height_color.rgb, tex.a);
}
"""

const SILHOUETTE_ADD_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded, blend_add;
uniform vec4 height_color = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
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
	
	height_viewport.canvas_cull_mask = 1
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
	height_camera.make_current()
	
	if multimesh_grass == true:
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
	
	for pair in height_pairs:
		var orig: Node2D = pair.front()
		var clone: Node2D = pair.back()
		if is_instance_valid(orig) and is_instance_valid(clone):
			clone.global_transform = orig.global_transform
			clone.visible = orig.is_visible_in_tree()
	
	var rotation_speed = (2.0 * PI) / day_duration_seconds
	current_angle = wrapf(current_angle + rotation_speed * delta, 0.0, TAU)
	var sun_dir := Vector2(cos(current_angle), sin(current_angle)).normalized()
	
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


func _setup_auto_heightmaps() -> void:
	var root_node = get_tree().current_scene
	if not root_node:
		root_node = self
		
	_scan_nodes_recursive(root_node)


func _scan_nodes_recursive(node: Node) -> void:
	if node == height_viewport:
		return

	if _is_visual_node(node):
		if node.is_in_group("ShadowObject"):
			_create_height_clone(node as Node2D, ShadowMode.SHADOW_OBJECT)
		elif node.is_in_group("ShadowCastOnly"):
			_create_height_clone(node as Node2D, ShadowMode.SHADOW_CAST_ONLY)
		elif node.is_in_group("ShadowReceiveOnly"):
			_create_height_clone(node as Node2D, ShadowMode.SHADOW_RECEIVE_ONLY)
		else:
			_create_height_clone(node as Node2D, ShadowMode.ZERO_SHADOW)

	for child in node.get_children():
		_scan_nodes_recursive(child)


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
	
	height_clone.set_script(null)
	height_clone.name = "AutoHeight_" + visual_node.name
	height_clone.visibility_layer = 1
	
	var total_z = _get_total_z_index(visual_node)
	height_clone.z_index = total_z
	height_clone.z_as_relative = false
	
	
	var z_height = clampf(float(total_z) / max_height_z, 0.01, 1.0) if total_z > 0 else 0.0
	var z_blue = clampf(float(total_z + 1) / (max_height_z + 1.0), 0.01, 1.0)
	
	var sil_mat = ShaderMaterial.new()
	sil_mat.shader = silhouette_shader
	
	match mode:
		ShadowMode.SHADOW_OBJECT:
			sil_mat.set_shader_parameter("height_color", Color(z_height, z_height, 0.0, 1.0))
		ShadowMode.SHADOW_CAST_ONLY:
			sil_mat.set_shader_parameter("height_color", Color(z_height, 0.0, z_blue, 1.0))
		ShadowMode.SHADOW_RECEIVE_ONLY:
			sil_mat.set_shader_parameter("height_color", Color(0.0, z_height, 0.0, 1.0))
		ShadowMode.ZERO_SHADOW:
			sil_mat.shader = silhouette_add_shader
			sil_mat.set_shader_parameter("height_color", Color(0.0, 0.0, z_blue, 1.0))
	
	height_clone.material = sil_mat
	height_clone.modulate = Color.WHITE
	
	height_clone.remove_from_group("ShadowObject")
	height_clone.remove_from_group("ShadowCastOnly")
	height_clone.remove_from_group("ShadowReceiveOnly")
	
	height_viewport.add_child(height_clone)
	height_clone.global_transform = visual_node.global_transform
	
	height_pairs.append([visual_node, height_clone])


func _spawn_test_multimesh() -> void:
	var tree_tex: Texture2D = load("res://assets/Grass.png")
	var random_color: Array = [
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
