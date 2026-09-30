shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 school_color : source_color;
void fragment() {
 float edge=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),1.5);
 ALBEDO=school_color.rgb;
 ALPHA=0.035+edge*0.3;
}

