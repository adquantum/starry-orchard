extends RefCounted
const ModernSkin=preload("res://scripts/fusion_3d/modern_inventory_skin.gd")
const INK=ModernSkin.INK
static func panel(tint: Color=Color.WHITE,vertical_padding: float=12.0) -> StyleBoxFlat:
	return ModernSkin.panel(Color("24445d") if tint!=Color.WHITE else Color("142336"),ModernSkin.ACCENT if tint!=Color.WHITE else Color("30465e"),vertical_padding)
static func apply_button(button: Button) -> void:
	ModernSkin.button(button)
