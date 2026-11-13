shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D heightmap_tex : repeat_disable, filter_nearest;

uniform vec2 heightmap_uv_scale = vec2(1.0, 1.0);
uniform vec2 heightmap_uv_offset = vec2(0.0, 0.0);

uniform vec2 sun_direction = vec2(0.7, -0.7);
uniform float max_ray_distance = 150.0;
uniform vec4 shadow_tint : source_color = vec4(0.15, 0.18, 0.30, 1.0);
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 world_color = texture(screen_texture, SCREEN_UV);
	
	vec2 base_hm_uv = SCREEN_UV * heightmap_uv_scale + heightmap_uv_offset;
	
	vec4 my_height_data = texture(heightmap_tex, base_hm_uv);
	float my_height = my_height_data.r + my_height_data.g;

	int steps = 64;
	float step_size = max_ray_distance / float(steps);
	
	vec2 hm_pixel_step = SCREEN_PIXEL_SIZE * heightmap_uv_scale;

	float in_shadow = 0.0;

	for (int i = 1; i <= steps; i++) {
		float dist = float(i) * step_size;
		vec2 sample_uv = base_hm_uv + (sun_direction * dist * hm_pixel_step);

		if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
			break;
		}

		vec4 sample_data = texture(heightmap_tex, sample_uv);
		float sample_height = sample_data.r + sample_data.g;

		float required_height = my_height + (float(i) / float(steps)) * 0.45;

		if (sample_height > required_height && sample_height > my_height + 0.02) {
			in_shadow = 1.0;
			break;
		}
	}

	float final_shadow = in_shadow * shadow_strength;
	vec3 shadowed_world = mix(world_color.rgb, world_color.rgb * shadow_tint.rgb, final_shadow);

	COLOR = vec4(shadowed_world, world_color.a);
}
