shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 dirt_color : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform vec4 mud_color : source_color = vec4(0.28, 0.24, 0.20, 1.0);
uniform float roughness : hint_range(0,1) = 0.95;
uniform float mud_mix : hint_range(0,1) = 0.0; // 0 dirt, 1 mud
uniform sampler2D dirt_noise : hint_default_white;

void fragment() {
	vec2 uv = UV * 8.0;
	// cheap procedural noise via sin
	float n = sin(uv.x*12.3)*sin(uv.y*11.7)*0.08;
	vec3 col = mix(dirt_color.rgb, mud_color.rgb, mud_mix);
	col += n;
	// darker wet when mud
	if (mud_mix > 0.5) {
		col *= 0.92;
		ROUGHNESS = 0.75;
	} else {
		ROUGHNESS = roughness;
	}
	ALBEDO = col;
	ROUGHNESS = roughness - mud_mix*0.2;
	METALLIC = 0.0;
}
