shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float progress = 0.0;
uniform float strength = 0.6;
void fragment() {
    float r=length((UV-vec2(0.5))*2.0);
    float wave=mix(0.08,1.15,smoothstep(0.0,0.65,progress));
    float ring=exp(-pow((r-wave)/0.09,2.0));
    float veil=(1.0-smoothstep(0.1,1.0,r))*0.18;
    float envelope=smoothstep(0.0,0.12,progress)*(1.0-smoothstep(0.45,0.95,progress));
    ALBEDO=vec3(0.70,0.82,1.0);
    ALPHA=(ring+veil)*envelope*strength*(1.0-smoothstep(0.92,1.0,r));
}
