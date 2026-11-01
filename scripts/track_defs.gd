# Track layouts, ported 1:1 from the JS feel prototype (v32).
# Each track is a loop of towers [x, y, direction, radius?] in world units
# (y grows "south", i.e. towards the camera). The road wraps round each tower
# (dir +1 clockwise seen from above, -1 anticlockwise) and the straights are
# the tangents between consecutive towers. All layouts are original.
extends RefCounted

const TRACKS := [
	{ "name": "Lasso", "note": "A big loop with a knot at the end", "laps": 5, "jumps": [{ "k": 0, "f": 0.5 }],
		"turns": [[700,1050,1],[1700,700,1],[2600,1050,-1],[1700,1400,1]] },
	{ "name": "Diamond Eight", "note": "Two diamonds joined by a bridge", "laps": 3,
		"turns": [[700,1300,1],[1500,700,1],[2300,1300,-1],[3100,1900,-1],[3900,1300,-1],[3100,700,-1],[2300,1300,1],[1500,1900,1]] },
	{ "name": "Sidestep", "note": "S-bends both ways", "laps": 3,
		"turns": [[1915,1092,-1],[2793,700,1],[3504,1043,1],[3319,1842,1],[2469,2087,-1],[1545,2500,1],[700,2075,1],[835,1446,1]] },
	{ "name": "Three Fingers", "note": "Three long hairpins", "laps": 4,
		"turns": [[844,1352,-1],[1392,883,1],[2256,700,1],[2421,1552,-1],[2700,2558,1],[1582,2566,-1],[700,2362,1]] },
	{ "name": "Big Top", "note": "A jump across the top", "laps": 4, "jumps": [{ "k": 3, "f": 0.5 }],
		"turns": [[785,1374,-1],[1533,705,1],[2427,700,1],[2622,1396,-1],[2538,2548,1],[1712,2505,-1],[700,2102,1]] },
	{ "name": "Fishhook", "note": "Hairpins that fold back", "laps": 3,
		"turns": [[1436,1371,1],[1879,700,1],[2422,1204,1],[2589,2089,-1],[3268,2679,1],[2631,3324,1],[1852,3017,-1],[1289,3642,1],[700,2956,1],[979,1941,-1]] },
	{ "name": "Squall", "note": "Tight and twisting", "laps": 3,
		"turns": [[1496,1366,1],[2138,700,1],[2891,990,1],[2662,1992,-1],[3344,2435,1],[2592,2859,1],[1834,3097,-1],[700,2937,1],[1201,2097,-1]] },
	{ "name": "Pretzel", "note": "Two bridges and a jump", "laps": 4, "jumps": [{ "k": 2, "f": 0.5 }],
		"turns": [[700,700,1],[700,2100,1],[2100,2100,-1],[2100,700,-1]] },
	{ "name": "Knucklebone", "note": "Short links, no rest", "laps": 3,
		"turns": [[2155,700,1],[2800,788,1],[3011,1570,-1],[3778,2402,1],[3207,3112,-1],[2517,3633,1],[2003,3227,1],[1839,2324,-1],[883,1647,1],[700,992,1],[1374,748,-1]] },
	{ "name": "Starfish", "note": "Twelve towers, five arms", "laps": 3,
		"turns": [[809,1019,1],[1541,821,-1],[2342,700,1],[3111,1207,-1],[3842,1593,1],[4267,2173,1],[3674,2598,-1],[2736,2987,1],[1875,2753,-1],[700,2796,1],[838,2072,-1]] },
	{ "name": "Trefoil", "note": "Three loops, three crossings", "laps": 4,
		"turns": [[900,2032,1],[1947,1427,-1],[970,900,1]] },
	{ "name": "Triskel", "note": "A tight knot of loops", "laps": 4,
		"turns": [[1620,900,-1],[2107,1950,-1],[900,1954,1]] },
	{ "name": "Knot", "note": "Four towers tied together", "laps": 3,
		"turns": [[2069,2017,1],[2337,900,1],[1377,1245,-1],[900,2118,1]] },
	{ "name": "Coil", "note": "One tower, two curves, two bridges", "laps": 4,
		"turns": [[2000,1200,1],[3100,900,-1],[2000,1200,1,750],[900,1500,-1]] },
	{ "name": "Halo", "note": "A ring round the middle tower", "laps": 2,
		"turns": [[1900,900,1],[2900,1500,1],[1900,900,1,750],[900,1500,1]] },
	{ "name": "Arch", "note": "Inner and outer curve on the summit", "laps": 4,
		"turns": [[1800,900,1],[2700,1800,-1],[1800,900,1,750],[900,1800,-1]] },
	{ "name": "Twin Bend", "note": "Two hairpins round one tower", "laps": 4,
		"turns": [[1900,900,1],[2900,1600,-1],[1900,900,-1,750],[900,1600,1]] },
]

const VARIANTS := [
	["standard", "Standard", "the plain layout"],
	["reverse", "Reverse", "same track, other way round"],
	["obstacles", "Obstacles", "posts break when hit: +1 s each"],
	["collect", "Collect", "follow the gem line; score = time + 0.25 s per miss"],
]

const ROSTER := [
	{ "name": "Player 1", "color": Color("#f2b134"), "skill": 1.0 },
	{ "name": "Player 2", "color": Color("#5fd38d"), "skill": 1.0 },
	{ "name": "Vesna", "color": Color("#4fc3e8"), "skill": 0.97 },
	{ "name": "Okoro", "color": Color("#e2574c"), "skill": 0.94 },
	{ "name": "Brandt", "color": Color("#a98cf0"), "skill": 0.91 },
]
