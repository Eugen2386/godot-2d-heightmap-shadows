shader_type canvas_item;
render_mode blend_mix;

uniform bool heightmap_mode = false;
uniform vec4 height_color = vec4(0.0, 0.5, 0.0, 1.0);
uniform bool additive_heightmap = false;

instance uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_palette = false;
uniform vec4 color_palette[4] : source_color;

uniform bool pixel_mode = true;
uniform float pixel_amount = 32.0;
uniform float distortion : hint_range(0.0, 0.1) = 0.01;

/// Noise Texture System
uniform bool texture_noise_system = true;
uniform float noise_speed = 1.0;
uniform int noise_direction : hint_range(-1, 1) = -1;
uniform sampler2D noise_texture : source_color, repeat_enable;

/// Worley System
uniform bool worley_noise_system = false;
uniform float worley_cell_density = 10.0;
uniform float worley_speed = 2.0;

/// Borders Effect
uniform sampler2D mask_texture : source_color, filter_nearest;
uniform bool edge_and_mask = false;
uniform float alpha_value : hint_range(0.0, 1.0) = 1.0;

varying vec2 inst_origin;

void vertex() {
	inst_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
}

/// Worley Methods
vec2 random(vec2 uv) {
	return vec2(fract(sin(dot(uv.xy,
		vec2(12.9898, 78.233))) * 43758.5453123));
}

float worley(vec2 uv, float columns, float rows, float time) {
	vec2 index_uv = floor(vec2(uv.x * columns, uv.y * rows));
	vec2 fract_uv = fract(vec2(uv.x * columns, uv.y * rows));
	
	float minimum_dist = 1.0;
	
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = random(index_uv + neighbor);
			point = vec2(cos(time * point.x * worley_speed), sin(time * point.y * worley_speed)) * 0.5 + 0.5;
			
			vec2 diff = neighbor + point - fract_uv;
			float dist = length(diff);
			minimum_dist = min(minimum_dist, dist);
		}
	}
	
	return minimum_dist;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 uv_result = vec4(0.0);
	vec2 uv;
	
	/// Pixel Mode
	if (pixel_mode) {
		uv = floor(UV * pixel_amount) / pixel_amount;
	} else {
		uv = UV;
	}
	
	/// Noise Texture System
	if (texture_noise_system) {
		vec4 noise_uv = texture(noise_texture, uv + TIME * noise_speed * float(noise_direction));
		uv_result += noise_uv;
	}
	
	/// Worley Noise System
	if (worley_noise_system) {
		float worley_val = worley(uv, worley_cell_density, worley_cell_density, TIME);
		vec4 result = texture(TEXTURE, vec2(worley_val));
		uv_result += result;
	}
	
	/// Blend
	vec2 noise_uv = mix(uv, uv_result.rg, distortion);

	vec4 active_tint = tint_color;
	if (use_palette) {
		int idx = int(floor(hash21(floor(inst_origin)) * 4.0)) % 4;
		active_tint = color_palette[idx];
	}
	
	if (edge_and_mask) {
		vec4 base = texture(TEXTURE, uv);
		vec4 blend = texture(mask_texture, noise_uv);
	
		vec4 final_color = mix(base, blend, blend.a);
		
		COLOR = vec4(final_color.rgb * active_tint.rgb, (texture(TEXTURE, noise_uv).a) * alpha_value * active_tint.a);
	} else {
		vec4 tex = texture(TEXTURE, noise_uv);
		COLOR = vec4(tex.rgb * active_tint.rgb, tex.a * alpha_value * active_tint.a);
	}

	if (heightmap_mode) {
		if (COLOR.a < 0.05) { discard; }
		if (additive_heightmap) {
			COLOR = vec4(height_color.rgb * COLOR.a, 1.0);
		} else {
			COLOR = vec4(height_color.rgb, COLOR.a);
		}
	}
}
