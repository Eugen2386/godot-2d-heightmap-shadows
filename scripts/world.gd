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
@export var max_height_z: float = 20.0
var current_angle: float = 0.785

var height_pairs: Array[Array] = []

const SILHOUETTE_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 height_color = vec4(0.0, 0.5, 0.0, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(height_color.rgb, tex.a);
}
"""
var silhouette_shader: Shader


func _ready() -> void:
	process_priority = 10
	
	silhouette_shader = Shader.new()
	silhouette_shader.code = SILHOUETTE_SHADER_CODE
	
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
		var orig: Sprite2D = pair.front()
		var clone: Sprite2D = pair.back()
		if is_instance_valid(orig) and is_instance_valid(clone):
			clone.global_position = orig.global_position
			clone.global_rotation = orig.global_rotation
			clone.global_scale = orig.global_scale
			clone.visible = orig.visible
	
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
	for node in get_tree().get_nodes_in_group("HeightMap"):
		_create_height_clone(node, false)
		
	for node in get_tree().get_nodes_in_group("TerrainMap"):
		_create_height_clone(node, true)


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


func _create_height_clone(target_node: Node, is_terrain: bool) -> void:
	var visual_sprite: Sprite2D = target_node as Sprite2D
	if not visual_sprite:
		visual_sprite = target_node.get_node_or_null("Sprite2D")
	if not visual_sprite:
		return
	
	var height_clone = visual_sprite.duplicate() as Sprite2D
	height_clone.name = "AutoHeightSprite_" + visual_sprite.name
	height_clone.visibility_layer = 1
	
	var total_z = _get_total_z_index(visual_sprite)
	height_clone.z_index = total_z
	height_clone.z_as_relative = false
	
	var z_height = clampf(float(total_z) / max_height_z, 0.0, 1.0)
	
	var sil_mat = ShaderMaterial.new()
	sil_mat.shader = silhouette_shader
	if is_terrain:
		sil_mat.set_shader_parameter("height_color", Color(z_height, 0.0, 0.0, 1.0))
	else:
		sil_mat.set_shader_parameter("height_color", Color(0.0, z_height, 0.0, 1.0))
	
	height_clone.material = sil_mat
	height_clone.modulate = Color.WHITE
	
	height_clone.remove_from_group("HeightMap")
	height_clone.remove_from_group("TerrainMap")
	
	height_viewport.add_child(height_clone)
	height_clone.global_position = visual_sprite.global_position
	height_clone.global_rotation = visual_sprite.global_rotation
	height_clone.global_scale = visual_sprite.global_scale
	
	height_pairs.append([visual_sprite, height_clone])
