# Short vibrations on phones: a tick on hook, a knock on a hard wall hit, a thud on a post,
# a longer buzz for a record or a medal. Off with the Vibration setting.
extends RefCounted

const Settings = preload("res://scripts/settings.gd")

static var _last_ms := 0

# only where there is something to vibrate (phones, and phone browsers)
static func available() -> bool:
	return DisplayServer.is_touchscreen_available()

# ms: length, amp: 0..1 strength (Android 8+; older phones ignore it)
static func buzz(ms: int, amp := 0.5, min_gap_ms := 60) -> void:
	if not available() or not Settings.get_opt("haptics"):
		return
	var now := Time.get_ticks_msec()
	if now - _last_ms < min_gap_ms:
		return
	_last_ms = now
	Input.vibrate_handheld(ms, amp)

static func hook() -> void: buzz(12, 0.35)
static func knock(strength: float) -> void: buzz(int(lerpf(20, 45, strength)), lerpf(0.45, 0.9, strength), 90)
static func post() -> void: buzz(40, 0.8, 0)
static func reward() -> void: buzz(90, 0.7, 0)
