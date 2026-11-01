# Layout rules shared by the layout tools: bends flat with room to ramp, roads clear of
# each other (unless one passes over the other at a crossing) and of the towers.
extends RefCounted
const TrackData = preload("res://scripts/track.gd")
const HW := TrackData.HW

static func check(d: Dictionary) -> Dictionary:
	var bad := 0.0
	var why := {}
	var T := TrackData.new(d, "standard")
	if T.ramp_report != "":
		bad += 1000.0 * T.ramp_report.count(";")
	var Tr := TrackData.new(d, "reverse")
	if Tr.ramp_report != "":
		bad += 1000.0 * Tr.ramp_report.count(";")
	# roads keep apart unless one is a level above the other
	var n := T.n
	for i in n:
		for j in range(i + 1, n):
			var ds := absf(T.seg_s0[j] - T.seg_s0[i]); ds = minf(ds, T.L - ds)
			if ds < 900.0: continue
			var d2 := T.P[i].distance_to(T.P[j])
			if d2 >= 2 * HW + 60.0: continue
			var dh := absf(T.height_of[i] - T.height_of[j])
			if dh < 30.0 or (dh < TrackData.LEVEL_H * 0.9 and d2 < 2 * HW - 10.0):
				bad += 50.0; why["flat"] = why.get("flat", 0) + 1; if OS.has_environment("DBG"): printerr([i, j, roundi(T.seg_s0[i]), roundi(T.seg_s0[j]), roundi(d2), roundi(T.height_of[i]), roundi(T.height_of[j])])
			elif not _near_crossing(T, i) or not _near_crossing(T, j):
				why["stack"] = why.get("stack", 0) + 1
				bad += 50.0   # long stacked overlap: the lower road would be hidden
	# two curves on one tower need clearly different radii, or one hides the other
	for i in T.anchors.size():
		for j in range(i + 1, T.anchors.size()):
			var A = T.anchors[i]; var B = T.anchors[j]
			if A.pos.distance_to(B.pos) < 1.0 and absf(A.r - B.r) < 300.0:
				bad += 5000.0; why["same_r"] = why.get("same_r", 0) + 1
	# towers clear of every road
	for a in T.anchors:
		for p in T.P:
			if p.distance_to(a.pos) < HW + 70.0:
				bad += 50.0; why["tower"] = why.get("tower", 0) + 1
	return { "bad": bad, "L": T.L, "area": T.bounds.get_area(), "bridges": T.bridges.size(), "levels": Array(T.arc_level), "why": why }

static func _near_crossing(T: TrackData, i: int) -> bool:
	for B in T.bridges:
		for k in [int(B["under"]), (int(B["from"]) + posmod(int(B["to"]) - int(B["from"]), T.n) / 2) % T.n]:
			var ds := absf(T.seg_s0[i] - T.seg_s0[k]); ds = minf(ds, T.L - ds)
			if ds < 650.0: return true
	return false
