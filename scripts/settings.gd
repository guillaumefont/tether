# Player options kept between sessions in user://settings.cfg: sound, ghost car, effects.
extends RefCounted

const PATH := "user://settings.cfg"
static var _cfg: ConfigFile

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

static func get_opt(key: String, default = true):
	return _load().get_value("options", key, default)

static func set_opt(key: String, v) -> void:
	_load().set_value("options", key, v)
	_cfg.save(PATH)
