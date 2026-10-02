shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 paper_color : source_color = vec4(0.72, 0.64, 0.4, 1.0);
uniform float wear = 0.1;
uniform float floral = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > max(n.x, n.z) ? world_position.xz : (n.z > n.x ? world_position.xy : world_position.zy);
	float fiber = texture(grain, uv * vec2(1.8, 0.55)).r;
	float aging = texture(grain, uv * 0.11 + vec2(0.13, 0.73)).r;
	float stain = smoothstep(0.49, 0.72, aging) * wear;
	stain *= 0.35 + 0.65 * (1.0 - smoothstep(0.15, 1.7, uv.y));
	// Fine printed lines fade with pixel footprint, avoiding moire in motion.
	float frequency = 6.2831853 / 0.065;
	float footprint = max(fwidth(uv.x) * frequency, 0.0001);
	float line = sin(uv.x * frequency) * (sin(footprint * 0.5) / (footprint * 0.5)) * (1.0 - smoothstep(0.8, 2.0, footprint));
	float seam_dist = min(fract(uv.x / 0.53), 1.0 - fract(uv.x / 0.53)) * 0.53;
	float seam = 1.0 - smoothstep(0.001, 0.001 + max(fwidth(uv.x), 0.001), seam_dist);
	vec2 motif = fract(uv / vec2(0.21, 0.29)) - 0.5;
	float petal = pow(max(0.0, cos(motif.x * 6.2831853) * cos(motif.y * 6.2831853)), 6.0);
	float ornament = petal * floral * max(0.0, 1.0 - length(fwidth(uv)) * 25.0);
	ALBEDO = paper_color.rgb * (0.91 + fiber * 0.12 + line * 0.028 - seam * 0.035 - ornament * 0.12);
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.46, 0.5, 0.39), stain);
	ROUGHNESS = 0.95;
}
