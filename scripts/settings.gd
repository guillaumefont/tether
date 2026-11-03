# Player options kept between sessions in user://settings.cfg: music and sound volume
# (0..100), ghost car, effects.
extends RefCounted

const PATH := "user://settings.cfg"
static var _cfg: ConfigFile

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

const DEFAULTS := { "music_vol": 70, "sfx_vol": 100, "ghost": true, "effects": true }

static func get_opt(key: String, default = null):
	var c := _load()
	if c.has_section_key("options", key):
		return c.get_value("options", key)
	# saves from before the volume sliders had one Sound on/off switch
	if key in ["music_vol", "sfx_vol"] and c.get_value("options", "sound", true) == false:
		return 0
	return DEFAULTS.get(key, true) if default == null else default

static func set_opt(key: String, v) -> void:
	_load().set_value("options", key, v)
	_cfg.save(PATH)
