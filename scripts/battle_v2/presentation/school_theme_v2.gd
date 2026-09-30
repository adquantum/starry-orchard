class_name SchoolThemeV2
extends RefCounted

const THEMES := {
	"fire": {"primary":Color("#d9442f"), "secondary":Color("#671e29"), "accent":Color("#ffd45b"), "rune":"flame", "glow":"ember", "particle":"spark"},
	"ice": {"primary":Color("#58b7df"), "secondary":Color("#1e5378"), "accent":Color("#d8f5ff"), "rune":"crystal", "glow":"frost", "particle":"shard"},
	"storm": {"primary":Color("#8c5ad9"), "secondary":Color("#38275f"), "accent":Color("#f0d7ff"), "rune":"spiral", "glow":"arc", "particle":"spark"},
	"myth": {"primary":Color("#d2a93f"), "secondary":Color("#665025"), "accent":Color("#fff0a6"), "rune":"eye", "glow":"sun", "particle":"dust"},
	"life": {"primary":Color("#4fb565"), "secondary":Color("#214e38"), "accent":Color("#d9ff9e"), "rune":"leaf", "glow":"bloom", "particle":"mote"},
	"death": {"primary":Color("#76628f"), "secondary":Color("#30263e"), "accent":Color("#d9b8ef"), "rune":"skull", "glow":"wisp", "particle":"ash"},
	"balance": {"primary":Color("#c88745"), "secondary":Color("#5c3c2d"), "accent":Color("#ffe2a3"), "rune":"scale", "glow":"sand", "particle":"dust"},
}


static func get_theme(school_id: StringName) -> Dictionary:
	return (THEMES.get(str(school_id), THEMES.fire) as Dictionary).duplicate()
