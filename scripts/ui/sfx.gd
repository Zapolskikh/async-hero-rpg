extends Node
## Sound effects (tools/gen_sounds.py). A busy fight fires dozens of events a second, so the
## same sound has a minimum gap and only VOICES sounds play at once.

const VOICES := 10
const MIN_GAP_MS := 90
const LEVELS := [["Выкл", 0.0], ["Тихо", 0.35], ["Средне", 0.65], ["Громко", 1.0]]
const SETTINGS := "user://audio.cfg"
const VARIANTS := {"sword_hit": 3, "heavy_hit": 2, "arrow_shot": 2, "death_enemy": 2}
## Spell effect -> sound. Enemy spells have no effect name: see _ENEMY.
const SPELL_SOUNDS := {"fire": "fire", "fire_arrow": "fire", "frost": "frost", "lightning": "lightning", "arcane": "arcane",
	"curse": "curse", "spirit": "spirit", "poison_arrow": "poison", "heal": "heal", "heal_chain": "heal", "holy": "heal",
	"prayer": "heal", "nature": "nature", "water": "water", "earth": "shield", "shield": "shield", "shield_hit": "block",
	"shield_throw": "block", "shockwave": "shockwave", "shout": "shout", "slash": "sword_hit", "heavy": "heavy_hit",
	"blade": "sword_hit", "bleed": "sword_hit", "whirlwind": "whirl", "arrow": "arrow_shot", "arrow_rain": "arrow_shot",
	"beast": "beast", "cleanse": "cleanse", "prism": "arcane", "stun": "stun"}
const _ENEMY := {"e_heal": "heal", "e_shield": "shield", "e_ward": "shield", "e_plague": "poison", "e_venom": "poison", "e_doom": "curse", "e_silence": "curse"}

var level := 2
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _streams := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved := ConfigFile.new()
	if saved.load(SETTINGS) == OK:
		level = clampi(int(saved.get_value("audio", "level", level)), 0, LEVELS.size() - 1)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_apply_level()

func _apply_level() -> void:
	var v: float = LEVELS[level][1]
	AudioServer.set_bus_mute(0, v <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))

func set_level(value: int) -> void:
	level = clampi(value, 0, LEVELS.size() - 1)
	_apply_level()
	var saved := ConfigFile.new()
	saved.set_value("audio", "level", level)
	saved.save(SETTINGS)

func level_name() -> String:
	return LEVELS[level][0]

func play(sound: String, pitch_spread: float = 0.0) -> void:
	if level == 0:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(sound, -MIN_GAP_MS)) < MIN_GAP_MS:
		return
	_last[sound] = now
	var file := sound
	if VARIANTS.has(sound):
		file = "%s%d" % [sound, randi_range(1, VARIANTS[sound])]
	if not _streams.has(file):
		_streams[file] = load("res://assets/sfx/%s.wav" % file)
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[file]
	p.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	p.play()

func spell(sid: String) -> void:
	var s: Dictionary = Db.SPELLS.get(sid, {})
	var sound: String = SPELL_SOUNDS.get(s.get("fx", ""), _ENEMY.get(sid, ""))
	if sound == "":
		sound = "heavy_hit" if s.get("school", "") == "physical" or s.get("kind", "") == "stun" else "arcane"
	play(sound, 0.05)

## Sting of a fresh item: rarer means longer.
func loot(best_quality: int) -> void:
	if best_quality >= Items.LEGENDARY:
		play("loot_legendary")
	elif best_quality >= Items.EPIC:
		play("loot_epic")
	elif best_quality >= Items.RARE:
		play("loot_rare")
	else:
		play("loot_common")
