shader_type spatial;
render_mode cull_disabled;

uniform sampler2D original_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D painted_map : source_color, filter_linear_mipmap, repeat_enable;
varying float eyewear;

void vertex() {
	// These six source hat meshes contain separate eyewear below the hat brim.
	// Eyewear vertices end at y=0.342; the hat starts at y=0.511 in mesh space.
	// Select the existing pieces without modifying their vertices or UV data.
	eyewear = 1.0 - step(0.43, VERTEX.y);
}

void fragment() {
	ALBEDO = mix(texture(painted_map, UV).rgb, texture(original_map, UV).rgb, eyewear);
	ROUGHNESS = 0.85;
}
