extends RefCounted
## Shared imported textures with a source-workspace preview fallback.
static var textures: Dictionary={}
static func texture(asset: String) -> Texture2D:
	if not textures.has(asset):
		var path:="res://assets/vfx/painted_particles_v28/"+asset+".png"
		if FileAccess.file_exists(path+".import"):
			textures[asset]=load(path)
		else:
			var image:=Image.load_from_file(path)
			image.generate_mipmaps()
			textures[asset]=ImageTexture.create_from_image(image)
	return textures[asset]
