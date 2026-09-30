shader_type spatial;
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving : source_color, filter_linear_mipmap, repeat_enable;
uniform bool plaza_enabled = true;
uniform bool school_ground = false;
varying vec3 world_position;
varying vec3 world_normal;

float hash3(vec3 p) {
	p=fract(p*0.1031);
	p+=dot(p,p.yzx+33.33);
	return fract((p.x+p.y)*p.z);
}

float stone_noise(vec3 p) {
	vec3 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),
		mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),
		mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}

vec3 natural_rock(vec3 pos) {
	// Mountain-size formations: the old unused 26m strata made the entire
	// 500m summit read as a tiny repeated rock. These bands span whole ribs.
	float broad = stone_noise(pos * vec3(0.009, 0.013, 0.009));
	float strata = sin(pos.y * 0.039 + broad * 3.6 + pos.x * 0.008 - pos.z * 0.011);
	float layer = smoothstep(-0.72, 0.85, strata);
	return mix(vec3(0.26, 0.30, 0.29), vec3(0.48, 0.49, 0.44), broad * 0.65 + layer * 0.35);
}

vec3 rock_projection(vec2 uv, float variation) {
	// Two independent scales and a quarter turn remove the unmistakable
	// diagonal wallpaper pattern while retaining the existing painted asset.
	vec3 a = texture(cliff_texture, uv).rgb;
	vec3 b = texture(cliff_texture, vec2(-uv.y, uv.x) * 0.73 + vec2(0.37, 0.61)).rgb;
	return mix(a, b, 0.25 + variation * 0.50);
}

vec3 mountain_rock(vec3 pos, vec3 weights, float camera_distance) {
	float broad = stone_noise(pos * 0.007 + vec3(3.1, 8.4, 0.7));
	// A painted tile covers 118m instead of 29m; distant summits keep their
	// broad color masses while nearby cliffs retain readable brushwork.
	vec3 p = pos * 0.0085;
	vec3 painted = rock_projection(p.zy, broad) * weights.x
		+ rock_projection(p.xy, broad) * weights.z
		+ rock_projection(p.xz, broad) * weights.y;
	float distant = smoothstep(160.0, 800.0, camera_distance);
	vec3 stone = mix(painted, natural_rock(pos), 0.32 + distant * 0.30);
	float high_peak = smoothstep(365.0, 610.0, pos.y);
	stone = mix(stone, vec3(0.35, 0.41, 0.45), distant * high_peak * 0.24);
	return stone;
}

void vertex() {
	world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}

void fragment() {
	vec3 n=normalize(world_normal);
	vec3 p=world_position*0.055;
	vec3 weights=pow(abs(n),vec3(4.0));
	weights/=max(weights.x+weights.y+weights.z,0.001);
	vec3 stone = mountain_rock(world_position, weights, distance(CAMERA_POSITION_WORLD, world_position));
	vec3 meadow=texture(grass,p.xz*0.65).rgb*vec3(0.91,0.98,0.88);
	vec3 sand=texture(soil,p.xz*0.65).rgb*vec3(0.94,0.98,0.92);
	// Keep the themed soil readable through paths and arenas; the coast stays sandy.
	vec3 trail_soil=school_ground ? mix(meadow, sand, 0.20) : sand;
	float shore=1.0-smoothstep(220.3,228.0,world_position.y);
	float steep=1.0-smoothstep(0.52,0.85,n.y);
	vec3 generated=mix(mix(meadow,sand,shore),stone*vec3(0.88,0.93,0.84),steep*0.85);
	generated=mix(generated,trail_soil,clamp(COLOR.g,0.0,1.0)*0.55*(1.0-steep));
	generated=mix(generated,mix(meadow,trail_soil,0.68),clamp(COLOR.b,0.0,1.0)*0.8);
	// Preserve the town's painted roads only on gentle ground, never on cliffs.
	float preserve=clamp(COLOR.r,0.0,1.0)*smoothstep(0.72,0.94,n.y)*(1.0-smoothstep(285.0,340.0,world_position.y));
	vec3 color=mix(generated,texture(base_texture,UV).rgb,preserve);
	if (plaza_enabled) {
		float r=distance(world_position.xz,vec2(881.310547,-219.205078));
		float amount=smoothstep(23.5,25.5,r)*(1.0-smoothstep(35.5,41.5,r))*0.62;
		vec3 stones=texture(paving,world_position.xz*(16.0/533.333313)).rgb;
		float luminance=dot(stones,vec3(0.2126,0.7152,0.0722));
		color=mix(color,clamp(mix(stones,vec3(luminance),0.55)*vec3(1.16,1.13,1.10),0.0,1.0),amount);
	}
	ALBEDO=color;
	ROUGHNESS=0.98;
	SPECULAR=0.16;
}
