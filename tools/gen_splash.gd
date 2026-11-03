extends SceneTree
# Renders the boot splash (icons/splash.png) from the same drawing as the loading screen.
# Needs a display: xvfb-run godot --path . --rendering-method gl_compatibility --resolution 1080x1080 --script tools/gen_splash.gd
const Art = preload("res://scripts/menu_art.gd")

func _initialize() -> void:
	var sp := Art.Splash.new()
	sp.font = load("res://fonts/Bungee-Regular.ttf")
	sp.animate = false
	sp.flat = true
	sp.t = 0.55
	sp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sp)
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://icons/splash.png")
	print("saved ", img.get_size())
	quit()
