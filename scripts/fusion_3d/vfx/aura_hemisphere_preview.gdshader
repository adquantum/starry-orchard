shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords, depth_draw_never;
uniform sampler2D aura_texture : source_color, filter_linear_mipmap;
uniform bool textured = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform mat4 aura_world;
uniform mat4 aura_inverse;
uniform float source_height = 2.15;
uniform float dome_radius = 2.1;
void vertex() {
    vec3 p = (aura_inverse * vec4(VERTEX, 1.0)).xyz;
    float height_fraction = clamp(p.y / source_height, 0.0, 0.995);
    p.xz *= (dome_radius / 1.12) * sqrt(max(0.002, 1.0-height_fraction*height_fraction));
    p.y = height_fraction * dome_radius;
    VERTEX = (aura_world * vec4(p, 1.0)).xyz;
}
void fragment() {
    vec4 pixel = tint * (textured ? texture(aura_texture, UV) : vec4(1.0));
    ALBEDO = pixel.rgb;
    ALPHA = pixel.a;
}
