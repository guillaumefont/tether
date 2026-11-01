# Time Trial records and ghosts, saved per track + variant in user://records.cfg.
# Only solo Time Trial writes here; races never set records (same rule as the prototype).
extends RefCounted

const PATH := "user://records.cfg"
static var _cfg: ConfigFile

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

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

static func get_ghost(k: String) -> Array:
	var flat: PackedFloat32Array = _load().get_value(k, "ghost", PackedFloat32Array())
	var out: Array = []
	for i in range(0, flat.size() - 2, 3):
		out.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	return out

static func set_ghost(k: String, trace: Array) -> void:
	var flat := PackedFloat32Array()
	for v in trace:
		flat.append(v.x); flat.append(v.y); flat.append(v.z)
	_load().set_value(k, "ghost", flat)
	_cfg.save(PATH)
