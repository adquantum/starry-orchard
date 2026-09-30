shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D glyph : filter_linear_mipmap;
uniform vec4 ink_color : source_color;
void fragment() { ALBEDO=ink_color.rgb; ALPHA=texture(glyph,UV).a; }
