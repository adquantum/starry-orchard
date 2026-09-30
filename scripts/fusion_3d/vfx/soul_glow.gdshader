shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D painted_sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 glow_color : source_color = vec4(1.0, 0.12, 0.3, 1.0);
uniform float energy = 1.3;

void vertex() {
	// Camera-facing sprite, preserving the condensation/shatter scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

void fragment() {
	vec4 paint = texture(painted_sprite, UV);
	float halo = 0.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		vec2 direction = vec2(cos(angle), sin(angle));
		halo += textureLod(painted_sprite, UV + direction * 0.018, 3.5).a * 0.075;
		halo += textureLod(painted_sprite, UV + direction * 0.038, 4.0).a * 0.05;
	}
	float light_plane = smoothstep(0.2, 0.85, max(paint.r, max(paint.g, paint.b)));
	// Preserve broad shaded planes; only the lit plane and silhouette radiate.
	vec3 body = paint.rgb * COLOR.rgb;
	ALBEDO = mix(glow_color.rgb, body, paint.a);
	EMISSION = mix(glow_color.rgb * energy, body * energy * (0.3 + light_plane * 0.65), paint.a);
	ALPHA = max(paint.a, halo * 0.22) * COLOR.a;
}
