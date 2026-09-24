shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.22, 0.42, 0.38, 0.85);
uniform vec4 deep_color : source_color = vec4(0.12, 0.28, 0.32, 1.0);
uniform float roughness : hint_range(0,1) = 0.15;
uniform float metallic : hint_range(0,1) = 0.05;
uniform float wave_scale : hint_range(0,2) = 0.5;
uniform float wave_speed : hint_range(0,2) = 0.6;
uniform sampler2D normal_map : hint_normal;

varying vec2 uv_world;

void vertex() {
	uv_world = VERTEX.xz * 0.08;
	// subtle wave
	float t = TIME * wave_speed;
	VERTEX.y += sin(VERTEX.x*0.2 + t*1.2)*0.04 * wave_scale;
	VERTEX.y += cos(VERTEX.z*0.18 + t*0.9)*0.035 * wave_scale;
}

void fragment() {
	vec2 uv = uv_world + TIME*0.02;
	// simple procedural normal wobble if no texture
	vec3 n = vec3(0,0,1);
	if (normal_map != sampler2D(normal_map)) {} // keep uniform
	// fake depth by uv
	float wave = sin(uv.x*12.0 + TIME*1.5)*0.5+0.5;
	wave *= cos(uv.y*10.0 + TIME*1.1)*0.5+0.5;
	vec3 col = mix(deep_color.rgb, water_color.rgb, 0.55 + wave*0.25);
	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALPHA = water_color.a;
	// fresnel-ish specular boost
	SPECULAR = 0.6;
}

