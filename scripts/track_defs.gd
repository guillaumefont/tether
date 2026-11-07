# Track layouts, first drawn in the JS feel prototype (v32), reworked in 2026-11 for short
# links: straights are about one lane long between bends (longer only where a jump or a
# bridge ramp needs the room). Every bridge ramp sits on a straight and the bends stay level.
# Each track is a loop of towers [x, y, direction, radius?] in world units
# (y grows "south", i.e. towards the camera). The road wraps round each tower
# (dir +1 clockwise seen from above, -1 anticlockwise) and the straights are
# the tangents between consecutive towers. All layouts are original.
# "theme" is the track's home world (scripts/themes.gd), used outside the campaign.
extends RefCounted

const TRACKS := [
	{ "name": "Lasso", "theme": "forest", "note": "A big loop with a knot at the end", "laps": 5, "jumps": [{ "k": 0, "f": 0.5 }],
		"turns": [[1333,572,1],[1938,21,1],[2656,834,-1],[2995,245,-1],[1997,696,1]] },
	{ "name": "Diamond Eight", "theme": "sand", "note": "Two snaking loops joined by a bridge", "laps": 4,
		"turns": [[1947,1250,1],[2526,1706,-1],[3159,1967,-1],[3455,1348,1],[2890,954,-1],[2526,1706,1],[1870,1926,1]] },
	{ "name": "Sidestep", "theme": "sand", "note": "S-bends both ways", "laps": 4,
		"turns": [[1728,892,-1],[2423,1116,1],[3048,1462,-1],[3151,2167,1],[2548,2590,-1],[1866,2381,1],[1336,1885,-1],[1131,1222,1]] },
	{ "name": "Three Fingers", "theme": "sand", "note": "Three long hairpins", "laps": 5,
		"turns": [[1245,1726,-1],[1845,1303,1],[2202,1964,-1],[2229,2692,1],[1491,2692,-1],[825,2367,1]] },
	{ "name": "Big Top", "theme": "forest", "note": "A jump across the top", "laps": 5, "jumps": [{ "k": 2, "f": 0.5 }],
		"turns": [[972,1370,-1],[1483,874,1],[1959,1398,-1],[2068,2422,1],[1375,2412,-1],[789,2048,1]] },
	{ "name": "Fishhook", "theme": "rock", "note": "Hairpins that fold back", "laps": 4,
		"turns": [[1855,1630,1],[2563,1723,-1],[3236,1590,-1],[2983,2261,-1],[3515,2778,1],[3153,3358,1],[2470,3575,-1],[2003,3027,1],[1772,2339,-1]] },
	{ "name": "Squall", "theme": "rock", "note": "Tight and twisting", "laps": 4,
		"turns": [[1456,1356,1],[2032,979,-1],[2707,1273,1],[2396,1898,-1],[2591,2597,1],[1959,2938,-1],[1240,2827,1],[1368,2096,-1]] },
	{ "name": "Pretzel", "theme": "sand", "note": "Two bridges and a jump", "laps": 3, "jumps": [{ "k": 4, "f": 0.5 }],
		"turns": [[360,835,1,750],[970,1609,1],[550,2476,1,750],[1440,2222,1],[2109,2120,-1],[1555,1244,-1]] },
	{ "name": "Knucklebone", "theme": "snow", "note": "Short links, no rest", "laps": 4,
		"turns": [[2062,1399,-1],[2779,1296,1],[2966,1961,-1],[3485,2425,1],[3248,3062,1],[2586,3268,-1],[2148,2701,1],[1551,2346,-1],[1081,1819,1],[1379,1201,1]] },
	{ "name": "Starfish", "theme": "snow", "note": "Ten towers, five arms", "laps": 4,
		"turns": [[897,1249,1],[1604,1090,-1],[2240,785,1],[2928,1034,-1],[3449,1535,1],[3463,2239,-1],[2830,2550,1],[2246,2172,-1],[1568,2387,1],[986,1962,-1]] },
	{ "name": "Trefoil", "theme": "snow", "note": "Three loops, two crossings", "laps": 3,
		"turns": [[421,1807,1,750],[1636,1395,-1],[1287,258,1,750]] },
	{ "name": "Triskel", "theme": "rock", "note": "Three loops tied in a knot", "laps": 4,
		"turns": [[1316,626,-1,750],[1747,2294,-1,750],[527,1629,1]] },
	{ "name": "Knot", "theme": "rock", "note": "Three towers tied in a knot", "laps": 3,
		"turns": [[2532,2206,1,750],[2505,1224,1,750],[1581,1706,1,750]] },
	{ "name": "Coil", "theme": "forest", "note": "A coiled S over two bridges", "laps": 4,
		"turns": [[2235,1538,1],[2874,1308,-1],[3542,1226,-1],[2235,1538,1,750],[1203,1190,-1],[1359,1849,-1]] },
	{ "name": "Halo", "theme": "snow", "note": "A ring round the middle tower", "laps": 2,
		"turns": [[1539,744,1],[2468,684,1],[2284,1339,1],[1539,744,1,750],[1153,1588,1,750]] },
	{ "name": "Arch", "theme": "rock", "note": "A summit between two loops", "laps": 4,
		"turns": [[1574,1224,1],[2124,1968,-1],[2611,1488,-1],[1574,1224,1,750],[238,1307,-1],[899,1159,-1]] },
	{ "name": "Twin Bend", "theme": "forest", "note": "Two hairpins round one tower", "laps": 5,
		"turns": [[2126,1994,1],[2126,2673,-1],[2126,1994,-1,750],[1165,1499,1]] },
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
