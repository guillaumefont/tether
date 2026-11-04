extends SceneTree
# Builds web/shell.html (the browser loading page) from web/shell_template.html: inlines the
# loading artwork and a transparent logo rendered from the game's own drawing. Needs a display:
#   xvfb-run godot --path . --rendering-method gl_compatibility --resolution 900x900 --script tools/gen_web_shell.gd
const Art = preload("res://scripts/menu_art.gd")

func _initialize() -> void:
	root.transparent_bg = true
	var sp := Art.Splash.new()
	sp.font = load("res://fonts/Bungee-Regular.ttf")
	sp.animate = false
	sp.flat = true
	sp.clear_bg = true
	sp.t = 0.55
	sp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sp)
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var logo := root.get_texture().get_image()
	logo.convert(Image.FORMAT_RGBA8)
	# keep the emblem and wordmark only (the square has empty margins)
	var used := logo.get_used_rect()
	logo = logo.get_region(used.grow(8).intersection(Rect2i(Vector2i.ZERO, logo.get_size())))
	logo.resize(logo.get_width() * 560 / logo.get_width(), logo.get_height() * 560 / logo.get_width(), Image.INTERPOLATE_LANCZOS)
	var art := Image.load_from_file("res://art/loading_snow_land.jpg")
	art.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	var html := FileAccess.get_file_as_string("res://web/shell_template.html")
	html = html.replace("__ART__", Marshalls.raw_to_base64(art.save_jpg_to_buffer(0.72)))
	html = html.replace("__LOGO__", Marshalls.raw_to_base64(logo.save_png_to_buffer()))
	var f := FileAccess.open("res://web/shell.html", FileAccess.WRITE)
	f.store_string(html)
	f.close()
	print("saved web/shell.html ", html.length(), " chars, logo ", logo.get_size())
	quit()
