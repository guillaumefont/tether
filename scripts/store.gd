# In-app purchases, behind one small interface so each platform can plug in its own
# billing (Google Play Billing on Android, StoreKit on iOS, Steam) without the menus
# changing. For now this is a stub: there is no real billing yet. Debug builds (the editor)
# and preview builds (CI APKs, exported with the "preview" feature) grant a purchase at once so paid items can be tried; release
# builds report the store as unavailable. Owned products are kept in user://store.cfg
# (a real backend will restore them from the platform instead).
extends RefCounted

const PATH := "user://store.cfg"
static var _cfg: ConfigFile

const PRODUCTS := {
	"chrome_pack": { "name": "Chrome pack", "price": "€1.99", "desc": "Three mirror-finish paints: Chrome, Rose gold and Black chrome." },
	"neon_pack": { "name": "Neon pack", "price": "€1.99", "desc": "Three glowing paints, the Neon trim livery and a neon rope." },
}

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

static func product(id: String) -> Dictionary:
	return PRODUCTS.get(id, { "name": id, "price": "", "desc": "" })

static func owns(id: String) -> bool:
	return bool(_load().get_value("owned", id, false))

# can a purchase be made on this build at all
static func available() -> bool:
	return OS.is_debug_build() or OS.has_feature("preview")

# buy a product; returns "ok", "owned" or "unavailable". A real backend answers later
# (a callback), so callers should treat this as "the purchase flow finished".
static func buy(id: String) -> String:
	if owns(id):
		return "owned"
	if not available():
		return "unavailable"
	_load().set_value("owned", id, true)
	_cfg.save(PATH)
	return "ok"

# restore purchases from the platform (nothing to do for the stub)
static func restore() -> void:
	pass
