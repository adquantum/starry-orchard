shader_type spatial;
uniform sampler2D source_ground : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D source_weights : filter_linear_mipmap, repeat_disable;
void fragment() {
 vec3 paint = texture(source_ground, UV).rgb;
 ALBEDO = paint;
 // Only the bright orange cores receive restrained glow; matte paths stay matte.
 float core = smoothstep(0.42,0.78,paint.r)*smoothstep(0.16,0.36,paint.r-paint.g)
              *smoothstep(0.025,0.10,paint.g-paint.b);
 EMISSION = paint*core*0.22;
 ROUGHNESS = mix(0.96,0.76,core);
 SPECULAR = 0.22;
}
