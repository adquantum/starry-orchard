shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D source_weights : filter_linear_mipmap, repeat_disable;
varying vec3 world_pos;
varying float up;
float pilot(vec2 p){return max(max(1.0-smoothstep(58.0,100.0,distance(p,vec2(-189.1875,-382.785156))),1.0-smoothstep(58.0,100.0,distance(p,vec2(-195,-150)))),1.0-smoothstep(58.0,100.0,distance(p,vec2(45,-240))));}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;up=clamp((MODEL_NORMAL_MATRIX*NORMAL).y,0.0,1.0);VERTEX.y+=0.45;}
void fragment(){
 float amount=texture(source_weights,UV).a*pilot(world_pos.xz)*smoothstep(0.4,0.8,up);
 if(amount<0.05){discard;}
 vec2 wave=vec2(sin(world_pos.z*0.6+TIME*1.7),cos(world_pos.x*0.47-TIME*1.2));
 // Subpixel shimmer at 1600px; localized to the existing lava surface.
 ALBEDO=texture(screen_tex,clamp(SCREEN_UV+wave*0.00065*amount,vec2(0.001),vec2(0.999))).rgb;
 ALPHA=amount*0.16;
}
