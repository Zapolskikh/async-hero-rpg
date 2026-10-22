class_name BattleUnit
extends RefCounted
## One combatant inside BattleSim. Pure data, no nodes.

const ATTACK_INTERVAL := 1.6   # base seconds between basic attacks
const SPELL_INTERVAL := 3.2    # base seconds between rotation steps
const RETRY_DELAY := 0.4       # if no rotation spell is valid, look again this soon

var uid: int
var side: int            # 0 = allies (left), 1 = enemies (right)
var slot: int            # 0 = frontline ... 3 = backline
var name: String
var color: Color = Color.WHITE
var is_boss := false
var is_npc := false
var target_rule := "front"
var sprite := ""         # visual only: assets/units/<sprite>.png
var ranged := false      # visual only: shoots instead of stepping forward

var max_hp: float
var hp: float
var atk: float
var power: float
var armor: float
var haste: float
var crit: float

var spells: Array = []   # [{id, lvl}] in rotation order
var rot_index := 0
var cooldowns := {}      # spell id -> seconds left

var attack_cd := 0.0
var spell_cd := 0.0
var casting := {}        # {spell, lvl, remaining, total, target}
var shield := 0.0
var shield_time := 0.0
var stun := 0.0
var taunt := 0.0
var dots: Array = []     # [{id, per_tick, remaining, tick}]
var hots: Array = []

# Stats for the after-battle summary.
var dealt := 0.0
var healed := 0.0

func _init(p_uid: int, p_side: int, p_slot: int, snap: Dictionary) -> void:
	uid = p_uid
	side = p_side
	slot = p_slot
	name = snap.get("name", "?")
	color = Color(snap.get("color", "#ffffff"))
	is_boss = snap.get("boss", false)
	is_npc = snap.get("npc", false)
	target_rule = snap.get("target", "front")
	sprite = snap.get("sprite", "")
	ranged = snap.get("ranged", false)
	var st: Dictionary = snap["stats"]
	max_hp = st["hp"]
	hp = max_hp
	atk = st["atk"]
	power = st["power"]
	armor = st.get("armor", 0.0)
	haste = st.get("haste", 0.0)
	crit = st.get("crit", 0.0)
	spells = snap.get("spells", []).duplicate(true)

func alive() -> bool:
	return hp > 0.0

func hp_frac() -> float:
	return hp / max_hp

func is_casting() -> bool:
	return not casting.is_empty()

func has_dot(id: String) -> bool:
	for d in dots:
		if d["id"] == id:
			return true
	return false

func has_hot(id: String) -> bool:
	for h in hots:
		if h["id"] == id:
			return true
	return false

func is_debuffed() -> bool:
	return dots.size() > 0 or stun > 0.0

func attack_interval() -> float:
	return ATTACK_INTERVAL / (1.0 + haste)

func spell_interval() -> float:
	return SPELL_INTERVAL / (1.0 + haste)
