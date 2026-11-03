# Background music: one looping track at a time, crossfaded when the scene
# changes (menu -> race -> menu). The tracks are original, composed and
# rendered by tools/music/compose.py, and loop seamlessly (loop=true in their
# .import files). Muted together with the sound effects.
extends Node

const TRACKS := {
	"menu": "res://music/menu.ogg",
	"race_a": "res://music/race_a.ogg",
	"race_b": "res://music/race_b.ogg",
}
const RACE_TRACKS := ["race_a", "race_b"]
const VOLUME_DB := { "menu": -9.0, "race_a": -9.0, "race_b": -9.0 }
const FADE := 1.2   # seconds for a crossfade
const SILENT := -60.0

var enabled := true:
	set(v):
		enabled = v
		_apply()
var current := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens: Array = [null, null]

func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = SILENT
		add_child(p)
		_players.append(p)

func race_track(track_idx: int) -> String:
	return RACE_TRACKS[track_idx % RACE_TRACKS.size()]

# switch to `name` ("" for silence); a no-op if it is already playing
func play(name: String) -> void:
	if name == current:
		return
	current = name
	_apply()

func _apply() -> void:
	if _players.is_empty():
		return
	var cur := _players[_active]
	var want := current if enabled else ""
	if want == "":
		_fade(_active, SILENT, true)
		return
	var stream: AudioStream = load(TRACKS[want])
	if cur.stream == stream and cur.playing:
		_fade(_active, VOLUME_DB[want], false)
		return
	# fade the old one out, start the new one on the other player
	_fade(_active, SILENT, true)
	_active = 1 - _active
	var nxt := _players[_active]
	nxt.stream = stream
	nxt.volume_db = SILENT
	nxt.play()
	_fade(_active, VOLUME_DB[want], false)

func _fade(i: int, to_db: float, stop_after: bool) -> void:
	if _tweens[i]:
		_tweens[i].kill()
	var p := _players[i]
	if not p.playing:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, FADE).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[i] = tw
