shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}

void fragment() {
	vec3 weights=pow(abs(normalize(world_normal)),vec3(4.0));
	weights/=max(weights.x+weights.y+weights.z,0.001);
	vec3 p=world_position*0.035;
	vec3 grass=texture(meadow,p.xz).rgb*vec3(0.83,0.97,0.81);
	vec3 soil=texture(sand,p.xz*0.8).rgb*vec3(0.91,0.97,0.89);
	vec3 rock=texture(stone,p.zy).rgb*weights.x
		+texture(stone,p.xz).rgb*weights.y+texture(stone,p.xy).rgb*weights.z;
	// Broad green floor, broken sandy clearings and a sandy waterline.
	float patches=sin(world_position.x*0.041+sin(world_position.z*0.027)*1.7)
		*sin(world_position.z*0.035);
	float clearing=smoothstep(0.32,0.82,patches)*0.55;
	float beach=1.0-smoothstep(221.0,227.0,world_position.y);
	vec3 floor_color=mix(grass,soil,max(clearing,beach));
	float cliff=1.0-smoothstep(0.38,0.78,normalize(world_normal).y);
	// Keep stone structure readable, with green staining on the upper slopes.
	vec3 cliff_color=mix(rock*vec3(0.75,0.85,0.69),grass,0.22+0.22*max(patches,0.0));
	ALBEDO=mix(floor_color,cliff_color,cliff);
	ROUGHNESS=0.98;
	SPECULAR=0.1;
}
