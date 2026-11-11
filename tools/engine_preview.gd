extends SceneTree
# Renders a short drive of every vehicle's engine (scripts/engines.gd) to WAV files, the
# way the game plays it: the loop re-pitched with speed (idle, launch, bends, full swing).
#   ENGINE_OUT=/tmp/engines godot --headless --path . --script tools/engine_preview.gd
# ENGINE_IDS: comma list of vehicles (default: all). Convert with ffmpeg for sharing.
const Engines = preload("res://scripts/engines.gd")
const WorldView = preload("res://scripts/world_view.gd")

# [seconds, speed at the end]: idle, launch, two bends (speed dips on the swing), full swing
const DRIVE := [[0.8, 0.0], [2.0, 900.0], [0.7, 760.0], [0.8, 1050.0], [0.6, 820.0], [1.2, 1100.0], [1.0, 0.0]]

func _initialize() -> void:
	var out := OS.get_environment("ENGINE_OUT")
	if out == "": out = "/tmp/engines"
	DirAccess.make_dir_recursive_absolute(out)
	var ids: Array = WorldView.BODIES
	if OS.get_environment("ENGINE_IDS") != "":
		ids = OS.get_environment("ENGINE_IDS").split(",")
	for id in ids:
		var t0 := Time.get_ticks_msec()
		var p := Engines.profile(id)
		var loop := Engines.render(p)
		var ms := Time.get_ticks_msec() - t0
		var buf := drive(p, loop)
		var w := Engines.to_wav(buf)
		w.loop_mode = AudioStreamWAV.LOOP_DISABLED
		w.save_to_wav(out.path_join(id + ".wav"))
		print("%s: loop rendered in %d ms" % [id, ms])
	quit()

# plays the loop like Sfx does: firing rate follows speed (smoothed), pitch = rate / base
static func drive(p: Dictionary, loop: PackedFloat32Array) -> PackedFloat32Array:
	var rate := Engines.RATE
	var out := PackedFloat32Array()
	var pos := 0.0
	var speed := 0.0
	var f := Engines.freq(p, 0.0)
	var g := 0.0
	for seg in DRIVE:
		var n := int(float(seg[0]) * rate)
		var s0 := speed
		for i in n:
			speed = lerpf(s0, float(seg[1]), float(i) / n)
			f += (Engines.freq(p, speed) - f) * minf(1.0, 1.0 / (0.05 * rate))
			g += (1.0 - g) * minf(1.0, 1.0 / (0.1 * rate))
			var pitch := clampf(f / float(p["base"]), 0.4, 3.0)
			var a := int(pos)
			var fr := pos - a
			var v := lerpf(loop[a % loop.size()], loop[(a + 1) % loop.size()], fr)
			out.append(v * g * 0.8 * float(p["gain"]))
			pos = fmod(pos + pitch, loop.size())
	return out
