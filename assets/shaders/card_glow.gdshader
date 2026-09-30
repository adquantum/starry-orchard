// card_glow.gdshader
// 卡牌像素魔法光晕着色器
// 用于卡牌悬停时的边缘发光 + 粒子感噪点效果
// 平台：PC/Console（移动端去掉 noise_glow 节省 ALU）

shader_type canvas_item;

// ─── 参数 ───────────────────────────────────────────────────────────────────
uniform vec4  glow_color  : source_color = vec4(1.0, 0.42, 0.1, 1.0);  // 默认火焰橙
uniform float glow_width  : hint_range(0.0, 0.05, 0.001) = 0.02;       // 外发光宽度
uniform float glow_intensity : hint_range(0.0, 3.0, 0.1) = 1.5;
uniform float pixel_size  : hint_range(1.0, 8.0, 1.0)   = 2.0;        // 像素块大小（像素化效果）
uniform float time_scale  : hint_range(0.0, 4.0, 0.1)   = 1.0;
uniform bool  mobile_mode = false;   // true 时关闭 noise，节省性能

// ─── 工具函数 ────────────────────────────────────────────────────────────────
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ─── 主函数 ─────────────────────────────────────────────────────────────────
void fragment() {
	// 像素化 UV（让贴图看起来有像素感）
	vec2 pixel_uv = floor(UV * TEXTURE_PIXEL_SIZE.zw / pixel_size) * pixel_size * TEXTURE_PIXEL_SIZE.xy;
	vec4 base_color = texture(TEXTURE, pixel_uv);

	// 边缘采样（用于计算是否在边缘附近）
	float alpha_n = texture(TEXTURE, UV + vec2(0.0,  glow_width)).a;
	float alpha_s = texture(TEXTURE, UV + vec2(0.0, -glow_width)).a;
	float alpha_e = texture(TEXTURE, UV + vec2( glow_width, 0.0)).a;
	float alpha_w = texture(TEXTURE, UV + vec2(-glow_width, 0.0)).a;
	float edge    = max(max(alpha_n, alpha_s), max(alpha_e, alpha_w)) - base_color.a;
	edge = clamp(edge, 0.0, 1.0);

	// 动态噪点（仅 PC 模式）
	float flicker = 1.0;
	if (!mobile_mode) {
		float t = TIME * time_scale;
		flicker = 0.85 + 0.15 * noise(UV * 8.0 + vec2(t * 0.7, t * 0.5));
	}

	// 合成：原色 + 边缘光晕
	vec4 glow = glow_color * edge * glow_intensity * flicker;
	COLOR = vec4(
		mix(base_color.rgb, glow_color.rgb, glow.a * edge),
		base_color.a + glow.a
	);
}
