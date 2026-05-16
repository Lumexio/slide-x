extends TextureRect

export(float) var line_alpha := 0.08
export(int) var line_height := 1
export(int) var gap_height := 1

func _ready() -> void:
	var total_height: int = max(1, line_height + gap_height)
	var img := Image.new()
	img.create(2, total_height, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in range(total_height):
		var a := line_alpha if y < line_height else 0.0
		var c := Color(1, 1, 1, a)
		img.set_pixel(0, y, c)
		img.set_pixel(1, y, c)
	img.unlock()

	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_REPEAT)
	texture = tex
	stretch_mode = STRETCH_TILE
	expand = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
