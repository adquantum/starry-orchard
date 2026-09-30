extends RefCounted
## Presentation-only formatting. Preserve increase/decrease meaning without signs.
static func clean(value: String) -> String:
	var range_pattern:=RegEx.new()
	range_pattern.compile("([0-9])[-−]([0-9])")
	value=range_pattern.sub(value,"$1至$2",true)
	var plus:=RegEx.new();plus.compile("[+＋]([0-9])")
	var minus:=RegEx.new();minus.compile("[-−－]([0-9])")
	value=plus.sub(value,"提高$1",true)
	value=minus.sub(value,"降低$1",true)
	return value.replace("提高提高","提高").replace("降低降低","降低").replace("+","、").replace("＋","、").replace("−","").replace("－","")
