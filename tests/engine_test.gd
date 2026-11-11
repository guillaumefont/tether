extends SceneTree
# Every vehicle has its own engine sound, and each loop is sound: whole firings (so it
# loops without a click), no silence or clipping, and about the same loudness as the rest.
#   godot --headless --path . --script tests/engine_test.gd
const Engines = preload("res://scripts/engines.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Cosmetics = preload("res://scripts/cosmetics.gd")

func _initialize() -> void:
	var fails := 0
	for b in Cosmetics.BODIES:
		if not Engines.PROFILES.has(b["id"]):
			print("FAIL %s has no engine profile" % b["id"])
			fails += 1
	for id in WorldView.BODIES:
		if not Engines.PROFILES.has(id):
			print("FAIL %s has no engine profile" % id)
			fails += 1
			continue
		var p: Dictionary = Engines.PROFILES[id]
		var fires := Engines.LOOP * float(p["base"])
		if absf(fires - roundf(fires)) > 0.001:
			print("FAIL %s: %.2f firings per loop, not whole" % [id, fires])
			fails += 1
		if int(roundf(fires)) % (p["pat"] as Array).size() != 0 or (p["pat"] as Array).size() != (p["lope"] as Array).size():
			print("FAIL %s: firing pattern does not fit the loop" % id)
			fails += 1
		var wc := float(p["whine"][0]) * fires   # whine cycles per loop, whole too
		if absf(wc - roundf(wc)) > 0.001:
			print("FAIL %s: whine does not loop (%.2f cycles)" % [id, wc])
			fails += 1
		for sp in [0.0, 1100.0]:
			var pitch := Engines.freq(p, sp) / float(p["base"])
			if pitch < 0.4 or pitch > 3.0:
				print("FAIL %s: pitch %.2f at speed %d is outside the player's range" % [id, pitch, sp])
				fails += 1
		var s := Engines.render(p)
		var sq := 0.0
		var peak := 0.0
		for v in s:
			if is_nan(v):
				peak = INF
				break
			sq += v * v
			peak = maxf(peak, absf(v))
		var rms := sqrt(sq / s.size())
		if peak > 0.99 or rms < 0.2 or rms > 0.35:
			print("FAIL %s: peak %.2f rms %.2f" % [id, peak, rms])
			fails += 1
	print("engine_test: %s" % ("OK" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)
