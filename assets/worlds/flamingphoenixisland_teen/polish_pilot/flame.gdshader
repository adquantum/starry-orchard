shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
varying float phase;
void vertex(){
 vec3 scale=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 VERTEX*=scale;
 phase=INSTANCE_CUSTOM.r*6.28318;
}
void fragment(){
 float h=1.0-UV.y;
 float sway=sin(TIME*2.8+phase-h*5.0)*0.065*h;
 float x=UV.x-0.5-sway;
 float width=(0.39*(1.0-h)+0.02)*(0.92+0.08*sin(TIME*4.0+phase+h*10.0));
 float body=1.0-smoothstep(width*0.68,width,abs(x));
 float tip=smoothstep(0.0,0.09,h)*(1.0-smoothstep(0.72+0.10*sin(TIME*2.6+phase),1.0,h));
 float core=(1.0-smoothstep(0.03,0.20,abs(x)))*(1.0-smoothstep(0.20,0.72,h));
 ALBEDO=mix(vec3(1.0,0.13,0.006),vec3(1.0,0.73,0.16),core);
 EMISSION=ALBEDO*0.55;
 ALPHA=body*tip*0.87;
}
