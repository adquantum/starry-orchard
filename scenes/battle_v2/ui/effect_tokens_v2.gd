extends RefCounted
const WIDTH:=114.0
const HEIGHT:=19.0
const GAP:=2.0
const ICON:=18.0
const VALUE_WIDTH:=34.0
const DIGIT_ADVANCE:=8.0
const VALUE_SIZE:=13
const INK=Color("f4e8c9")
const ACCENTS={"fire":Color("b48978"),"ice":Color("8cabb4"),"storm":Color("a292b6"),"life":Color("92ab86"),"death":Color("a095a7"),"balance":Color("b29e85"),"myth":Color("b4ac81"),"all":Color("b3aa92")}
static func accent(school: String) -> Color:return ACCENTS.get(school,ACCENTS.all)
static func top(count: int) -> float:return (63.0-count*HEIGHT-maxi(0,count-1)*GAP)/2.0
static func number_font() -> FontVariation:
	var f:=FontVariation.new()
	f.base_font=ThemeDB.fallback_font
	f.variation_embolden=0.65
	return f
static func draw_number(canvas: CanvasItem, value: String, x: float, y: float, width: float, font: Font, font_size: int=VALUE_SIZE, advance: float=DIGIT_ADVANCE) -> void:
	var start:=x+width-value.length()*advance
	for i in value.length():
		var character:=value.substr(i,1)
		var glyph_width:=font.get_string_size(character,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		canvas.draw_string(font,Vector2(start+i*advance+(advance-glyph_width)/2.0,y),character,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,INK)
