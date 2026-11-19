class_name FakeRtx
extends RefCounted
## Shared helpers: what colour a ray hit, and splitting a colour into hue and
## brightness for a light.

const NEUTRAL := Color(0.42, 0.42, 0.40)
static var _albedo_cache := {}


static func albedo_of(collider: Object) -> Color:
	## The average colour of whatever a ray hit, cached on the node. Set a
	## "fake_rtx_albedo" meta (Color) on a body to override it.
	if collider == null or not is_instance_valid(collider) or not (collider is Node):
		return NEUTRAL
	var node := collider as Node
	if node.has_meta("fake_rtx_albedo"):
		return node.get_meta("fake_rtx_albedo")
	var colour := material_albedo(_material_of(node))
	node.set_meta("fake_rtx_albedo", colour)
	return colour


static func _material_of(node: Node) -> Material:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			if mesh.material_override != null:
				return mesh.material_override
			if mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				return mesh.get_active_material(0)
	var parent := node.get_parent()
	if parent is MeshInstance3D:
		return (parent as MeshInstance3D).get_active_material(0)
	return null


static func material_albedo(material: Material) -> Color:
	if material == null:
		return NEUTRAL
	if _albedo_cache.has(material):
		return _albedo_cache[material]
	var colour := NEUTRAL
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		colour = base.albedo_color
		if base.albedo_texture != null:
			var average := texture_average(base.albedo_texture)
			colour = Color(colour.r * average.r, colour.g * average.g, colour.b * average.b)
	_albedo_cache[material] = colour
	return colour


static func texture_average(texture: Texture2D) -> Color:
	var image := texture.get_image()
	if image == null:
		return Color(0.5, 0.5, 0.5)
	if image.is_compressed() and image.decompress() != OK:
		return Color(0.5, 0.5, 0.5)
	image.convert(Image.FORMAT_RGBA8)
	while image.get_width() > 8 or image.get_height() > 8:
		image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	var total := Color(0.0, 0.0, 0.0)
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y)
	var count := float(image.get_width() * image.get_height())
	return Color(total.r / count, total.g / count, total.b / count)


static func split_colour(colour: Color) -> Array:
	## [hue at full brightness, brightness].
	var peak := maxf(maxf(colour.r, colour.g), maxf(colour.b, 0.0001))
	return [Color(colour.r / peak, colour.g / peak, colour.b / peak), peak]
