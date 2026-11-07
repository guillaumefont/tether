# Time Trial records and ghosts, saved per track + variant in user://records.cfg.
# Only solo Time Trial writes here; races never set records (same rule as the prototype).
extends RefCounted

const PATH := "user://records.cfg"
# Bumped whenever track layouts change: best times and ghosts set on an older layout are
# dropped (they no longer match the road). Medals and campaign progress are kept.
# 2: 2026-11 rework (shorter straights, more bends and crossings).
const LAYOUT_VERSION := 2
const META := "meta"
static var _cfg: ConfigFile

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
		_move_ghosts()
		_drop_old_layout_records()
	return _cfg

static func _drop_old_layout_records() -> void:
	if int(_cfg.get_value(META, "layouts", 1)) >= LAYOUT_VERSION:
		return
	var had_any := _cfg.get_sections().size() > 0
	for k in _cfg.get_sections():
		if k == META:
			continue
		for key in ["best", "lap"]:
			if _cfg.has_section_key(k, key):
				_cfg.erase_section_key(k, key)
		var gp := _ghost_path(k)
		if FileAccess.file_exists(gp):
			DirAccess.remove_absolute(gp)
	_cfg.set_value(META, "layouts", LAYOUT_VERSION)
	if had_any:
		_cfg.save(PATH)

static func key(track_name: String, variant: String) -> String:
	return track_name + ("" if variant == "standard" else "-" + variant)

static func get_best(k: String) -> float:
	return float(_load().get_value(k, "best", -1.0))

static func set_best(k: String, v: float) -> void:
	_load().set_value(k, "best", v)
	_cfg.save(PATH)

# Collect variant: the record is the run score; the best raw lap drives the ghost
static func get_lap(k: String) -> float:
	return float(_load().get_value(k, "lap", -1.0))

static func set_lap(k: String, v: float) -> void:
	_load().set_value(k, "lap", v)
	_cfg.save(PATH)

# Ghosts live in their own small binary file per track + variant (user://ghosts/).
# They used to sit in records.cfg as text, so every new lap record rewrote every
# ghost of every track at the finish line: a visible hitch that grew with play.
const GHOST_DIR := "user://ghosts"

static func _ghost_path(k: String) -> String:
	return "%s/%s.bin" % [GHOST_DIR, k.validate_filename()]

# once, on first load: an older build kept the ghosts in records.cfg
static func _move_ghosts() -> void:
	var moved := false
	for k in _cfg.get_sections():
		if _cfg.has_section_key(k, "ghost"):
			var flat: PackedFloat32Array = _cfg.get_value(k, "ghost")
			if _write_ghost(k, flat):
				_cfg.erase_section_key(k, "ghost")
				moved = true
	if moved:
		_cfg.save(PATH)

static func _write_ghost(k: String, flat: PackedFloat32Array) -> bool:
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	var f := FileAccess.open(_ghost_path(k), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(flat.to_byte_array())
	f.close()
	return true

static func get_ghost(k: String) -> Array:
	_load()
	var flat := PackedFloat32Array()
	var f := FileAccess.open(_ghost_path(k), FileAccess.READ)
	if f:
		flat = f.get_buffer(f.get_length()).to_float32_array()
	var out: Array = []
	for i in range(0, flat.size() - 2, 3):
		out.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	return out

static func set_ghost(k: String, trace: Array) -> void:
	var flat := PackedFloat32Array()
	flat.resize(trace.size() * 3)
	for i in trace.size():
		var v: Vector3 = trace[i]
		flat[i * 3] = v.x; flat[i * 3 + 1] = v.y; flat[i * 3 + 2] = v.z
	_write_ghost(k, flat)

# medals: best tier earned (0 none, 1 bronze .. 4 pivot) per track + variant, per mode
static func get_medal(k: String, mode: String) -> int:
	return int(_load().get_value(k, "medal_" + mode, 0))

# returns true when this is an upgrade
static func award_medal(k: String, mode: String, tier: int) -> bool:
	if tier <= get_medal(k, mode):
		return false
	_load().set_value(k, "medal_" + mode, tier)
	_cfg.save(PATH)
	return true

# progress flags (campaign worlds finished)
static func get_flag(section: String, k: String) -> bool:
	return bool(_load().get_value(section, k, false))

static func set_flag(section: String, k: String) -> void:
	_load().set_value(section, k, true)
	_cfg.save(PATH)

# anything saved at all: a player who already raced is not a first-time player
static func any() -> bool:
	for k in _load().get_sections():
		if k != META:
			return true
	return false
