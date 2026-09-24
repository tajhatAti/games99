shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// PUBG-style paddy rice wind - cheap vertex sway, per-instance variation via INSTANCE_CUSTOM
uniform float wind_strength : hint_range(0.0, 1.5) = 0.35;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;
uniform vec2 wind_dir = vec2(1.0, 0.3);
uniform float sway_height_bias : hint_range(0.0, 2.0) = 1.0;
uniform vec4 albedo_color : source_color = vec4(0.42, 0.62, 0.28, 1.0);
uniform float roughness : hint_range(0.0,1.0) = 0.85;
uniform sampler2D noise_tex : hint_default_white;

varying vec3 v_pos;

void vertex() {
	// height factor: taller vertices sway more
	float h = clamp((VERTEX.y + 0.3) * sway_height_bias, 0.0, 1.2);
	// per-instance random from INSTANCE_CUSTOM (set from GDScript)
	float inst_rand = INSTANCE_CUSTOM.x * 6.283;
	float inst_phase = INSTANCE_CUSTOM.y * 2.0;
	// world position for spatial variation
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	float t = TIME * wind_speed;
	// two octave sine for natural gust
	float gust = sin(t * 0.7 + wpos.x * 0.08 + wpos.z * 0.05 + inst_rand) * 0.6
	           + sin(t * 1.9 + wpos.x * 0.15 - wpos.z*0.07 + inst_phase) * 0.35;
	gust *= wind_strength * h;
	// sway along wind dir
	VERTEX.x += gust * wind_dir.x;
	VERTEX.z += gust * wind_dir.y;
	// slight vertical wiggle
	VERTEX.y += sin(t*1.4 + wpos.x*0.1)*0.015 * h;
	v_pos = VERTEX;
}

void fragment() {
	// subtle variation by height + instance
	float h = clamp(v_pos.y * 1.5, 0.0, 1.0);
	vec3 base = albedo_color.rgb;
	// darker at root, brighter at tip
	base = mix(base * 0.75, base * 1.15, h);
	// per-instance tint
	base *= 0.9 + INSTANCE_CUSTOM.z * 0.25;
	// fake AO at bottom
	float ao = 1.0 - (1.0 - h)*0.25;
	ALBEDO = base * ao;
	ROUGHNESS = roughness;
	// slight SSS-ish
	SSS_STRENGTH = 0.25;
}

void light() {
	// gentle translucent look
	DIFFUSE_LIGHT *= 1.0;
}
