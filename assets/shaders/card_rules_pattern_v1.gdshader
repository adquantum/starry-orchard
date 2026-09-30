shader_type canvas_item;
uniform float unavailable=0.0;
void fragment(){
	vec4 c=COLOR;
	vec2 edge=min(UV,vec2(1.0)-UV);
	c.a*=smoothstep(0.0,0.07,edge.x)*smoothstep(0.0,0.12,edge.y)*0.9;
	float gray=dot(c.rgb,vec3(.299,.587,.114));
	c.rgb=mix(c.rgb,vec3(gray),unavailable*.65)*(1.0-unavailable*.19);
	COLOR=c;
}
