# Medals per track, variant and mode. Time Trial: beat a lap target (a run-score target
# on Collect) derived from the AI reference time. Race (one player): finish 3rd, 2nd, 1st,
# or win by RACE_TOP_GAP seconds for the top tier. Earned medals are kept in records.cfg.
extends RefCounted

const Times = preload("res://scripts/medal_times.gd")

const NAMES := ["Bronze", "Silver", "Gold", "Pivot"]
const COLORS := [Color("#c98a55"), Color("#c9d3d6"), Color("#f2b134"), Color("#5fe0d0")]
const TRIAL_K := [1.30, 1.15, 1.03, 0.96]   # target = reference x k
const RACE_TOP_GAP := 3.0

static func targets(track_name: String, variant: String) -> Array:
	var ref: float = Times.REF.get(track_name, {}).get(variant, -1.0)
	var out: Array = []
	for k in TRIAL_K:
		out.append(snappedf(ref * k, 0.05) if ref > 0.0 else -1.0)
	return out

# 0 = none, 1..4 = bronze..pivot
static func trial_tier(track_name: String, variant: String, t: float) -> int:
	if t <= 0.0:
		return 0
	var tg := targets(track_name, variant)
	var tier := 0
	for i in tg.size():
		if tg[i] > 0.0 and t <= tg[i]:
			tier = i + 1
	return tier

static func race_tier(place: int, lead: float) -> int:
	if place == 1:
		return 4 if lead >= RACE_TOP_GAP else 3
	if place == 2:
		return 2
	if place == 3:
		return 1
	return 0
