extends RefCounted
## One school per generated island; the main town remains the shared seven-school hub.
static func profiles() -> Array[Dictionary]:
	return [
		{"id":0,"name":"西岸生命果园","school":"life","center":Vector2(270,-235),"rotation":0.0,"start":Vector2(-40,-496),"cells":Vector2i(158,132)},
		{"id":1,"name":"南湾烈焰果园","school":"fire","center":Vector2(1080,594),"rotation":0.0,"start":Vector2(776,328),"cells":Vector2i(165,132)},
		{"id":2,"name":"北境霜果岛","school":"ice","center":Vector2(1000,-1180),"rotation":PI*0.5,"start":Vector2(660,-1520),"cells":Vector2i(170,170)},
		{"id":3,"name":"东北风暴果岛","school":"storm","center":Vector2(1770,-900),"rotation":-PI*0.5,"start":Vector2(1410,-1260),"cells":Vector2i(180,180)},
		{"id":4,"name":"东境幻果岛","school":"myth","center":Vector2(1950,-100),"rotation":PI,"start":Vector2(1610,-440),"cells":Vector2i(170,170)}
	]
