// spell_cast_vfx.gdshader
// 施法特效着色器 —— 投影到全屏闪光 ColorRect 上
// 触发时 alpha 从 1→0，配合 Tween 控制

shader_type canvas_item;

uniform vec4  flash_color : source_color = vec4(1.0, 0.42, 0.1, 1.0);
uniform float dissolve    : hint_range(0.0, 1.0) = 0.0;  // 由代码驱动 0→1
uniform float pixel_size  : hint_range(1.0, 8.0) = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// 像素化噪点遮罩
	vec2 pix = floor(UV / pixel_size / TEXTURE_PIXEL_SIZE.xy) * pixel_size * TEXTURE_PIXEL_SIZE.xy;
	float n = hash(pix * 10.0 + vec2(TIME * 0.3, 0.0));

	// dissolve：噪点高于 threshold 时消失
	float threshold = dissolve;
	float mask = step(threshold, n);

	// 发光边缘（在消融边界处叠加高亮）
	float edge_width = 0.05;
	float edge = step(threshold - edge_width, n) * (1.0 - mask);
	vec4 edge_col = vec4(1.0, 1.0, 0.8, 1.0);

	COLOR = mix(
		mix(flash_color, edge_col, edge),
		vec4(0.0),
		1.0 - mask
	);
}
