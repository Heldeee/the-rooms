shader_type spatial;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 carpet_color : source_color = vec4(0.46, 0.42, 0.31, 1.0);
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > max(n.x, n.z) ? world_position.xz : (n.x > n.z ? world_position.zy : world_position.xy);
	float fibers = texture(grain, uv * vec2(8.0, 13.0)).r;
	float pile = texture(grain, uv * 1.7).r;
	float stain = texture(grain, uv * 0.085 + vec2(0.37, 0.61)).r;
	ALBEDO = carpet_color.rgb * (0.79 + fibers * 0.26 + pile * 0.12);
	ALBEDO *= 1.0 - smoothstep(0.53, 0.76, stain) * 0.23;
	ROUGHNESS = 0.98;
}
