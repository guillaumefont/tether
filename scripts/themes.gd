# The four worlds a track can be dressed in. Only the look changes: track layouts,
# grip and medal times are the same in every theme.
# Each entry is plain data read by world_view.gd (ground, road, edge banks, towers,
# jumps, scenery, weather) and by the car builder (which kit the cars wear).
extends RefCounted

const ORDER := ["snow", "forest", "rock", "sand"]

const THEMES := {
	"snow": {
		"name": "Snowfield",
		"ground": Color("#c9d6e0"), "ground_dots": Color("#b4c4d1"),
		"ambient": Color("#a9c2dc"), "sun": Color("#fff3e4"),
		# road surface: base colour, patches (glossy ice here), edge creep
		"road": Color("#353e49"), "patch": Color("#7a99b3"), "patch_amt": 0.5, "patch_rough": 0.25,
		"streak": Color("#bfd6eb"), "edge": Color("#dbe8f2"), "road_rough": 0.8,
		# edge: a verge strip, then a bank (inner face, crest, outer slope)
		"verge": Color("#9fb4c6"), "bank_face": Color("#b7c8d6"), "bank_top": Color("#eef3f7"),
		"bank_slope": Color("#dfe8ef"), "bank_h": 30.0, "bank_jag": 0.0,
		"rail_top": Color("#eef3f7"),
		# towers: column, cap, the drift round the foot, hanging icicles
		"column": Color("#3f4c5c"), "cap": Color("#eef3f7"), "foot": Color("#eef3f7"),
		"icicles": true, "hub": Color("#eef3f7"),
		# jumps: kicker stripes, the gap (edge to middle colour) and its lips
		"ramp_a": Color("#eef3f7"), "ramp_b": Color("#4f8fc0"),
		"gap_edge": Color("#1f5f86"), "gap_mid": Color("#06100f"), "lip": Color("#7fd8f0"),
		"spray": [Color("#eef3f7"), Color("#9fb4c6")],
		"weather": "snow", "props": "snow", "kit": "snow",
	},
	"forest": {
		"name": "Pinewood",
		"ground": Color("#3a5f2a"), "ground_dots": Color("#325425"),
		"ambient": Color("#b4cc9c"), "sun": Color("#fff0d2"),
		"road": Color("#5b4734"), "patch": Color("#3a2e24"), "patch_amt": 0.55, "patch_rough": 0.35,
		"streak": Color("#6b5a48"), "edge": Color("#8a6a34"), "road_rough": 0.95,
		"verge": Color("#4a6a30"), "bank_face": Color("#6b4f34"), "bank_top": Color("#5c8a3a"),
		"bank_slope": Color("#3f6530"), "bank_h": 26.0, "bank_jag": 0.0,
		"rail_top": Color("#5c8a3a"),
		"column": Color("#5d6656"), "cap": Color("#5c8a3a"), "foot": Color("#4f7d33"),
		"icicles": false, "hub": Color("#5c8a3a"),
		"ramp_a": Color("#a07a50"), "ramp_b": Color("#6e5236"),
		"gap_edge": Color("#2f7d84"), "gap_mid": Color("#0f2c33"), "lip": Color("#c9a46a"),
		"spray": [Color("#7a5a36"), Color("#5c8a3a")],
		"weather": "leaves", "props": "forest", "kit": "forest",
	},
	"rock": {
		"name": "Highlands",
		"ground": Color("#5c605a"), "ground_dots": Color("#50544f"),
		"ambient": Color("#b8bec4"), "sun": Color("#fff1de"),
		"road": Color("#45403c"), "patch": Color("#6c635b"), "patch_amt": 0.45, "patch_rough": 0.95,
		"streak": Color("#7d746b"), "edge": Color("#9a9c96"), "road_rough": 0.9,
		"verge": Color("#6c6e69"), "bank_face": Color("#64666a"), "bank_top": Color("#8e9090"),
		"bank_slope": Color("#696d67"), "bank_h": 36.0, "bank_jag": 1.0,
		"rail_top": Color("#918a83"),
		"column": Color("#5d5f63"), "cap": Color("#8e9090"), "foot": Color("#6c6e69"),
		"icicles": false, "hub": Color("#8e9090"),
		"ramp_a": Color("#8e9090"), "ramp_b": Color("#d38a33"),
		"gap_edge": Color("#3d2c24"), "gap_mid": Color("#0b0706"), "lip": Color("#e8a64a"),
		"spray": [Color("#b4b6b0"), Color("#6c6e69")],
		"weather": "dust", "props": "rock", "kit": "rock",
	},
	"sand": {
		"name": "Dunes",
		"ground": Color("#bf955a"), "ground_dots": Color("#b0874f"),
		"ambient": Color("#e6d2b2"), "sun": Color("#fff0d0"),
		"road": Color("#584638"), "patch": Color("#c9a46c"), "patch_amt": 0.4, "patch_rough": 1.0,
		"streak": Color("#d8b884"), "edge": Color("#e3c48d"), "road_rough": 0.9,
		"verge": Color("#c79c5e"), "bank_face": Color("#c99e64"), "bank_top": Color("#efd59f"),
		"bank_slope": Color("#c9a066"), "bank_h": 28.0, "bank_jag": 0.0,
		"rail_top": Color("#efd59f"),
		"column": Color("#b0744a"), "cap": Color("#dcae78"), "foot": Color("#e6c891"),
		"icicles": false, "hub": Color("#dcae78"),
		"ramp_a": Color("#efd59f"), "ramp_b": Color("#b0744a"),
		"gap_edge": Color("#8a5a32"), "gap_mid": Color("#1c1009"), "lip": Color("#f2c064"),
		"spray": [Color("#efd59f"), Color("#c79c5e")],
		"weather": "sand", "props": "sand", "kit": "sand",
	},
}

static func get_theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES["snow"])
