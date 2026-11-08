# Coins: earned with medals, the Track of the day and awards, spent on Garage looks.
# Kept in user://wallet.cfg with the looks bought, the awards earned, a few counters
# (records set, tracks of the day played) and the Track of the day already paid today.
# Looks only: coins never buy speed, so rankings stay fair.
extends RefCounted

const PATH := "user://wallet.cfg"
static var _cfg: ConfigFile

# coins for a medal tier (Bronze..Pivot) the first time it is reached on a track +
# variant + mode, and for a later run that earns a tier already held (about a quarter)
const FIRST := [20, 30, 50, 80]
const REPEAT := [5, 8, 12, 20]

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

static func _save() -> void:
	_cfg.save(PATH)

static func coins() -> int:
	return int(_load().get_value("wallet", "coins", 0))

static func add(n: int) -> void:
	if n <= 0:
		return
	_load().set_value("wallet", "coins", coins() + n)
	_save()

# false (and nothing spent) when the player can't afford it
static func spend(n: int) -> bool:
	if n > coins():
		return false
	_load().set_value("wallet", "coins", coins() - n)
	_save()
	return true

# coins a run pays for its medal: the full value of every tier it reaches for the first
# time (from `held`, the best tier held before the run), or the repeat value of its tier
static func medal_coins(held: int, run_tier: int) -> int:
	if run_tier <= 0:
		return 0
	if run_tier > held:
		var n := 0
		for t in range(held, run_tier):
			n += FIRST[t]
		return n
	return REPEAT[run_tier - 1]

# ---------------------------------------------------------------- looks bought
static func owns(key: String) -> bool:
	return bool(_load().get_value("owned", key, false))

static func set_owned(key: String) -> void:
	_load().set_value("owned", key, true)
	_save()

# ---------------------------------------------------------------- awards and counters
static func has_award(id: String) -> bool:
	return bool(_load().get_value("awards", id, false))

static func set_award(id: String) -> void:
	_load().set_value("awards", id, true)
	_save()

static func stat(k: String) -> int:
	return int(_load().get_value("stats", k, 0))

static func bump(k: String, n := 1) -> void:
	_load().set_value("stats", k, stat(k) + n)
	_save()

static func get_v(section: String, k: String, default = null):
	return _load().get_value(section, k, default)

static func set_v(section: String, k: String, v) -> void:
	_load().set_value(section, k, v)
	_save()

# ---------------------------------------------------------------- reset
# a fresh wallet: no coins, looks, awards or counters. `migrated` stays set so the
# looks of the old medal-unlock rules are not handed back.
static func reset() -> void:
	_cfg = ConfigFile.new()
	_cfg.set_value("meta", "migrated", true)
	_save()
