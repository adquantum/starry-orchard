shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_mix;
uniform sampler2D effect_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec3 effect_center = vec3(0.0);
uniform float effect_radius = 1.0;
uniform float inner_clear_radius = 0.0;
uniform bool billboard = false;
varying vec3 world_vertex;
void vertex() {
	mat4 world = MODEL_MATRIX;
	if (billboard) {
		world = mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * world;
	}
	world_vertex = (world * vec4(VERTEX, 1.0)).xyz;
	UV = UV * uv_scale.xy + uv_offset.xy;
}
void fragment() {
	float distance_from_center = length(world_vertex.xz - effect_center.xz);
	float edge = 1.0 - smoothstep(effect_radius * 0.94, max(effect_radius, 0.00001), distance_from_center);
	float center = inner_clear_radius > 0.0 ? smoothstep(inner_clear_radius * 0.85, inner_clear_radius, distance_from_center) : 1.0;
	vec4 pixel = texture(effect_texture, UV) * tint;
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a * edge * center;
}
