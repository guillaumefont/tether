# Track layouts from the JS feel prototype (v32), some reshaped so every
# bridge ramp sits on a straight and the bends stay level.
# Each track is a loop of towers [x, y, direction, radius?] in world units
# (y grows "south", i.e. towards the camera). The road wraps round each tower
# (dir +1 clockwise seen from above, -1 anticlockwise) and the straights are
# the tangents between consecutive towers. All layouts are original.
# "theme" is the track's home world (scripts/themes.gd), used outside the campaign.
extends RefCounted

const TRACKS := [
	{ "name": "Lasso", "theme": "forest", "note": "A big loop with a knot at the end", "laps": 5, "jumps": [{ "k": 0, "f": 0.5 }],
		"turns": [[700,1050,1],[1600,750,1],[3400,1050,-1],[1600,1350,1]] },
	{ "name": "Diamond Eight", "theme": "sand", "note": "Two diamonds joined by a bridge", "laps": 3,
		"turns": [[700,1300,1],[1500,700,1],[2300,1300,-1],[3100,1900,-1],[3900,1300,-1],[3100,700,-1],[2300,1300,1],[1500,1900,1]] },
	{ "name": "Sidestep", "theme": "sand", "note": "S-bends both ways", "laps": 3,
		"turns": [[1915,1092,-1],[2793,700,1],[3504,1043,1],[3319,1842,1],[2469,2087,-1],[1545,2500,1],[700,2075,1],[835,1446,1]] },
	{ "name": "Three Fingers", "theme": "sand", "note": "Three long hairpins", "laps": 4,
		"turns": [[844,1352,-1],[1392,883,1],[2256,700,1],[2421,1552,-1],[2700,2558,1],[1582,2566,-1],[700,2362,1]] },
	{ "name": "Big Top", "theme": "forest", "note": "A jump across the top", "laps": 4, "jumps": [{ "k": 3, "f": 0.5 }],
		"turns": [[785,1374,-1],[1533,705,1],[2427,700,1],[2622,1396,-1],[2538,2548,1],[1712,2505,-1],[700,2102,1]] },
	{ "name": "Fishhook", "theme": "rock", "note": "Hairpins that fold back", "laps": 3,
		"turns": [[1436,1371,1],[1879,700,1],[2422,1204,1],[2589,2089,-1],[3268,2679,1],[2631,3324,1],[1852,3017,-1],[1289,3642,1],[700,2956,1],[979,1941,-1]] },
	{ "name": "Squall", "theme": "rock", "note": "Tight and twisting", "laps": 3,
		"turns": [[1496,1366,1],[2138,700,1],[2891,990,1],[2662,1992,-1],[3344,2435,1],[2592,2859,1],[1834,3097,-1],[700,2937,1],[1201,2097,-1]] },
	{ "name": "Pretzel", "theme": "sand", "note": "Two bridges and a jump", "laps": 3, "jumps": [{ "k": 2, "f": 0.5 }],
		"turns": [[600,600,1,750],[600,2800,1,750],[2600,2200,-1],[2600,1200,-1]] },
	{ "name": "Knucklebone", "theme": "snow", "note": "Short links, no rest", "laps": 3,
		"turns": [[2155,700,1],[2800,788,1],[3011,1570,-1],[3778,2402,1],[3207,3112,-1],[2517,3633,1],[2003,3227,1],[1839,2324,-1],[883,1647,1],[700,992,1],[1374,748,-1]] },
	{ "name": "Starfish", "theme": "snow", "note": "Twelve towers, five arms", "laps": 3,
		"turns": [[809,1019,1],[1541,821,-1],[2342,700,1],[3111,1207,-1],[3842,1593,1],[4267,2173,1],[3674,2598,-1],[2736,2987,1],[1875,2753,-1],[700,2796,1],[838,2072,-1]] },
	{ "name": "Trefoil", "theme": "snow", "note": "Three loops, two crossings", "laps": 3,
		"turns": [[626,2386,1,750],[1929,1372,-1],[1269,156,1,750]] },
	{ "name": "Triskel", "theme": "rock", "note": "Three loops tied in a knot", "laps": 3,
		"turns": [[1188,191,-1,750],[1726,3030,-1,750],[-98,1902,1]] },
	{ "name": "Knot", "theme": "rock", "note": "Four towers tied together", "laps": 2,
		"turns": [[795,765,1,750],[3005,2635,1,750],[3005,765,1,750],[795,2635,1,750]] },
	{ "name": "Coil", "theme": "forest", "note": "A long S over two bridges", "laps": 4,
		"turns": [[2000,1200,1],[3700,700,-1],[2000,1200,1,750],[300,1700,-1]] },
	{ "name": "Halo", "theme": "snow", "note": "A ring round the middle tower", "laps": 2,
		"turns": [[1625,679,1],[2619,1453,1],[1625,679,1,750],[1156,1536,1,750]] },
	{ "name": "Arch", "theme": "rock", "note": "A summit between two loops", "laps": 4,
		"turns": [[1800,900,1],[3500,1800,-1],[1800,900,1,750],[100,1800,-1]] },
	{ "name": "Twin Bend", "theme": "forest", "note": "Two hairpins round one tower", "laps": 4,
		"turns": [[1900,900,1],[2900,1600,-1],[1900,900,-1,750],[900,1600,1]] },
]

# The first-launch tutorial's own track (scripts/tutorial.gd): five roomy bends, one of them
# turning the other way, no crossings or jumps. Not listed in the menus. "laps" is a cap:
# the tutorial decides when the run ends.
const TUTORIAL := { "name": "Training Loop", "theme": "snow", "note": "Learn to hook and let go", "laps": 99,
	"turns": [[700,900,1],[2300,700,1],[3100,1500,1],[2000,1500,-1],[900,1900,1]] }

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
