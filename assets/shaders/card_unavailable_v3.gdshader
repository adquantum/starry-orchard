shader_type canvas_item;
uniform float unavailable=0.0;
void fragment(){
	vec4 c=COLOR;
	float gray=dot(c.rgb,vec3(.299,.587,.114));
	c.rgb=mix(c.rgb,vec3(gray),unavailable*.65)*(1.0-unavailable*.19);
	COLOR=c;
}
