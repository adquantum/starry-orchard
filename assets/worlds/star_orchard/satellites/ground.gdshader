shader_type spatial;
render_mode cull_back;
uniform sampler2D grass : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D paving : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D snow : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D soil : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int design = 0;
uniform vec2 island_center = vec2(0.0);
varying vec2 p;
void vertex() { p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz-island_center; }
float segment(vec2 v, vec2 a, vec2 b) {
    vec2 ab=b-a;return length(v-a-ab*clamp(dot(v-a,ab)/dot(ab,ab),0.0,1.0));
}
float curve(vec2 v, vec2 a, vec2 b, vec2 c, vec2 d) {
    float dist=1000.0;vec2 prev=a;
    for(int i=1;i<=12;i++) {
        float t=float(i)/12.0;float s=1.0-t;
        vec2 next=s*s*s*a+3.0*s*s*t*b+3.0*s*t*t*c+t*t*t*d;
        dist=min(dist,segment(v,prev,next));prev=next;
    }
    return dist;
}
float ellipse(vec2 v,vec2 c,vec2 r) { return (length((v-c)/r)-1.0)*min(r.x,r.y); }
float box(vec2 v,vec2 c,vec2 r) { vec2 q=abs(v-c)-r;return length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0); }
float fill(float d,float f) { return 1.0-smoothstep(-f,f,d); }
float lane(float d,float w) { return 1.0-smoothstep(w,w+2.3,d); }
float edge_break(vec2 v) { return sin(v.x*.16+sin(v.y*.09)*2.0)*1.4+sin(v.y*.27+v.x*.08)*.6; }
vec3 soften(vec3 tex,vec3 base,float contrast) {
    float lum=dot(tex,vec3(.22,.65,.13));return base*(.85+lum*.3)+(tex-vec3(lum))*contrast;
}
vec3 grass_color(vec2 v) {
    vec3 base=mix(vec3(.24,.38,.19),vec3(.41,.48,.27),.5+.5*sin(v.x*.028+sin(v.y*.031)));
    return soften(texture(grass,v/43.0).rgb,base,.19);
}
vec3 stone_color(vec2 v) { return soften(texture(paving,v/28.0).rgb,vec3(.66,.65,.52),.34); }
vec3 earth_color(vec2 v) { return soften(texture(soil,v/34.0).rgb,vec3(.43,.33,.21),.27); }
vec3 rock_color(vec2 v) { return soften(texture(rock,v/45.0).rgb,vec3(.57,.60,.57),.3); }
// START: winding garden walks and scalloped flower beds around broad lawn pockets.
vec3 garden(vec2 v) {
    float walk=curve(v,vec2(-62,38),vec2(-93,5),vec2(-67,-53),vec2(-15,-67));
    walk=min(walk,curve(v,vec2(-15,-67),vec2(77,-82),vec2(77,-8),vec2(62,38)));
    walk=min(walk,curve(v,vec2(0,66),vec2(18,41),vec2(-10,21),vec2(1,-22)));
    walk=min(walk,curve(v,vec2(-62,38),vec2(-28,59),vec2(19,42),vec2(62,38)));
    float bed=min(ellipse(v,vec2(-71,-27),vec2(16,22)),ellipse(v,vec2(54,-56),vec2(28,12)));
    bed=min(bed,ellipse(v,vec2(32,55),vec2(18,8)));
    vec3 base=mix(grass_color(v),vec3(.35,.40,.23),fill(bed+edge_break(v),2.8)*.75);
    float flowers=fill(bed+edge_break(v),2.8)*(.5+.5*sin(v.x*1.6)*sin(v.y*1.1));
    base=mix(base,vec3(.57,.40,.43),flowers*.42);
    return mix(base,stone_color(v),lane(walk+edge_break(v)*.25,3.8)*.92);
}
// GROVE: diagonal branching dirt trails, separate orchard plots and mossy rows.
vec3 orchard(vec2 v) {
    float route=curve(v,vec2(-62,38),vec2(-32,19),vec2(-6,-46),vec2(65,-55));
    route=min(route,curve(v,vec2(0,66),vec2(15,41),vec2(-40,35),vec2(-23,0)));
    route=min(route,curve(v,vec2(62,38),vec2(23,30),vec2(59,-6),vec2(12,-23)));
    float plots=min(box(v,vec2(-62,-39),vec2(26,31)),box(v,vec2(61,-56),vec2(25,17)));
    plots=min(plots,ellipse(v,vec2(43,61),vec2(22,14)));
    float planted=fill(plots+edge_break(v)*1.7,4.0);
    float rows=.5+.5*sin(v.y*.6+v.x*.16);
    vec3 base=mix(grass_color(v)*.88,earth_color(v)*.78,planted*.95);
    base=mix(base,vec3(.27,.34,.16),planted*smoothstep(.45,.85,rows)*.44);
    return mix(base,earth_color(v)*1.12,lane(route+edge_break(v)*.8,4.2));
}
// GUARD: pale rectangular court, laid blocks, perimeter band and turf joints.
vec3 courtyard(vec2 v) {
    float paved=fill(box(v,vec2(0,-10),vec2(78,62))+edge_break(v)*.4,3.0);
    vec2 grid=abs(fract((v+vec2(4,2))/vec2(13,10))-.5)*vec2(13,10);
    float seams=1.0-smoothstep(.10,.30,min(grid.x,grid.y));
    vec3 slabs=mix(stone_color(v)*1.17,vec3(.31,.37,.27),seams*.55);
    float band=lane(abs(box(v,vec2(0,-10),vec2(71,55))),1.4);
    slabs=mix(slabs,vec3(.46,.49,.44),band*.72);
    float planting=min(box(v,vec2(-21,29),vec2(4,13)),box(v,vec2(21,29),vec2(4,13)));
    planting=min(planting,box(v,vec2(-63,-49),vec2(8,7)));
    vec3 base=mix(grass_color(v),slabs,paved);
    base=mix(base,grass_color(v)*.82,fill(planting,1.2));
    float entry=lane(segment(v,vec2(0,66),vec2(0,41)),5.5);
    return mix(base,slabs,max(entry,lane(segment(v,vec2(-62,38),vec2(62,38)),3.0)));
}
// FROST: snow banks, exposed slate, fractured stone and an icy meltwater pocket.
vec3 frostfield(vec2 v) {
    float channel=curve(v,vec2(-86,55),vec2(-31,14),vec2(-20,-28),vec2(77,-61));
    float bare=lane(channel+edge_break(v)*1.7,11.0);
    bare=max(bare,fill(ellipse(v,vec2(43,5),vec2(30,23))+edge_break(v)*2.2,5.0));
    bare=max(bare,fill(ellipse(v,vec2(-68,-45),vec2(24,31))+edge_break(v),4.0));
    vec3 snowy=soften(texture(snow,v/51.0).rgb,vec3(.59,.70,.76),.18);
    vec3 slate=soften(texture(rock,v/33.0).rgb,vec3(.39,.49,.56),.2);
    float fractures=1.0-smoothstep(.1,.6,abs(sin(v.x*.17+v.y*.09))*5.0);
    slate=mix(slate,vec3(.22,.36,.44),fractures*.3);
    vec3 base=mix(snowy,slate,bare*.92);
    float ice=fill(ellipse(v,vec2(-7,19),vec2(19,11))+edge_break(v)*.8,3.0);
    return mix(base,vec3(.34,.65,.71),ice*.65);
}
// WIND: pale wind-eroded chalk terraces; the curved ascent joins the real ramp.
vec3 windcourt(vec2 v) {
    float walk=curve(v,vec2(-62,38),vec2(-80,57),vec2(-29,55),vec2(0,15));
    walk=min(walk,curve(v,vec2(62,38),vec2(75,2),vec2(52,-30),vec2(34,-52)));
    walk=min(walk,curve(v,vec2(0,66),vec2(45,73),vec2(22,27),vec2(0,15)));
    walk=min(walk,segment(v,vec2(0,15),vec2(0,-22)));
    float chalk=fill(ellipse(v,vec2(0,-25),vec2(89,71))+edge_break(v)*1.6,9.0);
    vec3 stone=soften(texture(rock,v/59.0).rgb,vec3(.72,.71,.62),.20);
    float strata=1.0-smoothstep(.14,.6,abs(sin(v.y*.12+sin(v.x*.037)*1.8))*4.0);
    stone=mix(stone,vec3(.51,.53,.48),strata*.32);
    vec3 base=mix(grass_color(v)*.88,stone,chalk*.95);
    base=mix(base,stone_color(v)*1.10,lane(walk,4.2));
    float arc=lane(abs(length(v-vec2(0,-39))-25.5),.50)*smoothstep(-55.0,-40.0,v.x);
    return mix(base,vec3(.48,.56,.62),arc*.66);
}
// TRIAL: one six-point ritual seal, with a broken outer ring and grass invasion.
vec3 trial(vec2 v) {
    vec2 q=v-vec2(0,-7);float r=length(q);
    float field=fill(r-66.0+edge_break(v)*1.7,4.0);
    vec3 base=mix(grass_color(v)*.81,stone_color(v)*vec3(.94,.91,1.09),field);
    float star=min(segment(q,vec2(0,-59),vec2(51,29.5)),segment(q,vec2(51,29.5),vec2(-51,29.5)));
    star=min(star,segment(q,vec2(-51,29.5),vec2(0,-59)));
    star=min(star,segment(q,vec2(0,59),vec2(51,-29.5)));
    star=min(star,segment(q,vec2(51,-29.5),vec2(-51,-29.5)));
    star=min(star,segment(q,vec2(-51,-29.5),vec2(0,59)));
    float seal=max(lane(star,.75),lane(abs(r-63.0),1.0));
    seal=max(seal,lane(abs(r-20.0),.5));
    float breakage=fill(ellipse(v,vec2(-59,24),vec2(19,24))+edge_break(v),3.0);
    breakage=max(breakage,fill(ellipse(v,vec2(53,-45),vec2(24,14))+edge_break(v),2.0));
    base=mix(base,vec3(.34,.31,.44),seal*(1.0-breakage)*.82);
    base=mix(base,grass_color(v)*.84,breakage*.90);
    float approach=lane(curve(v,vec2(-62,38),vec2(-43,76),vec2(42,77),vec2(62,38)),5.0);
    return mix(base,stone_color(v),approach*.90);
}
// RETURN: packed camp clearings, a flagstone loading apron and wandering trail.
vec3 camp(vec2 v) {
    float dirt=min(ellipse(v,vec2(-42,-17),vec2(43,57)),ellipse(v,vec2(39,7),vec2(39,31)));
    dirt=min(dirt,ellipse(v,vec2(0,-39),vec2(29,26)));
    vec3 base=mix(grass_color(v)*.90,earth_color(v)*1.18,fill(dirt+edge_break(v)*2.0,6.0));
    float trail=curve(v,vec2(-62,38),vec2(-12,10),vec2(14,72),vec2(62,38));
    trail=min(trail,curve(v,vec2(0,66),vec2(40,45),vec2(19,10),vec2(0,-55)));
    base=mix(base,earth_color(v)*1.34,lane(trail+edge_break(v)*.5,5.4));
    float loading=fill(box(v,vec2(-61,-31),vec2(15,20))+edge_break(v)*.65,2.0);
    base=mix(base,stone_color(v)*.94,loading);
    float scattered=fill(ellipse(v,vec2(36,38),vec2(28,13))+edge_break(v)*2.0,4.0);
    return mix(base,stone_color(v),scattered*.60);
}
void fragment() {
    if(design==0) ALBEDO=garden(p);
    else if(design==1) ALBEDO=orchard(p);
    else if(design==2) ALBEDO=courtyard(p);
    else if(design==3) ALBEDO=frostfield(p);
    else if(design==4) ALBEDO=windcourt(p);
    else if(design==5) ALBEDO=trial(p);
    else ALBEDO=camp(p);
    ROUGHNESS=design==3 ? .80 : .94;
}
