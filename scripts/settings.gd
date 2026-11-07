# Player options kept between sessions in user://settings.cfg: music and sound volume
# (0..100), ghost car, graphics quality, vibration; whether the first-launch tutorial has been played.
extends RefCounted

const PATH := "user://settings.cfg"
static var _cfg: ConfigFile

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

const DEFAULTS := { "music_vol": 70, "sfx_vol": 100, "ghost": true, "haptics": true, "tutorial_done": false }

# graphics quality: what each level turns on is in WorldView.set_quality
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

# phones start on Medium, computers on High
static func default_quality() -> int:
	return 1 if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") else 2

static func get_opt(key: String, default = null):
	var c := _load()
	if c.has_section_key("options", key):
		return c.get_value("options", key)
	# saves from before the quality setting had one Effects on/off switch
	if key == "quality":
		return 0 if c.get_value("options", "effects", true) == false else default_quality()
	# saves from before the volume sliders had one Sound on/off switch
	if key in ["music_vol", "sfx_vol"] and c.get_value("options", "sound", true) == false:
		return 0
	return DEFAULTS.get(key, true) if default == null else default

static func set_opt(key: String, v) -> void:
	_load().set_value("options", key, v)
	_cfg.save(PATH)
