extends Node
signal changed(school: String)
signal appearance_status(message: String)
var appearance_busy:=false
var appearance_request_id:=""
var appearance_request_body:=""
var economic_cosmetics: Array=[]
var cosmetic_index: Dictionary={}
var compatible_cosmetics: Dictionary={}
var cosmetic_school_index: Dictionary={}
var hair_catalog: Dictionary
var dye_catalog: Dictionary
var teen_catalog: Dictionary
var teen_sets: Dictionary
var catalog: Dictionary
var outfits: Dictionary={}
var owned: Array[String]=[]
var save_enabled:=true
var save_path:="user://academy_wardrobe.json"
const TEEN_OUTFIT_ADDONS: Array[String]=[
	"res://resources/fusion_3d/teen_hidden_anime.json",
	"res://resources/fusion_3d/teen_starweave_v1.json",
	"res://resources/fusion_3d/teen_pink_sakura.json",
	"res://resources/fusion_3d/teen_sailor_uniform.json",
	"res://resources/fusion_3d/teen_hanbok.json",
]
func _ready() -> void:
	dye_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/teen_dye_catalog.json"))
	teen_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/teen_catalog.json"))
	for addon_path in TEEN_OUTFIT_ADDONS:
		var addon: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(addon_path))
		for slot in addon.get("options",{}):
			if not teen_catalog.options.has(slot):teen_catalog.options[slot]=[]
			for item in addon.options[slot]:
				var exists:=false
				for current in teen_catalog.options[slot]:
					if str(current.id)==str(item.id):exists=true;break
				if not exists:teen_catalog.options[slot].append(item)
	hair_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/teen_hair_dye_catalog.json"))
	# Separate addon survives regeneration of the imported source catalog.
	for addon_path in ["res://resources/fusion_3d/teen_hat_hair_catalog.json","res://resources/fusion_3d/teen_hat_hair_v2_catalog.json"]:
		var hat_hair: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(addon_path))
		hair_catalog.items.merge(hat_hair.items,true)
		for item in hat_hair.options:
			if option("teen_hair",str(item.id)).is_empty():teen_catalog.options.teen_hair.append(item)
	for item in teen_catalog.options.teen_hair:
		if hair_catalog.items.has(str(item.id)):item.name=hair_catalog.items[str(item.id)].name
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/wardrobe_catalog.json"))
	teen_sets=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/teen_sets.json"))
	for addon_path in TEEN_OUTFIT_ADDONS:
		var addon: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(addon_path))
		for set_spec in addon.get("sets",[]):
			var exists:=false
			for current in teen_sets.get("sets",[]):
				if str(current.id)==str(set_spec.id):exists=true;break
			if not exists:teen_sets.sets.append(set_spec)
	load_save()
	for preset in teen_sets.get("sets",[]):
		var school:=school_key(str(preset.get("school","any")))
		if school.is_empty():school="any"
		for slot in preset.get("pieces",{}):
			var key:=str(slot)+":"+str(preset.pieces[slot])
			if not cosmetic_school_index.has(key):cosmetic_school_index[key]=[]
			if not cosmetic_school_index[key].has(school):cosmetic_school_index[key].append(school)
	var equipment_path:="res://resources/fusion_3d/weekend_equipment.json"
	if FileAccess.file_exists(equipment_path):
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(equipment_path))
		if data is Dictionary:economic_cosmetics=data.get("cosmetics",[])
	for cosmetic in economic_cosmetics:cosmetic_index[str(cosmetic.id)]=cosmetic
	for path in TEEN_OUTFIT_ADDONS:
		if path.ends_with("teen_hidden_anime.json"):continue
		var addon: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		for slot in addon.get("options",{}):
			for item in addon.options[slot]:compatible_cosmetics[str(slot)+":"+str(item.id)]=true
	# Only the authored Sakura/Sailor sets' existing female boot underlayer.
	compatible_cosmetics["teen_boots:baselayer_female_boots"]=true
	var accounts=get_node_or_null("/root/Accounts")
	if accounts!=null and accounts.has_signal("progression_changed"):
		accounts.connect("progression_changed",_progression_changed)
func options_for(slot: String) -> Array:
	if teen_catalog.get("options",{}).has(slot):return teen_catalog.options[slot]
	if slot=="gender":return catalog.get("genders",[])
	if slot=="hairstyle":return catalog.get("hairstyles",[])
	return catalog.themes if catalog.slots.has(slot) else []
func school_key(value: String) -> String:
	return "storm" if value=="strom" else ("any" if value.is_empty() else value)
func option(slot: String,id: String) -> Dictionary:
	for entry in options_for(slot):
		if str(entry.id)==id:return entry
	return {}
func option_name(slot: String,id: String) -> String:
	return str(option(slot,id).get("name",id))
func appearance_path(slot: String,id: String) -> String:
	return str(option(slot,id).get("model",""))
func default_outfit(school: String) -> Dictionary:
	var theme:=school if valid_theme(school) else "fire"
	var result: Dictionary={}
	for slot in catalog.slots:
		result[slot]=str(catalog.default_appearance[theme][slot]) if slot in ["gender","hairstyle"] else theme
	result.model_style="teen"
	result.merge(school_defaults(school,str(result.gender)),true)
	result.teen_dyes={}
	result.teen_hair_color=""
	return result
func valid_theme(id: String) -> bool:
	for theme in catalog.themes:
		if theme.id==id:return true
	return false
func outfit(school: String) -> Dictionary:
	var snap:=progression()
	var value: Dictionary=snap.get("appearance",{}) if school==str(snap.get("school","")) else {}
	if value.is_empty():value=default_outfit(school)
	var base:=default_outfit(school)
	base.merge(value,true)
	return filter_entitlements(school,sanitize_restricted(base,can_use_hidden_character()))
func can_use_hidden_character() -> bool:
	var accounts=get_node_or_null("/root/Accounts")
	return accounts!=null and not str(accounts.token).is_empty() and str(accounts.account.get("username","")).to_lower()=="admin"
func can_use_item(item: Dictionary) -> bool:
	return str(item.get("restricted_account",""))!="admin" or can_use_hidden_character()
func sanitize_restricted(value: Dictionary,allowed: bool=false) -> Dictionary:
	var result=value.duplicate(true)
	if not allowed and str(result.get("teen_clothes",""))=="hidden_anime_catgirl":
		var sex=str(result.get("gender","female"))
		if sex not in ["male","female"]:sex="female"
		result.teen_clothes=teen_catalog.defaults[sex].teen_clothes
		result.teen_body_shape=teen_catalog.defaults[sex].teen_body_shape
	return result
func equip(school: String,slot: String,value: String) -> bool:
	if not valid_theme(school) or not catalog.slots.has(slot) or not cosmetic_allowed(school,slot,value):return false
	var result:=outfit(school)
	result[slot]=value
	if slot!="aura":result.model_style="modular"
	return submit_appearance(school,result)
func equip_set(school: String,theme: String) -> void:
	if not valid_theme(school) or not valid_theme(theme):return
	var previous:=outfit(school)
	var result:=previous.duplicate(true)
	# Outfit presets change equipment and colors, preserving personal appearance.
	result.model_style="modular"
	for slot in ["hat","robe","boots","staff","aura"]:result[slot]=theme
	submit_appearance(school,result)
func set_model_style(school: String, style: String) -> void:
	if not valid_theme(school) or style not in ["custom","modular","teen"]:return
	if style=="custom" and not catalog.get("custom_models",{}).has(school):return
	var result:=outfit(school)
	result.model_style=style
	submit_appearance(school,result)
func model_path(theme: String) -> String:
	for entry in catalog.themes:
		if entry.id==theme:return str(entry.model)
	return str(catalog.themes[0].model)
func theme_name(theme: String) -> String:
	return option_name("body",theme)
func save() -> void:
	if not save_enabled:return
	var accounts := get_node_or_null("/root/Accounts")
	if accounts != null and save_path==accounts.path_for("academy_wardrobe.json"):
		accounts.write_save("academy_wardrobe.json",{"version":4,"outfits":outfits})
		return
	var file:=FileAccess.open(save_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"version":4,"outfits":outfits},"  "))
func load_save() -> void:
	outfits.clear()
	if not FileAccess.file_exists(save_path):return
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or not data.get("outfits") is Dictionary:return
	for school in data.outfits:
		if not valid_theme(str(school)) or not data.outfits[school] is Dictionary:continue
		# V1 six-slot saves receive default appearance without losing equipped items.
		var clean:=default_outfit(str(school))
		for slot in clean:
			if slot in ["teen_dyes","teen_hair_color"]:continue
			var value:=str(data.outfits[school].get(slot,clean[slot]))
			if owned.has(slot+":"+value) or (slot.begins_with("teen_") and not option(slot,value).is_empty()):clean[slot]=value
		clean.teen_dyes=clean_dyes(data.outfits[school].get("teen_dyes",{}))
		clean.teen_hair_color=clean_hair_color(data.outfits[school].get("teen_hair_color",""))
		clean.teen_clothing_fit_revision=int(data.outfits[school].get("teen_clothing_fit_revision",0))
		clean.teen_equipment_fit_revision=int(data.outfits[school].get("teen_equipment_fit_revision",0))
		clean.teen_special_fit_revision=int(data.outfits[school].get("teen_special_fit_revision",0))
		clean.teen_costume_fit_revision=int(data.outfits[school].get("teen_costume_fit_revision",0))
		clean.teen_recovered_fit_revision=int(data.outfits[school].get("teen_recovered_fit_revision",0))
		clean.teen_alpha_fit_revision=int(data.outfits[school].get("teen_alpha_fit_revision",0))
		clean.teen_high_school_fit_revision=int(data.outfits[school].get("teen_high_school_fit_revision",0))
		clean.teen_requested_fit_revision=int(data.outfits[school].get("teen_requested_fit_revision",0))
		clean.teen_boot_review_fit_revision=int(data.outfits[school].get("teen_boot_review_fit_revision",0))
		clean.teen_attachment_fit_revision=int(data.outfits[school].get("teen_attachment_fit_revision",0))
		clean.teen_level40_fit_revision=int(data.outfits[school].get("teen_level40_fit_revision",0))
		var style:=str(data.outfits[school].get("model_style",clean.model_style))
		if style in ["teen","modular"] or (style=="custom" and catalog.get("custom_models",{}).has(school)):clean.model_style=style
		if clean.model_style=="teen" and not data.outfits[school].has("teen_hair"):
			var created:=creation_outfit(str(school),str(clean.gender),str(clean.hairstyle))
			for slot in teen_catalog.slots:clean[slot]=created[slot]
		outfits[school]=clean_teen(clean) if clean.model_style=="teen" else clean

func clean_teen(value: Dictionary) -> Dictionary:
	var result:=value.duplicate(true)
	var sex:=str(result.get("gender","male"))
	if sex not in ["male","female"]:sex="male"
	result.gender=sex
	result.teen_dyes=clean_dyes(result.get("teen_dyes",{}))
	result.teen_hair_color=clean_hair_color(result.get("teen_hair_color",""))
	for slot in teen_catalog.slots:
		var selected:=option(slot,str(result.get(slot,"")))
		if selected.is_empty() or str(selected.get("gender","both")) not in [sex,"both"]:result[slot]=str(teen_catalog.defaults[sex][slot])
	# Upgrade only the former automatic fit once; keep other custom silhouettes.
	if int(result.get("teen_clothing_fit_revision",0))<1:
		var clothes:=option("teen_clothes",str(result.teen_clothes))
		if clothes.has("legacy_shape") and str(result.teen_body_shape)==sex+"_"+str(int(clothes.legacy_shape)):
			result.teen_body_shape=sex+"_"+str(int(clothes.shape))
		result.teen_clothing_fit_revision=1
	if int(result.get("teen_equipment_fit_revision",0))<1:
		for slot in ["teen_boots","teen_back"]:
			var item:=option(slot,str(result[slot]))
			var shape_slot: String="teen_boot_shape" if slot=="teen_boots" else "teen_back_shape"
			if item.has("previous_equipment_shape"):
				var old_shape:=sex+"_"+str(int(item.previous_equipment_shape))
				if str(value.get(shape_slot,""))==old_shape or (option(shape_slot,old_shape).is_empty() and str(result[shape_slot])==str(teen_catalog.defaults[sex][shape_slot])):
					result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_equipment_fit_revision=1
	if int(result.get("teen_special_fit_revision",0))<1:
		for slot in ["teen_clothes","teen_boots"]:
			var item:=option(slot,str(result[slot]))
			var shape_slot: String="teen_body_shape" if slot=="teen_clothes" else "teen_boot_shape"
			if item.has("previous_special_shape") and str(result[shape_slot])==sex+"_"+str(int(item.previous_special_shape)):
				result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_special_fit_revision=1
	if int(result.get("teen_costume_fit_revision",0))<1:
		for slot in ["teen_clothes","teen_boots","teen_back"]:
			var item:=option(slot,str(result[slot]))
			var shape_slot: String={"teen_clothes":"teen_body_shape","teen_boots":"teen_boot_shape","teen_back":"teen_back_shape"}[slot]
			if item.has("previous_costume_shape") and str(result[shape_slot])==sex+"_"+str(int(item.previous_costume_shape)):
				result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_costume_fit_revision=1
	if int(result.get("teen_recovered_fit_revision",0))<1:
		for slot in ["teen_clothes","teen_back"]:
			var item:=option(slot,str(result[slot]))
			var shape_slot: String="teen_body_shape" if slot=="teen_clothes" else "teen_back_shape"
			if item.has("previous_recovered_shape") and str(result[shape_slot])==sex+"_"+str(int(item.previous_recovered_shape)):
				result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_recovered_fit_revision=1
	if int(result.get("teen_alpha_fit_revision",0))<1:
		for slot in ["teen_clothes","teen_boots"]:
			var item:=option(slot,str(result[slot]))
			var shape_slot: String="teen_body_shape" if slot=="teen_clothes" else "teen_boot_shape"
			if item.has("previous_alpha_shape") and str(result[shape_slot])==sex+"_"+str(int(item.previous_alpha_shape)):
				result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_alpha_fit_revision=1
	if int(result.get("teen_high_school_fit_revision",0))<1:
		for slot in ["teen_clothes","teen_boots"]:
			var item:=option(slot,str(result[slot]))
			var shape_slot: String="teen_body_shape" if slot=="teen_clothes" else "teen_boot_shape"
			if item.has("previous_high_school_shape") and str(result[shape_slot])==sex+"_"+str(int(item.previous_high_school_shape)):
				result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_high_school_fit_revision=1
	if int(result.get("teen_requested_fit_revision",0))<1:
		for slot in ["teen_clothes","teen_boots"]:
			var item:=option(slot,str(result[slot]))
			var shape_slot: String="teen_body_shape" if slot=="teen_clothes" else "teen_boot_shape"
			if item.has("previous_requested_shape") and str(result[shape_slot])==sex+"_"+str(int(item.previous_requested_shape)):
				result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_requested_fit_revision=1
	if int(result.get("teen_boot_review_fit_revision",0))<1:
		var item:=option("teen_boots",str(result.teen_boots))
		if item.has("previous_boot_review_shape") and str(result.teen_boot_shape)==sex+"_"+str(int(item.previous_boot_review_shape)):
			result.teen_boot_shape=sex+"_"+str(int(item.shape))
		result.teen_boot_review_fit_revision=1
	if int(result.get("teen_attachment_fit_revision",0))<1:
		var item:=option("teen_back",str(result.teen_back))
		if int(item.get("attachment_fit_revision",0))==1:
			result.teen_back_shape=sex+"_"+str(int(item.shape))
		result.teen_attachment_fit_revision=1
	if int(result.get("teen_level40_fit_revision",0))<1:
		for slot in ["teen_clothes","teen_boots"]:
			var item:=option(slot,str(result[slot]))
			if int(item.get("level40_fit_revision",0))!=1:continue
			var shape_slot: String="teen_body_shape" if slot=="teen_clothes" else "teen_boot_shape"
			var legacy: Array=[801,802,803] if slot=="teen_clothes" else [501,502,506]
			if int(str(result[shape_slot]).get_slice("_",1)) in legacy:result[shape_slot]=sex+"_"+str(int(item.shape))
		result.teen_level40_fit_revision=1
	# Revision 2 repairs only the previous default boots; clothing/manual choices stay intact.
	if int(result.get("teen_level40_fit_revision",0))<2:
		var item:=option("teen_boots",str(result.teen_boots))
		if int(item.get("level40_boot_uv_revision",0))==2 and str(result.teen_boot_shape)==sex+"_502":
			result.teen_boot_shape=sex+"_"+str(int(item.shape))
		result.teen_level40_fit_revision=2
	return result
func equip_teen(school: String,slot: String,value: String) -> bool:
	if not valid_theme(school):return false
	if not can_use_item(option(slot,value)) or not cosmetic_allowed(school,slot,value):return false
	if slot=="gender":
		if value not in ["male","female"]:return false
	elif not teen_catalog.slots.has(slot) or option(slot,value).is_empty():return false
	var result:=outfit(school)
	var previous_dye_shape:=int(dye_spec(result).get("shape",-1))
	result[slot]=value
	result.model_style="teen"
	result=clean_teen(result)
	if slot=="gender" and previous_dye_shape>=0:
		var counterpart:="atelier_"+value+"_"+str(previous_dye_shape)
		if dye_catalog.items.has(counterpart):
			result.teen_clothes=counterpart
			result.teen_body_shape=value+"_"+str(previous_dye_shape)
	if slot in ["teen_clothes","teen_boots","teen_back"]:
		var item:=option(slot,value)
		var shape_slot: String={"teen_clothes":"teen_body_shape","teen_boots":"teen_boot_shape","teen_back":"teen_back_shape"}[slot]
		var shape_id:=str(result.gender)+"_"+str(int(item.get("shape",0)))
		if not option(shape_slot,shape_id).is_empty():result[shape_slot]=shape_id
	return submit_appearance(school,result)

func teen_set(id: String) -> Dictionary:
	for item in teen_sets.get("sets",[]):
		if str(item.id)==id:return item
	return {}
func set_outfit(value: Dictionary,set_id: String) -> Dictionary:
	var preset:=teen_set(set_id)
	if not can_use_item(preset):return {}
	if not set_allowed(str(progression().get("school","")),preset):return {}
	if preset.is_empty() or str(value.gender)!=str(preset.gender):return {}
	var result:=clean_teen(value)
	# Keep the selected face, hair, skin, school and per-item dye choices.
	for slot in ["teen_clothes","teen_boots","teen_hat","teen_back","teen_weapon"]:
		if not preset.pieces.has(slot):return {}
		var item:=option(slot,str(preset.pieces[slot]))
		if item.is_empty() or str(item.get("gender","both")) not in [str(result.gender),"both"]:return {}
		result[slot]=str(item.id)
		var shape_slot: String={"teen_clothes":"teen_body_shape","teen_boots":"teen_boot_shape","teen_back":"teen_back_shape"}.get(slot,"")
		if not shape_slot.is_empty() and item.has("shape"):result[shape_slot]=str(result.gender)+"_"+str(int(item.shape))
	result.model_style="teen"
	return clean_teen(result)
func equip_teen_set(school: String,set_id: String) -> bool:
	if not valid_theme(school):return false
	var result:=set_outfit(outfit(school),set_id)
	if result.is_empty():return false
	return submit_appearance(school,result)

func creation_options(slot: String,sex: String) -> Array:
	var result: Array=[]
	for item in options_for(slot):
		if str(item.get("gender",""))!=sex:continue
		if slot=="teen_skin" and not str(item.get("id","")).begins_with("smooth_face_"):continue
		if slot=="teen_hair" and not hair_catalog.items.has(str(item.id)):continue
		result.append(item)
	return result

func creation_outfit(school: String,sex: String,hair: String,face_id: String="") -> Dictionary:
	var result:=default_outfit(school)
	result.gender=sex
	result.hairstyle=("f" if sex=="female" else "m")+str(clampi(int(hair.substr(1)),1,3))
	result.merge(school_defaults(school,sex),true)
	var choices:=creation_options("teen_hair",sex)
	var number:=clampi(int(hair.substr(1)),1,3)
	if not choices.is_empty():result.teen_hair=str(choices[mini(number-1,choices.size()-1)].id)
	for item in choices:
		if str(item.id)==hair:result.teen_hair=hair;break
	result.teen_skin="smooth_face_"+sex+"_a"
	for item in creation_options("teen_skin",sex):
		if str(item.id)==face_id:result.teen_skin=face_id;break
	for slot in ["teen_clothes","teen_boots"]:
		for item in options_for(slot):
			var source:=str(item.get("source","")).to_lower()
			if str(item.gender)==sex and source.contains(school) and source.contains("lv1_"):
				result[slot]=str(item.id)
				break
	return result

# Dye values are a separate, bounded field; unknown item IDs and malformed colors
# never reach either saved appearances or the multiplayer renderer.
func clean_dyes(value: Variant) -> Dictionary:
	var clean: Dictionary={}
	if not value is Dictionary:return clean
	for id in dye_catalog.get("items",{}):
		var colors: Variant=value.get(id,[])
		if not colors is Array or colors.size()!=4:continue
		var checked: Array=[]
		for color in colors:
			if not color is String or color.length()!=7 or not color.begins_with("#") or not Color.html_is_valid(color):break
			checked.append("#"+Color.html(color).to_html(false))
		if checked.size()==4:clean[id]=checked
	return clean
func dye_spec(value: Dictionary) -> Dictionary:
	var item: Dictionary=dye_catalog.get("items",{}).get(str(value.get("teen_clothes","")),{})
	if item.is_empty():return {}
	if str(value.get("gender",""))!=str(item.gender):return {}
	if str(value.get("teen_body_shape",""))!=str(item.gender)+"_"+str(int(item.shape)):return {}
	return item
func dye_colors(value: Dictionary) -> Array:
	var spec:=dye_spec(value)
	if spec.is_empty():return []
	return clean_dyes(value.get("teen_dyes",{})).get(str(value.teen_clothes),spec.defaults).duplicate()
func set_teen_dye(school: String,zone: int,color: Color) -> bool:
	if not valid_theme(school) or zone<0 or zone>3:return false
	var value:=outfit(school)
	var colors:=dye_colors(value)
	if colors.size()!=4:return false
	colors[zone]="#"+color.to_html(false)
	value.teen_dyes=clean_dyes(value.get("teen_dyes",{}))
	value.teen_dyes[str(value.teen_clothes)]=colors
	return submit_appearance(school,value)
func set_teen_dye_preset(school: String,preset: String) -> bool:
	if not valid_theme(school):return false
	var value:=outfit(school)
	if dye_spec(value).is_empty():return false
	if preset!="default" and not dye_catalog.presets.has(preset):return false
	value.teen_dyes=clean_dyes(value.get("teen_dyes",{}))
	if preset=="default":value.teen_dyes.erase(str(value.teen_clothes))
	else:value.teen_dyes[str(value.teen_clothes)]=dye_catalog.presets[preset].duplicate()
	return submit_appearance(school,value)

# Hair color is a bounded RGB string, independent of hairstyle and clothing dyes.
func clean_hair_color(value: Variant) -> String:
	if not value is String:return ""
	if value.length()!=7 or not value.begins_with("#") or not Color.html_is_valid(value):return ""
	return value.to_lower()
func hair_spec(value: Dictionary) -> Dictionary:
	var spec: Dictionary=hair_catalog.get("items",{}).get(str(value.get("teen_hair","")),{})
	if spec.is_empty() or spec.gender!=str(value.get("gender","male")):return {}
	return spec
func hair_color(value: Dictionary) -> String:
	var custom:=clean_hair_color(value.get("teen_hair_color",""))
	return custom if not custom.is_empty() else str(hair_spec(value).get("default","#e8bb65"))
func set_teen_hair_color(school: String,color: Color) -> bool:
	if not valid_theme(school):return false
	var value:=outfit(school)
	if hair_spec(value).is_empty():return false
	value.teen_hair_color="#"+color.to_html(false)
	return submit_appearance(school,value)
func reset_teen_hair_color(school: String) -> bool:
	if not valid_theme(school):return false
	var value:=outfit(school)
	if hair_spec(value).is_empty():return false
	value.teen_hair_color=""
	return submit_appearance(school,value)

# Accounts owns all economic state; these helpers only read its snapshot.
func progression() -> Dictionary:
	var accounts=get_node_or_null("/root/Accounts")
	if accounts==null:return {}
	for property in accounts.get_property_list():
		if str(property.name)=="progression_snapshot":
			var value: Variant=accounts.get("progression_snapshot")
			if value is Dictionary:return value
	return {}

func _progression_changed(snapshot: Dictionary) -> void:
	changed.emit(str(snapshot.get("school","")))

func cosmetic_allowed(school: String,slot: String,id: String,sex: String="") -> bool:
	var snap:=progression()
	if school!=str(snap.get("school","")):return false
	if sex.is_empty():sex=str(snap.get("appearance",{}).get("gender","male"))
	var entry:=option(slot,id)
	if str(entry.get("gender","both")) not in ["both",sex]:return false
	if slot in ["gender","hairstyle","teen_hair","teen_skin","body","teen_body_shape","teen_boot_shape","teen_back_shape"]:return not entry.is_empty() and can_use_item(entry)
	if not can_use_item(entry):return false
	var restriction:=school_key(str(entry.get("school","any")))
	if restriction not in ["","any",school]:return false
	var economic:=false
	for cosmetic in economic_cosmetics:
		for appearance in cosmetic.get("appearance_by_gender",{}).values():
			if str(appearance.get(slot,""))!=id:continue
			economic=true
			if str(cosmetic.get("appearance_by_gender",{}).get(sex,{}).get(slot,""))==id and str(cosmetic.get("school","any")) in ["any",school] and cosmetic_id_owned(str(cosmetic.id)):return true
	if economic:return false
	if compatible_cosmetics.has(slot+":"+id):return true
	# A local legacy save never grants economic rights.
	if str(teen_catalog.get("defaults",{}).get(sex,{}).get(slot,""))==id:return true
	if id=="none" and not entry.is_empty():return true
	if catalog.slots.has(slot) and id==school:return true
	return false

func cosmetic_visible(school: String,slot: String,id: String) -> bool:
	var economic:=false
	for cosmetic in economic_cosmetics:
		for appearance in cosmetic.get("appearance_by_gender",{}).values():
			if str(appearance.get(slot,""))!=id:continue
			economic=true
			if str(cosmetic.get("school","any")) in ["any",school]:return true
	var schools: Array=cosmetic_school_index.get(slot+":"+id,["any"])
	return not economic and (schools.has("any") or schools.has(school)) and school_key(str(option(slot,id).get("school","any"))) in ["any",school]

func cosmetic_source(school: String,slot: String,id: String) -> String:
	for cosmetic in economic_cosmetics:
		if str(cosmetic.get("school","any")) not in ["any",school]:continue
		for appearance in cosmetic.get("appearance_by_gender",{}).values():
			if str(appearance.get(slot,""))==id:return "外观商店 · "+str(cosmetic.get("tier","")).to_upper()+" · 账号永久收藏"
	if compatible_cosmetics.has(slot+":"+id):return "用户制作外观 · 基础兼容收藏"
	if cosmetic_allowed(school,slot,id):return "基础形象"
	return "尚未解锁 · 暂无获取途径"

func set_allowed(school: String,item: Dictionary) -> bool:
	if not can_use_item(item) or school_key(str(item.get("school","any"))) not in ["any",school]:return false
	for slot in item.get("pieces",{}):
		if not cosmetic_allowed(school,str(slot),str(item.pieces[slot])):return false
	return not item.get("pieces",{}).is_empty()

func filter_entitlements(school: String,value: Dictionary) -> Dictionary:
	var result:=value.duplicate(true)
	var defaults:=default_outfit(school)
	var sex:=str(result.get("gender","male"))
	if sex in ["male","female"]:defaults.merge(school_defaults(school,sex),true)
	for slot in catalog.slots:
		if result.has(slot) and not cosmetic_allowed(school,str(slot),str(result[slot]),sex):result[slot]=defaults[slot]
	for slot in teen_catalog.slots:
		if result.has(slot) and not cosmetic_allowed(school,str(slot),str(result[slot]),sex):
			result[slot]=defaults.get(slot,result[slot])
			var shape_slot: String={"teen_clothes":"teen_body_shape","teen_boots":"teen_boot_shape","teen_back":"teen_back_shape"}.get(slot,"")
			if not shape_slot.is_empty():result[shape_slot]=defaults.get(shape_slot,result.get(shape_slot,""))
	return result

func school_defaults(school: String,sex: String) -> Dictionary:
	var value: Dictionary=teen_catalog.get("defaults",{}).get(sex,{}).duplicate(true)
	for cosmetic in economic_cosmetics:
		if str(cosmetic.get("school",""))==school and str(cosmetic.get("tier",""))=="t0":
			value.merge(cosmetic.get("appearance_by_gender",{}).get(sex,{}),true)
	for slot in ["teen_clothes","teen_boots","teen_back"]:
		var spec:=option(slot,str(value.get(slot,"")))
		var shape_slot: String={"teen_clothes":"teen_body_shape","teen_boots":"teen_boot_shape","teen_back":"teen_back_shape"}[slot]
		if spec.has("shape"):value[shape_slot]=sex+"_"+str(int(spec.shape))
	return value

func preview_equipment_cosmetic(slot: String,tier: String) -> Dictionary:
	var snap:=progression();var school:=str(snap.get("school",""))
	var value:=outfit(school);var sex:=str(value.get("gender","male"))
	for cosmetic in economic_cosmetics:
		if str(cosmetic.school)!=school or str(cosmetic.slot)!=slot or str(cosmetic.get("tier",""))!=tier:continue
		for part in cosmetic.get("appearance_by_gender",{}).get(sex,{}):
			value[part]=str(cosmetic.appearance_by_gender[sex][part])
			var spec:=option(str(part),str(value[part]))
			var shape_slot: String={"teen_clothes":"teen_body_shape","teen_boots":"teen_boot_shape","teen_back":"teen_back_shape"}.get(part,"")
			if not shape_slot.is_empty() and spec.has("shape"):value[shape_slot]=sex+"_"+str(int(spec.shape))
		value.model_style="teen"
		return clean_teen(value)
	return {}

func cosmetic_by_id(id: String) -> Dictionary:
	return cosmetic_index.get(id,{})

func cosmetic_id_owned(id: String) -> bool:
	var spec:=cosmetic_by_id(id)
	if spec.is_empty():return false
	if bool(spec.get("always_unlocked",false)) or str(spec.get("tier",""))=="t0":return true
	var unlocked: Array=progression().get("cosmetic_unlocks",[])
	if unlocked.has(id):return true
	for alias in spec.get("unlock_aliases",[]):
		if unlocked.has(str(alias)):return true
	return false

func preview_cosmetic_id(id: String) -> Dictionary:
	var spec:=cosmetic_by_id(id);var snap:=progression()
	var school:=str(snap.get("school",""));var value:=outfit(school)
	var sex:=str(value.get("gender","male"))
	if spec.is_empty() or str(spec.get("school","any")) not in ["any",school]:return {}
	var mapping: Dictionary=spec.get("appearance_by_gender",{}).get(sex,{})
	if mapping.is_empty():return {}
	for part in mapping:
		var item:=option(str(part),str(mapping[part]))
		if item.is_empty() or not can_use_item(item):return {}
		value[part]=mapping[part]
		var shape_slot: String={"teen_clothes":"teen_body_shape","teen_boots":"teen_boot_shape","teen_back":"teen_back_shape"}.get(part,"")
		if not shape_slot.is_empty() and item.has("shape"):value[shape_slot]=sex+"_"+str(int(item.shape))
	value.model_style="teen"
	return clean_teen(value)

func cosmetic_texture(id: String) -> Texture2D:
	var sex:=str(progression().get("appearance",{}).get("gender","male"))
	var mapping: Dictionary=cosmetic_by_id(id).get("appearance_by_gender",{}).get(sex,{})
	for slot in mapping:
		var path:="res://assets/ui/wardrobe/thumbs/"+str(slot)+"_"+sex+"_"+str(mapping[slot])+".png"
		if ResourceLoader.exists(path):return load(path)
	return null

func equipment_display(item: Dictionary) -> Dictionary:
	var sex:=str(progression().get("appearance",{}).get("gender","male"))
	for cosmetic in economic_cosmetics:
		if str(cosmetic.school)!=str(item.get("school","")) or str(cosmetic.slot)!=str(item.get("slot","")) or str(cosmetic.get("tier",""))!=str(item.get("tier","")):continue
		var mapping: Dictionary=cosmetic.get("appearance_by_gender",{}).get(sex,{})
		for slot in mapping:return {"title":option_name(str(slot),str(mapping[slot])),"thumbnail":"res://assets/ui/wardrobe/thumbs/"+str(slot)+"_"+sex+"_"+str(mapping[slot])+".png"}
	return {"title":str(item.get("slot","装备"))+" "+str(item.get("tier","")),"thumbnail":""}

func equipment_texture(item: Dictionary) -> Texture2D:
	var path:=str(equipment_display(item).get("thumbnail",""))
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null

func submit_appearance(school: String,value: Dictionary) -> bool:
	var accounts=get_node_or_null("/root/Accounts")
	if appearance_busy:return false
	value=value.duplicate(true)
	# Godot JSON reads all numbers as floats; revisions must retain integer wire types.
	for key in value:
		if str(key).ends_with("_fit_revision"):value[key]=int(value[key])
	if accounts==null or not accounts.has_method("save_appearance") or school!=str(progression().get("school","")):
		appearance_status.emit("外观服务尚未就绪，请刷新账号权益。")
		return false
	if filter_entitlements(school,value)!=value:
		appearance_status.emit("包含未解锁或不属于当前学院的外观。")
		return false
	var body:=JSON.stringify(value)
	if body!=appearance_request_body or appearance_request_id.is_empty():
		appearance_request_body=body
		appearance_request_id="appearance-"+str(Time.get_unix_time_from_system())+"-"+str(Time.get_ticks_usec())
	appearance_busy=true
	appearance_status.emit("正在保存外观…")
	_finish_appearance(accounts,value,appearance_request_id)
	return true

func _finish_appearance(accounts: Node,value: Dictionary,request_id: String) -> void:
	var result: Dictionary=await accounts.call("save_appearance",value,request_id)
	appearance_busy=false
	if bool(result.get("ok",false)):
		appearance_request_id="";appearance_request_body=""
		appearance_status.emit("外观已保存；属性装备保持不变。")
		changed.emit(str(progression().get("school","")))
	else:appearance_status.emit("保存失败："+str(result.get("code","unknown"))+"；未应用本地改动。")
