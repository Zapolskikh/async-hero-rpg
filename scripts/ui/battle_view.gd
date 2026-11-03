extends Control
## Draws the live battle of Game.expedition with placeholder pixel-art.
## Allies on the left (frontline nearest the centre), enemies on the right,
## mirrored. Everything here is visual only: the simulation already happened,
## the view just reacts to the events it emitted.

const UNIT_SCALE := 3.0          # 34x42 sprites -> ~102x126 on a 720px tall view
const BOSS_SCALE := 1.9          # bosses are generated at 2x already
const UNIT_GAP := 150.0          # between units of one side on a 720px tall view
const SCREEN_MARGIN := 140.0     # kept free at the screen edge and in the middle
const STATUS_ICON := 24.0
const SPELL_ICON := 24.0     # rotation icons under a hero's cast bar
const CAST_BAR_H := 16.0
const STATUS_MAX := 6            # icons per row, more would run into the neighbour
const HARMFUL_BUFFS := ["slow", "weakness", "haunt", "sunder", "mortal_wounds"]
const BUFF_ICONS := {"wall": "sp_shield_wall", "physical": "sp_battle_cry", "bloodlust": "sp_bloodlust", "rally": "sp_rally",
	"earth_shield": "sp_earth_shield", "prayer": "sp_prayer", "vengeance_charge": "sp_vengeance",
	"slow": "sp_frostbolt", "weakness": "sp_weakness", "haunt": "sp_haunt", "sunder": "sp_shatter", "mortal_wounds": "sp_mortal_strike"}
const FLOAT_LIFE := 1.1
const LUNGE_TIME := 0.28
const CHARACTER_LUNGE_TIME := .52
const HURT_TIME := 0.22
const DEATH_TIME := 1.1 # Matches the hero fall clip; the body fades during the last DEATH_FADE seconds.
const DEATH_FADE := .35
const PROJ_TIME := 0.28
const MAGIC_TIME := 0.42        # spell projectiles fly slower than arrows, so their path can be followed
const DEATH_HOLD_MAX := 1.5     # a body waits at most this long for the projectile that killed it
const MAGIC_KINDS := ["orb", "fire", "shadow", "arcane", "holy", "heal", "water", "nature", "spirit", "poison", "prism", "meteor", "frost"]
const Character := preload("res://scripts/ui/character_actor.gd")

const SPELL_COLORS := {
	"fireball": Color("#ff8a2a"), "ignite": Color("#ff5a2a"), "poison_cloud": Color("#7ccf3a"),
	"chain_lightning": Color("#8fd8ff"), "drain": Color("#c0304a"), "bash": Color("#ffe14a"),
	"kick": Color("#ffffff"), "cleave": Color("#ffffff"), "execute": Color("#ff3b3b"),
	"e_bolt": Color("#c87bff"), "e_volley": Color("#d8c08a"), "e_venom": Color("#7ccf3a"),
	"e_cataclysm": Color("#9a6aff"),
	"twin_strike": Color("#ffffff"), "mortal_strike": Color("#ff6a3b"), "whirlwind": Color("#ffffff"),
	"shield_slam": Color("#ffd75a"), "aimed_shot": Color("#d8c08a"), "arrow_rain": Color("#d8c08a"),
	"arcane_bolt": Color("#8ad0ff"),
}
const MELEE_SPELLS := ["strike", "execute", "kick", "bash", "cleave", "e_smash", "e_backstab", "e_crush",
	"twin_strike", "mortal_strike", "whirlwind", "shield_slam"]

var textures := {}
var sky: Texture2D
var ground: Texture2D

var floats: Array = []        # {text, color, uid, life, offset, size}
var anim := {}                # uid -> {lunge, hurt, dead}
var projectiles: Array = []   # {from, to, t, color, kind}
var effects: Array = []       # {pos, t, dur, kind, color, radius}
var clock := 0.0
var preview_mode := false      # embedded on the hub: show the idle party when no expedition runs
var training_sim: BattleSim = null # isolated sandbox; never replaces Game.expedition
var show_last := false             # keeps the finished battle on screen (watch layer)

func active_sim() -> BattleSim:
	if training_sim != null:
		return training_sim
	if Game.expedition != null:
		return Game.expedition.sim
	return Game.last_battle.sim if show_last and Game.last_battle != null else null
var _sim_ref: BattleSim = null
var _last_n := 0
var _preview_units: Array = []
var _preview_key := ""
var characters := {}
var animation_rate := 1.0
var pending_actions := {}
var death_hold := {}            # uid -> seconds held: the unit is dead, its killing blow is still in flight
var _pose_time := 0.
var _display_time := 0.
var _advance_origin := 0.
var _processing_time := 0.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sky = load("res://assets/bg/sky.png")
	ground = load("res://assets/bg/ground.png")

func tex(name: String) -> Texture2D:
	if name == "":
		return null
	if not textures.has(name):
		var path := "res://assets/units/%s.png" % name
		textures[name] = load(path) if ResourceLoader.exists(path) else null
	return textures[name]

func _process(delta: float) -> void:
	var dt := delta * (animation_rate if training_sim != null else Game.watch_speed)
	clock += dt
	var sim := active_sim()
	if sim != null:
		if sim != _sim_ref:
			_pose_time = 0.
			_display_time = 0.
			pending_actions.clear()
			death_hold.clear()
			for item in characters.values():
				item["actor"].play("idle")
			_sim_ref = sim
			_last_n = 0
			floats.clear()
			projectiles.clear()
			effects.clear()
			anim.clear()
			for u in sim.units:
				if u.side == 1 or not anim.has(u.uid):
					anim[u.uid] = {"lunge": 0.0, "hurt": 0.0, "dead": 0.0 if u.alive() else DEATH_TIME}
		_display_time = maxf(sim.time+sim._acc,_display_time+dt if sim.finished else 0.)
		_sync_characters(sim.units,false)
		_consume_events(sim)
		for u in sim.units:
			var a: Dictionary = _anim(u.uid)
			a["lunge"] = max(0.0, a["lunge"] - dt)
			a["hurt"] = max(0.0, a["hurt"] - dt)
			if death_hold.has(u.uid):
				death_hold[u.uid] += dt
				if death_hold[u.uid] >= DEATH_HOLD_MAX:
					_release_death(u.uid)
			elif not u.alive():
				a["dead"] = min(DEATH_TIME, a["dead"] + dt)
			else:
				a["dead"] = 0.0
	for f in floats.duplicate():
		f["life"] -= dt
		if f["life"] <= 0.0:
			floats.erase(f)
	for p in projectiles.duplicate():
		p["t"] = maxf(0.,_display_time-p["born"]) if p.has("born") else float(p["t"])+dt
		if p["t"] >= _flight(p):
			projectiles.erase(p)
			_impact(p)
			for hit in p.get("damage",[]): _show_hit(hit)
	for e in effects.duplicate():
		e["t"] += dt
		if e["t"] >= e["dur"]:
			effects.erase(e)
	_sync_characters(sim.units if sim != null else (_get_preview_units() if preview_mode else []))
	if sim == null:
		for item in characters.values(): item["actor"].advance_visual(dt)
	queue_redraw()

func _advance_characters_to(target: float) -> void:
	var amount := maxf(0.,target-_pose_time)
	_advance_origin = _pose_time
	for item in characters.values(): item["actor"].advance_visual(amount)
	_pose_time = maxf(_pose_time,target)

func _sync_characters(units: Array, synchronize_state: bool = true) -> void:
	var present := []
	for u in units:
		if u.side != 0:
			continue
		present.append(u.uid)
		var key := str(u.appearance) + str(u.look) + str(u.weapons)
		if not characters.has(u.uid):
			var actor := Character.new()
			add_child(actor)
			actor.set_process(false)
			actor.marker.connect(_on_character_marker.bind(u.uid))
			actor.action_cancelled.connect(_on_character_cancelled.bind(u.uid))
			characters[u.uid] = {"actor":actor, "key":""}
		var item: Dictionary = characters[u.uid]
		var actor: CharacterActor = item["actor"]
		if item["key"] != key:
			actor.configure(u.appearance, u.look, u.weapons)
			item["key"] = key
		var a := _anim(u.uid)
		var offset := Vector2.ZERO
		if synchronize_state:
			if u.alive():
				if actor.clip == "death":
					actor.play("idle")
				if a["lunge"] > 0.:
					offset += _lunge_offset(u,a["lunge"])
				if u.stun > 0.:
					if actor.clip != "idle": actor.play("idle")
				elif u.is_casting() and not (_sim_ref != null and _sim_ref.finished):
					var casting: Dictionary = u.casting if not u.casting.is_empty() else u.channel
					var spell: Dictionary = Db.SPELLS[casting["spell"]]
					if spell.get("weapon",false):
						if u.equipped("bow") and actor.clip != "aim_hold": actor.begin_aim()
					else:
						var color := Color(spell.get("color","#99cfff"))
						if actor.clip not in ["cast","cast_hold"] or actor.magic_color != color: _magic_motion(u,spell,true)
				elif actor.clip in ["cast","cast_hold","aim_hold"]:
					actor.cancel_cast()
			elif not death_hold.has(u.uid):
				if actor.clip != "death":
					actor.play("death")
		actor.position = _home(u) + offset
		actor.scale = Vector2.ONE * (_sprite_size(u).y / 350.)
		actor.modulate = Color(1., .55, .55) if a["hurt"] > 0. else Color.WHITE
		actor.modulate.a = 1. if u.alive() or death_hold.has(u.uid) else clampf((DEATH_TIME-float(a["dead"]))/DEATH_FADE,0.,1.)
	for id in characters.keys():
		if id not in present:
			characters[id]["actor"].queue_free()
			characters.erase(id)

func _character_animation(uid: int, clip: String, _start: float = 0.) -> void:
	if characters.has(uid): characters[uid]["actor"].play(clip)

func _lunge_offset(u: BattleUnit, remaining: float) -> Vector2:
	if u.side == 0: return Vector2.ZERO # Clips move the body over planted feet.
	return Vector2(-46.*sin(clampf(1.-remaining/LUNGE_TIME,0.,1.)*PI),0.)

func _packet(uid: int, kind: String) -> void:
	var actor: CharacterActor = characters[uid]["actor"]
	pending_actions[uid] = {"id":actor.action_serial,"kind":kind,"projectiles":[],"effects":[],"damage":[]}

func _magic_motion(src: BattleUnit, spell: Dictionary, preparing: bool) -> void:
	var actor: CharacterActor = characters[src.uid]["actor"]
	var color := Color(spell.get("color","#99cfff"))
	if src.equipped("staff") and spell.get("group","") == "arcane" and spell.get("cast",0.) > 0.:
		actor.begin_staff_magic(color,preparing)
	else:
		actor.begin_magic(color,preparing)

func _melee_motion(src: BattleUnit, shield: bool = false) -> void:
	if not characters.has(src.uid):
		_anim(src.uid)["lunge"] = LUNGE_TIME
		return
	var actor: CharacterActor = characters[src.uid]["actor"]
	if src.equipped("staff") or src.equipped("bow"):
		actor.begin_magic(Color("#ffe7a1"),false)
	else:
		actor.play("shield_bash" if shield else "attack")
	_packet(src.uid,"melee")

func _on_character_cancelled(action_id: int, uid: int) -> void:
	if not pending_actions.has(uid) or pending_actions[uid]["id"] != action_id: return
	# Damage has already been calculated by BattleSim; cancel only its pending visuals.
	for event in pending_actions[uid]["damage"]: _show_hit(event)
	pending_actions.erase(uid)

func _on_character_marker(action_id: int, event: StringName, _socket: StringName, transform: Transform2D, uid: int) -> void:
	if not pending_actions.has(uid) or pending_actions[uid]["id"] != action_id: return
	if str(event) not in ["melee_impact","offhand_impact","dual_impact","shield_impact","arrow_release","spell_release"]: return
	var packet: Dictionary = pending_actions[uid]
	pending_actions.erase(uid) # A logical action releases each visual packet exactly once.
	var origin: Vector2 = get_global_transform().affine_inverse() * transform.origin
	var released_at: float = _advance_origin + characters[uid]["actor"].rig.last_event_offset
	var assigned := []
	for projectile in packet["projectiles"]:
		projectile["from"] = origin
		projectile["t"] = 0.
		projectile["born"] = released_at
		projectile["damage"] = []
		for damage in packet["damage"]:
			if damage["uid"] == projectile["target_uid"] and damage not in assigned:
				projectile["damage"].append(damage)
				assigned.append(damage)
		projectiles.append(projectile)
	for effect in packet["effects"]: effects.append(effect)
	for damage in packet["damage"]:
		if damage not in assigned: _show_hit(damage)

## The fight on the watch screen is heard; the small preview on the hub is not.
func _heard() -> bool:
	return show_last and is_visible_in_tree()

func _hit_sound(e: Dictionary) -> void:
	if e.get("dot",false) or not _heard():
		return
	if e.get("crit",false):
		Sfx.play("crit",.04)
		return
	var sim := active_sim()
	var src: BattleUnit = sim.unit_by_uid(e.get("src",-1)) if sim != null else null
	if src == null: return
	if src.equipped("bow"): Sfx.play("arrow_hit",.08)
	elif src.equipped("greatsword") or src.is_boss: Sfx.play("heavy_hit",.06)
	elif not src.equipped("staff"): Sfx.play("sword_hit",.08)

## A hit event that waited for its projectile (or melee swing): damage, absorbed damage or the death it caused.
func _show_hit(e: Dictionary) -> void:
	match e.get("t", "dmg"):
		"absorb": _show_absorb(e)
		"death": _release_death(int(e["uid"]))
		_: _show_damage(e)

func _show_absorb(e: Dictionary) -> void:
	_float(e["uid"], "щит −%d" % roundi(float(e["v"])), Color("#9fd7ff"), 21)
	var sim := active_sim()
	if sim != null:
		var u := sim.unit_by_uid(e["uid"])
		if u != null: effects.append({"pos": _center(u), "t": 0.0, "dur": 0.4, "kind": "bubble", "color": Color("#9fd7ff"), "radius": 40.0})
	if _heard(): Sfx.play("block",.05)

func _release_death(uid: int) -> void:
	death_hold.erase(uid)
	_character_animation(uid,"death")
	var sim := active_sim()
	var fallen := sim.unit_by_uid(uid) if sim != null else null
	if _heard():
		Sfx.play("death_ally" if fallen != null and fallen.side == 0 else ("death_boss" if fallen != null and fallen.is_boss else "death_enemy"))
	_float(uid, "Пал", UI.BAD, 22)

## Attaches a hit to the visual that is about to deliver it: the attacker's pending swing or cast,
## or a projectile launched at this moment towards this target. False: show it right away.
func _hold_for_visual(e: Dictionary, source: int, target: int) -> bool:
	if source >= 0 and pending_actions.has(source):
		pending_actions[source]["damage"].append(e)
		return true
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		if int(p.get("target_uid", -1)) != target or p.get("landed", false):
			continue
		if (source < 0 or int(p.get("src_uid", -2)) == source) and (source < 0 or is_equal_approx(float(p.get("born", -1.0)), _processing_time)):
			p["damage"].append(e)
			return true
	return false

func _flight(p: Dictionary) -> float:
	return MAGIC_TIME if p.get("kind", "") in MAGIC_KINDS else PROJ_TIME

## Where a projectile lands: a burst sized and coloured by the kind of attack.
func _impact(p: Dictionary) -> void:
	var col: Color = p["color"]
	var kind: String = p.get("kind", "")
	if kind in ["arrow", "poison_arrow", "fire_arrow", "arrow_rain", "beast", "shield_throw", "blade"]:
		effects.append({"pos": p["to"], "t": 0.0, "dur": 0.25, "kind": "burst", "color": col, "radius": 18.0})
	elif kind in ["shadow", "doom"]:
		effects.append({"pos": p["to"], "t": 0.0, "dur": 0.5, "kind": "shadow_burst", "color": col, "radius": 46.0})
	elif kind in ["meteor", "fire"]:
		effects.append({"pos": p["to"], "t": 0.0, "dur": 0.45, "kind": "explosion", "color": col, "radius": 40.0})
	else:
		effects.append({"pos": p["to"], "t": 0.0, "dur": 0.4, "kind": "burst", "color": col, "radius": 34.0})
		effects.append({"pos": p["to"], "t": 0.0, "dur": 0.4, "kind": "bubble", "color": col.lightened(0.3), "radius": 30.0})

func _show_damage(e: Dictionary) -> void:
	_hit_sound(e)
	var color := Color("#ffd27a") if e.get("dot",false) else Color.WHITE
	if e.get("crit",false): color = Color("#ff7b4a")
	_float(e["uid"],str(roundi(float(e["v"])))+("!" if e.get("crit",false) else ""),color,26 if e.get("crit",false) else 20)
	if not e.get("dot",false): _anim(e["uid"])["hurt"] = HURT_TIME

func _anim(uid: int) -> Dictionary:
	if not anim.has(uid):
		anim[uid] = {"lunge": 0.0, "hurt": 0.0, "dead": 0.0}
	return anim[uid]

func _consume_events(sim: BattleSim) -> void:
	for e in sim.events:
		if e.get("n", 0) <= _last_n:
			continue
		_last_n = e.get("n", 0)
		_processing_time = float(e.get("time",sim.time))
		_advance_characters_to(_processing_time)
		match e["t"]:
			"attack":
				var src := sim.unit_by_uid(e["uid"])
				var dst := sim.unit_by_uid(e["tgt"])
				if src != null and dst != null:
					if src.equipped("bow") or src.ranged:
						if _heard() and src.equipped("bow"): Sfx.play("arrow_shot",.06)
						_shoot(src, dst, Color("#e8dcc0"), "arrow")
					elif not src.equipped("staff"):
						_melee_motion(src)
			"fx":
				_on_fx(sim,e)
			"spell":
				_on_spell(sim, e)
			"dmg":
				var source: int = e.get("src",-1)
				if e.get("dot",false) or not _hold_for_visual(e, source, int(e["uid"])): _show_damage(e)
			"heal":
				_float(e["uid"], "+%d" % e["v"], UI.GOOD, 20)
				_effect_on(sim, e["uid"], "sparkle", UI.GOOD, 0.5)
			"absorb":
				if not _hold_for_visual(e, int(e.get("src", -1)), int(e["uid"])): _show_absorb(e)
			"shield":
				_effect_on(sim, e["uid"], "bubble", Color("#8fd0ff"), 0.45)
			"interrupt":
				if characters.has(e["uid"]): characters[e["uid"]]["actor"].cancel_cast()
				_float(e["uid"], e["text"], Color("#ff5ad1"), 26)
				if _heard(): Sfx.play("interrupt")
				_effect_on(sim, e["uid"], "burst", Color("#ff5ad1"), 0.35)
			"status":
				_float(e["uid"], e["text"], Color("#c9b6ff"), 18)
				if characters.has(e["uid"]):
					var actor: CharacterActor = characters[e["uid"]]["actor"]
					if e["text"] == "Оглушён": actor.play("idle")
					elif e["text"] == "Безмолвие" and actor.clip in ["cast","cast_hold","cast_release","aim_hold"]: actor.cancel_cast()
			"cast":
				if _heard() and not Db.SPELLS.get(e.get("sid",""),{}).get("weapon",false): Sfx.play("cast_start",.05)
				if characters.has(e["uid"]):
					var spell: Dictionary = Db.SPELLS.get(e.get("sid",""),{})
					var actor: CharacterActor = characters[e["uid"]]["actor"]
					if spell.get("weapon",false) and actor.preset == "bow": actor.begin_aim()
					elif not spell.get("weapon",false): _magic_motion(sim.unit_by_uid(e["uid"]),spell,true)
			"death":
				if _hold_for_visual(e, -1, int(e["uid"])) or _held_by_packet(e):
					death_hold[int(e["uid"])] = 0.0
				else:
					_release_death(int(e["uid"]))
	if floats.size() > 60:
		floats = floats.slice(floats.size() - 60)
	_advance_characters_to(_display_time)

## A death waits for a pending swing or cast aimed at that unit (its projectile is made on release).
func _held_by_packet(e: Dictionary) -> bool:
	for uid in pending_actions:
		for hit in pending_actions[uid]["damage"]:
			if int(hit.get("uid", -1)) == int(e["uid"]):
				pending_actions[uid]["damage"].append(e)
				return true
	return false

func _on_spell(sim: BattleSim, e: Dictionary) -> void:
	var src := sim.unit_by_uid(e["uid"])
	if src == null: return
	if _heard(): Sfx.spell(e.get("sid",""))
	_float(src.uid,e["text"],UI.ACCENT,17,-44.)
	if not characters.has(src.uid): return
	var spell: Dictionary = Db.SPELLS.get(e.get("sid",""),{})
	var actor: CharacterActor = characters[src.uid]["actor"]
	if spell.get("weapon",false) and src.equipped("bow"):
		if actor.clip == "aim_hold": actor.release_aim()
		else: actor.play("shoot")
		_packet(src.uid,"bow")
	elif spell.get("fx","") in ["slash","heavy","bleed","shield_hit","whirlwind"]:
		if src.equipped("dual") and spell.get("fx","") == "whirlwind" and spell.get("kind","") == "aoe_damage":
			actor.play_native("dual_combo","idle_dual")
			_packet(src.uid,"melee")
		else:
			_melee_motion(src,spell.get("fx","") == "shield_hit")
	else:
		_magic_motion(src,spell,false)
		_packet(src.uid,"magic")

func _on_fx(sim: BattleSim, e: Dictionary) -> void:
	var src := sim.unit_by_uid(e["uid"])
	var dst := sim.unit_by_uid(e["tgt"])
	if src == null or dst == null:
		return
	var kind: String = e["kind"]
	var col := Color(e["color"])
	if kind in ["slash","heavy","bleed","shield_hit","whirlwind"]:
		if not pending_actions.has(src.uid): _melee_motion(src,kind == "shield_hit")
		_effect_on(sim,dst.uid,kind,col,.42,src.uid)
	elif kind in ["shout","shield","cleanse","curse","shockwave","explosion","nature","earth","resurrect","quake"]:
		_effect_on(sim,dst.uid,kind,col,.65,src.uid)
	elif kind == "doom":
		_put_effect(src.uid,{"pos":_center(dst),"t":0.,"dur":.6,"kind":"shadow_burst","color":col,"radius":60.})
	elif kind in ["lightning","heal_chain"]:
		_put_effect(src.uid,{"pos":_center(dst),"from":_center(src),"t":0.,"dur":.38,"kind":kind,"color":col,"radius":40.})
	else:
		if e.get("summon","") != "":
			var origin := _home(src)+Vector2(-34.,-30.)
			for i in src.summons.size():
				if src.summons[i]["id"] == e["summon"]:
					origin = _home(src) + Vector2(-34.-i*25.,-30.)
					break
			projectiles.append({"from":origin,"to":_center(dst),"t":0.,"kind":kind,"color":col,"born":_processing_time})
		else:
			if not characters.has(src.uid) and kind in MAGIC_KINDS and kind != "meteor":
				effects.append({"pos": _center(src) + Vector2(0, -10), "t": 0.0, "dur": 0.3, "kind": "burst", "color": col, "radius": 26.0})
			_shoot(src,dst,col,kind)

func _shoot(src: BattleUnit, dst: BattleUnit, col: Color, kind: String) -> void:
	var projectile := {"from":_center(src)+Vector2(0,-10),"to":_center(dst),"t":0.,"color":col,"kind":kind,"target_uid":dst.uid,"src_uid":src.uid,"born":_processing_time,"damage":[]}
	if characters.has(src.uid) and src.equipped("bow") and kind in ["arrow","poison_arrow","fire_arrow","arrow_rain"]:
		if not pending_actions.has(src.uid):
			var actor: CharacterActor = characters[src.uid]["actor"]
			if actor.clip == "aim_hold": actor.release_aim()
			else: actor.play("shoot")
			_packet(src.uid,"bow")
	if pending_actions.has(src.uid): pending_actions[src.uid]["projectiles"].append(projectile)
	else: projectiles.append(projectile)

func _put_effect(source: int, effect: Dictionary) -> void:
	if pending_actions.has(source): pending_actions[source]["effects"].append(effect)
	else: effects.append(effect)

func _effect_on(sim: BattleSim, uid: int, kind: String, col: Color, dur: float, source: int = -1) -> void:
	var u := sim.unit_by_uid(uid)
	if u == null:
		return
	_put_effect(source,{"pos": _center(u), "t": 0.0, "dur": dur, "kind": kind, "color": col, "radius": 40.0})

func _float(uid: int, text: String, col: Color, size: int, y_off: float = 0.0) -> void:
	var stack := 0
	for f in floats:
		if f["uid"] == uid and f["life"] > FLOAT_LIFE - 0.35:
			stack += 1
	floats.append({"text": text, "color": col, "uid": uid, "life": FLOAT_LIFE,
		"offset": Vector2(0, y_off - stack * 22), "size": size})

# ---------------- layout ----------------

func ground_y() -> float:
	return size.y * 0.70

## Scale factor relative to a 720px tall full-screen view.
func k() -> float:
	return clamp(size.y / 720.0, 0.5, 1.0)

func _sprite_size(u: BattleUnit) -> Vector2:
	if u.side == 0:
		return Vector2(90.,150.) * k()
	var t := tex(u.sprite)
	var sc := (BOSS_SCALE if u.is_boss else UNIT_SCALE) * k()
	if t == null:
		return Vector2(84, 112) if not u.is_boss else Vector2(120, 160)
	return t.get_size() * sc

## Spot on the ground where the unit stands (bottom-centre), without animation.
func _home(u: BattleUnit) -> Vector2:
	var mid := size.x / 2.0
	var gap := _gap(u.side)
	var depth := u.slot * 6.0 * k()   # backline stands slightly higher -> fake depth
	if u.side == 0:
		return Vector2(mid - 85.0 * k() - u.slot * gap, ground_y() - depth)
	return Vector2(mid + 85.0 * k() + u.slot * gap + (30.0 * k() if u.is_boss else 0.0), ground_y() - depth)

## Spacing of one side: wide, but a full line of units still fits on screen.
func _gap(side: int) -> float:
	var n := 0
	var battle := active_sim()
	if battle != null:
		for u in battle.units:
			if u.side == side:
				n += 1
	return min(UNIT_GAP * k(), (size.x / 2.0 - SCREEN_MARGIN * k()) / maxf(1.0, n - 1.0))

## Active effects as [icon, seconds left, or -1 when it has no end]: [helpful, harmful].
func _statuses(u: BattleUnit) -> Array:
	var good := {}
	var bad := {}
	var stacks := {}
	for id in u.buffs:
		var left: float = u.buffs[id].get("remaining", -1.0)
		if not BUFF_ICONS.has(id):
			continue
		(bad if id in HARMFUL_BUFFS else good)[BUFF_ICONS[id]] = left
	for d in u.dots:
		bad["sp_" + str(d["id"])] = maxf(bad.get("sp_" + str(d["id"]), 0.0), d["remaining"])
		stacks["sp_" + str(d["id"])] = int(stacks.get("sp_" + str(d["id"]), 0)) + 1
	for h in u.hots:
		good["sp_" + str(h["id"])] = maxf(good.get("sp_" + str(h["id"]), 0.0), h["remaining"])
		stacks["sp_" + str(h["id"])] = int(stacks.get("sp_" + str(h["id"]), 0)) + 1
	if u.shield > 0.0:
		good["sp_" + (u.shield_sid if u.shield_sid != "" else "barrier")] = u.shield_time if u.shield_time < 999.0 else -1.0
	if u.stun > 0.0:
		bad["sp_bash"] = u.stun
	if u.silence > 0.0:
		bad["sp_kick"] = u.silence
	# The same HoT or DoT from several casters: one icon with the count in its corner.
	for key in stacks:
		if int(stacks[key]) > 1:
			var row: Dictionary = good if good.has(key) else bad
			row[key] = [row[key], int(stacks[key])]
	return [good, bad]

## Row of effect icons above `top`; returns the y the next row starts from.
func _draw_status_row(effects: Dictionary, x: float, top: float, tint: Color, fallback: String, font: Font) -> float:
	if effects.is_empty():
		return top
	var side: float = STATUS_ICON * k()
	var keys: Array = effects.keys().slice(0, STATUS_MAX)
	var y := top - side - 2.0
	var left := x - keys.size() * (side + 2.0) / 2.0
	for i in keys.size():
		var box := Rect2(left + i * (side + 2.0), y, side, side)
		draw_rect(box.grow(1.5), tint)
		var icon := UI.icon_tex(keys[i])
		draw_texture_rect(icon if icon != null else UI.icon_tex(fallback), box, false)
		var value = effects[keys[i]]
		var seconds: float = float(value[0]) if value is Array else float(value)
		if seconds >= 0.0:
			_text(font, box.position + Vector2(2.0, side - 2.0), str(ceili(seconds)), 12, Color.WHITE, 3)
		if value is Array:
			var label := "×%d" % int(value[1])
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			_text(font, box.position + Vector2(side - w, 11.0), label, 13, Color("#ffe066"), 3)
	return y

func _status_height(u: BattleUnit) -> float:
	var rows := 0
	for list in _statuses(u):
		if not list.is_empty():
			rows += 1
	return rows * (STATUS_ICON * k() + 2.0)

func _center(u: BattleUnit) -> Vector2:
	return _home(u) - Vector2(0, _sprite_size(u).y * 0.5)

func unit_rect(u: BattleUnit) -> Rect2:
	var sz := _sprite_size(u)
	var h := _home(u)
	return Rect2(h - Vector2(sz.x / 2.0, sz.y), sz)

# ---------------- drawing ----------------

func _draw() -> void:
	_draw_background()
	var font := ThemeDB.fallback_font
	var ex: Expedition = Game.expedition
	var sim := active_sim()
	if sim == null:
		if preview_mode:
			for u in _get_preview_units():
				_draw_unit(u, font)
		else:
			_text(font, Vector2(40, 110), "Нет активного похода", 28, Color.WHITE)
		return
	# back to front: higher slots first so the frontline overlaps them
	var order: Array = sim.units.duplicate()
	order.sort_custom(func(a, b): return a.slot > b.slot)
	for u in order:
		if not u.alive():
			_draw_unit(u, font)
	for u in order:
		if u.alive():
			_draw_unit(u, font)
	for e in effects:
		_draw_effect(e)
	for p in projectiles:
		_draw_projectile(p)
	for f in floats:
		var u := sim.unit_by_uid(f["uid"])
		if u == null:
			continue
		var r := unit_rect(u)
		var t: float = 1.0 - f["life"] / FLOAT_LIFE
		var pos: Vector2 = Vector2(r.position.x + r.size.x / 2.0, r.position.y - 40.0 - _status_height(u)) + f["offset"] + Vector2(0, -36.0 * t)
		var col: Color = f["color"]
		col.a = clamp(f["life"] / FLOAT_LIFE * 1.6, 0.0, 1.0)
		var w := font.get_string_size(f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, f["size"]).x
		draw_string_outline(font, pos - Vector2(w / 2.0, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, f["size"], 5, Color(0, 0, 0, col.a))
		draw_string(font, pos - Vector2(w / 2.0, 0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, f["size"], col)
	if training_sim == null and ex != null and ex.pause > 0.0:
		var msg := "Волна %d / %d" % [ex.wave_index + 1, ex.total_waves()]
		var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		_text(font, Vector2(size.x / 2.0 - w / 2.0, size.y * 0.33), msg, 44, UI.ACCENT)

func _draw_background() -> void:
	var gy := ground_y()
	if sky != null:
		var sky_h := gy + 30.0
		var sky_w: float = max(size.x, sky_h * sky.get_width() / sky.get_height())
		draw_texture_rect(sky, Rect2(Vector2((size.x - sky_w) / 2.0, 0), Vector2(sky_w, sky_h)), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#cfe3ef"))
	if ground != null:
		var tile := ground.get_size() * 3.0
		var x := 0.0
		while x < size.x:
			draw_texture_rect(ground, Rect2(Vector2(x, gy - 6.0), tile), false)
			var y := gy - 6.0 + tile.y
			while y < size.y:
				draw_texture_rect_region(ground, Rect2(Vector2(x, y), tile), Rect2(Vector2(0, 8), ground.get_size() - Vector2(0, 8)))
				y += tile.y - 24.0
			x += tile.x
	else:
		draw_rect(Rect2(Vector2(0, gy), Vector2(size.x, size.y - gy)), Color("#b9a06a"))

func _draw_unit(u: BattleUnit, font: Font) -> void:
	var a: Dictionary = _anim(u.uid)
	var sz := _sprite_size(u)
	var home := _home(u)
	var dir := 1.0 if u.side == 0 else -1.0
	var offset := Vector2.ZERO
	if u.alive():
		offset.y = -abs(sin(clock * 3.0 + u.uid)) * 3.0   # idle breathing
		if a["lunge"] > 0.0:
			offset += _lunge_offset(u,a["lunge"])
		if a["hurt"] > 0.0:
			offset.x -= dir * 8.0 * (a["hurt"] / HURT_TIME)
		if _casting_shown(u):
			offset.y -= 4.0
	var t := tex(u.sprite)
	var tint := Color.WHITE
	if a["hurt"] > 0.0:
		tint = Color(1.0, 0.55, 0.55)
	if u.stun > 0.0:
		tint = tint.darkened(0.3)
	var dead_k: float = a["dead"] / DEATH_TIME if not u.alive() else 0.0
	if not u.alive():
		tint.a = lerp(1.0, 0.35, dead_k)

	# shadow
	draw_set_transform(Vector2.ZERO)
	var shadow_w := sz.x * (0.55 if not u.alive() else 0.45)
	_ellipse(home + Vector2(offset.x, 0), Vector2(shadow_w, 9), Color(0, 0, 0, 0.25))

	# cast glow under the feet
	if _casting_shown(u):
		var c: Dictionary = u.casting if not u.casting.is_empty() else u.channel
		var col: Color = Color(Db.SPELLS[c["spell"]].get("color", "#ffd27a"))
		col.a = 0.35 + 0.2 * sin(clock * 10.0)
		_ellipse(home, Vector2(sz.x * 0.55, 14), col)

	# cosmetic aura under the feet
	if u.alive() and u.cosmetics.has("aura"):
		var ac := Color(u.cosmetics["aura"])
		for i in 3:
			var ph := fmod(clock * 0.8 + i / 3.0, 1.0)
			var col := ac
			col.a = 0.8 * (1.0 - ph)
			_ellipse(home, Vector2(sz.x * (0.3 + 0.5 * ph), 9.0 + 12.0 * ph), col, false, 4.0)
		var core := ac
		core.a = 0.4 + 0.12 * sin(clock * 3.0)
		_ellipse(home, Vector2(sz.x * 0.5, 15), core)
		for i in 4:   # rising sparks
			var st := fmod(clock * 0.6 + i * 0.25, 1.0)
			var sp := ac
			sp.a = 0.9 * (1.0 - st)
			var sx := sin(i * 2.1 + clock) * sz.x * 0.35
			draw_rect(Rect2(home + Vector2(sx, -st * sz.y * 0.7), Vector2(4, 4) * k()), sp)

	if u.side != 0:
		# sprite: rotate to fall over when dead, mirror for enemies
		var pivot := home + offset
		var angle := -dir * dead_k * PI / 2.0
		draw_set_transform(pivot, angle, Vector2(dir, 1.0))
		var rect := Rect2(Vector2(-sz.x / 2.0, -sz.y), sz)
		if u.sprite == "training_dummy":
			var wood := Color("#946338") * tint
			draw_rect(Rect2(-7, -sz.y * .8, 14, sz.y * .8), wood)
			draw_rect(Rect2(-sz.x * .45, -sz.y * .64, sz.x * .9, 12), wood)
			draw_rect(Rect2(-22, -sz.y * .88, 44, 35), Color("#d0b171") * tint)
			draw_rect(Rect2(-24, -sz.y * .58, 48, 39), Color("#b99a61") * tint)
			draw_circle(Vector2(0, -sz.y * .43), 13, Color("#a34c3e") * tint)
			draw_circle(Vector2(0, -sz.y * .43), 6, Color("#e6cf9c") * tint)
			draw_rect(Rect2(-30, -8, 60, 8), wood)
		elif not u.look.is_empty():
			if u.cosmetics.has("glow") and u.alive():
				var gc := Color(u.cosmetics["glow"])
				gc.a = 0.7 + 0.25 * sin(clock * 4.0)
				for l in u.look:
					var gt := tex("doll_" + str(l[0]) + "_glow")
					if gt != null:
						draw_texture_rect(gt, rect, false, gc)
			for l in u.look:
				var lt := tex("doll_" + str(l[0]))
				if lt != null:
					draw_texture_rect(lt, rect, false, tint * (Color(l[1]) if str(l[1]) != "" else Color.WHITE))
		elif t != null:
			draw_texture_rect(t, rect, false, tint)
		else:
			draw_rect(rect, u.color * tint)
		draw_set_transform(Vector2.ZERO)

	if not u.alive() and not death_hold.has(u.uid):
		return
	var r := Rect2(home + offset - Vector2(sz.x / 2.0, sz.y), sz)
	if u.shield > 0.0:
		var sc := Color("#8fd0ff")
		sc.a = 0.35 + 0.1 * sin(clock * 4.0)
		_ellipse(r.get_center(), r.size * Vector2(0.62, 0.56), sc, false, 4.0)
	if u.taunt > 0.0:
		_text(font, Vector2(r.get_center().x - 6, r.position.y - 4), "!", 34, Color("#ff3b3b"))
	if u.stun > 0.0:
		for i in 3:
			var ang := clock * 4.0 + i * TAU / 3.0
			draw_circle(Vector2(r.get_center().x + cos(ang) * 22.0, r.position.y + 6 + sin(ang) * 6.0), 4.0, Color("#ffe14a"))
	_draw_summons(u, home)
	# HP bar and name above the unit
	var bar := Rect2(Vector2(home.x - 48, r.position.y - 22), Vector2(96, 11))
	if u.is_boss:
		var bw: float = min(160.0, _gap(u.side) - 10.0)
		bar = Rect2(Vector2(home.x - bw / 2.0, r.position.y - 22), Vector2(bw, 13))
	draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * u.hp_frac(), bar.size.y)), UI.GOOD if u.side == 0 else UI.BAD)
	if u.shield > 0.0:
		var sw: float = min(bar.size.x, bar.size.x * u.shield / u.max_hp)
		draw_rect(Rect2(bar.position + Vector2(0, bar.size.y - 4), Vector2(sw, 4)), Color("#bfe6ff"))
	var nw := font.get_string_size(u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_text(font, Vector2(home.x - nw / 2.0, bar.position.y - 5), u.name, 16, Color.WHITE, 4)
	# effects over the head: harmful next to the name, helpful above them
	if u.alive():
		var effects := _statuses(u)
		var row_top := _draw_status_row(effects[1], home.x, bar.position.y - 23.0, Color("#e0413a"), "sp_ignite", font)
		_draw_status_row(effects[0], home.x, row_top, Color("#3f8cff"), "sp_renew", font)
	# cast bar under the feet (gone once the wave is over: a cast cut off by the end is not shown)
	if _casting_shown(u):
		var c: Dictionary = u.casting if not u.casting.is_empty() else u.channel
		var cb := Rect2(Vector2(home.x - 60, home.y + 6), Vector2(120, CAST_BAR_H))
		draw_rect(cb.grow(1.5), Color(0, 0, 0, 0.8))
		var frac: float = 1.0 - c["remaining"] / c["total"]
		var col := Color("#f0a23a") if c.get("interruptible", true) else Color("#b0b0b0")
		draw_rect(Rect2(cb.position, Vector2(cb.size.x * frac, cb.size.y)), col)
		# the spell name sits inside the bar, the hero's spell icons go right under it
		var sname: String = Db.SPELLS[c["spell"]]["name"]
		var sw2 := font.get_string_size(sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_text(font, Vector2(home.x - sw2 / 2.0, cb.end.y - 3), sname, 13, Color.WHITE, 4)
	if u.alive() and u.side == 0:
		_draw_spell_row(u, home)

## The party's spells (hero and mercenaries, not enemies) under the cast bar with a WoW-style cooldown sweep: the dark sector is
## what is left (global cooldown or the spell's own one, whichever ends later), the bright
## part has recovered, a light hand marks the edge. No numbers.
func _draw_spell_row(u: BattleUnit, home: Vector2) -> void:
	var side: float = SPELL_ICON * k()
	var n := u.spells.size()
	if n == 0:
		return
	var y := home.y + 6.0 + CAST_BAR_H + 5.0
	var left := home.x - n * (side + 4.0) / 2.0 + 2.0
	var gcd_total := u.spell_interval()
	var gcd_left := maxf(0.0, u.spell_cd) if u.spell_cd > BattleUnit.RETRY_DELAY else 0.0
	for i in n:
		var e: Dictionary = u.spells[i]
		var sid: String = e["id"]
		var box := Rect2(left + i * (side + 4.0), y, side, side)
		var usable := Db.spell_usable(sid, u.weapons, u.talents)
		draw_rect(box.grow(1.5), Color(0, 0, 0, 0.85))
		var icon := UI.icon_tex(UI.spell_icon(sid))
		if icon != null:
			draw_texture_rect(icon, box, false, Color.WHITE if usable else Color(0.45, 0.45, 0.45))
		if not usable:
			continue
		var own_left: float = float(u.cooldowns.get(sid, 0.0))
		var own_total: float = maxf(0.01, Db.spell_cd(sid, int(e.get("lvl", 1))))
		var frac := 0.0   # share still left
		if own_left > gcd_left and own_left > 0.0:
			frac = clampf(own_left / own_total, 0.0, 1.0)
		elif gcd_left > 0.0 and not _reactive(sid):
			frac = clampf(gcd_left / maxf(0.01, gcd_total), 0.0, 1.0)
		if frac > 0.0:
			_draw_sweep(box, frac)

func _casting_shown(u: BattleUnit) -> bool:
	return u.is_casting() and not (_sim_ref != null and _sim_ref.finished)

## Interrupts, taunts and emergency answers are not held by the global cooldown.
func _reactive(sid: String) -> bool:
	var s: Dictionary = Db.SPELLS[sid]
	return s["kind"] in ["interrupt", "taunt", "suppress"] or s.get("reactive", false)

func _draw_sweep(box: Rect2, left_frac: float) -> void:
	var c := box.get_center()
	var r := box.size.length()
	# Recovered part runs clockwise from 12 o'clock; the rest stays dark.
	var start := -PI / 2.0 + (1.0 - left_frac) * TAU
	var stop := -PI / 2.0 + TAU
	var pts := PackedVector2Array([c])
	var steps := maxi(2, int(ceil(left_frac * 32.0)))
	for i in steps + 1:
		var a := lerpf(start, stop, float(i) / steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var square := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	for poly in Geometry2D.intersect_polygons(pts, square):
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(0, 0, 0, 0.66))
	var hand := c + Vector2(cos(start), sin(start)) * r
	var clipped := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([c, hand]), square)
	if not clipped.is_empty() and clipped[0].size() >= 2:
		draw_line(clipped[0][0], clipped[0][1], Color(1, 0.95, 0.75, 0.9), 1.5, true)

func _draw_projectile(p: Dictionary) -> void:
	if p["t"] < 0.:
		return
	var k: float = minf(1.0, p["t"] / _flight(p))
	var from: Vector2 = p["from"]
	var to: Vector2 = p["to"]
	var arc := 30.0 if p["kind"] not in MAGIC_KINDS else 14.0
	var pos := from.lerp(to, k) + Vector2(0, -sin(k * PI) * arc)
	if p["kind"] in ["arrow_rain", "meteor"]:
		from = to + Vector2(-35 if p["kind"] == "arrow_rain" else -90,-170 if p["kind"] == "arrow_rain" else -300)
		pos = from.lerp(to,k)
	var col: Color = p["color"]
	if p["kind"] in ["arrow","poison_arrow","fire_arrow","arrow_rain"]:
		var d := (to - from).normalized()
		draw_line(pos - d * 16.0, pos, Color("#6a4a2a"), 3.0)
		draw_line(pos - d * 4.0, pos, col, 4.0)
	elif p["kind"] == "beast":
		draw_rect(Rect2(pos+Vector2(-14,-7),Vector2(23,12)),Color("#986947"))
		draw_rect(Rect2(pos+Vector2(6,-13),Vector2(12,13)),Color("#c99b69"))
		draw_rect(Rect2(pos+Vector2(13,-10),Vector2(3,3)),Color("#ffe2a0"))
	elif p["kind"] in ["shield_throw","blade"]:
		draw_set_transform(pos, k * TAU * 2.)
		draw_rect(Rect2(-10,-10,20,20),Color("#252a3b"))
		draw_rect(Rect2(-7,-7,14,14),col)
		draw_line(Vector2(-4,0),Vector2(4,0),Color.WHITE,3.)
		draw_set_transform(Vector2.ZERO)
	elif p["kind"] == "shadow":
		# dark bolt: a black core in a purple flame with a curling smoky trail
		var dir := (to - from).normalized()
		var side := Vector2(-dir.y, dir.x)
		for i in 7:
			var back := pos - dir * (i * 9.0) + side * sin(clock * 18.0 + i) * (2.0 + i * 1.5)
			draw_circle(back, 11.0 - i * 1.3, Color(col, 0.55 - i * 0.07))
		draw_circle(pos, 18.0, Color(col, 0.3))
		draw_circle(pos, 13.0, col)
		draw_circle(pos, 6.0, Color("#1a0a24"))
		for i in 3:
			var ang := clock * 9.0 + i * TAU / 3.0
			draw_circle(pos + Vector2(cos(ang), sin(ang)) * 14.0, 2.5, col.lightened(0.4))
	elif p["kind"] == "meteor":
		var dir := (to - from).normalized()
		for i in 8:
			draw_circle(pos - dir * (i * 12.0), 16.0 - i * 1.7, Color(col.lerp(Color("#ff9a3a"), i / 8.0), 0.6 - i * 0.07))
		draw_circle(pos, 15.0, col)
		draw_circle(pos, 7.0, Color("#fff0c0"))
	elif p["kind"] == "poison":
		for i in 5:
			var tk: float = max(0.0, k - i * 0.05)
			var tp := from.lerp(to, tk) + Vector2(sin(i * 2.3) * 5.0, -sin(tk * PI) * arc)
			draw_circle(tp, 9.0 - i * 1.4, Color(col, 0.6 - i * 0.1))
		draw_circle(pos, 10.0, col)
		draw_circle(pos + Vector2(-3, -3), 3.0, col.lightened(0.6))
	elif p["kind"] == "frost":
		var dir := (to-from).normalized()
		for i in 4:
			var center := pos-dir*i*8.
			draw_colored_polygon(PackedVector2Array([center+Vector2(0,-7),center+dir*9.,center+Vector2(0,7),center-dir*6.]),Color(col,1.-i*.18))
	else:
		# a glowing orb with a trail: fire, arcane, holy, healing and the rest of the magic
		var big := 1.6 if p["kind"] in MAGIC_KINDS else 1.0
		draw_circle(pos, 14.0 * big, Color(col, 0.25))
		for i in 6:
			var tk: float = max(0.0, k - i * 0.05)
			var tp := from.lerp(to, tk) + Vector2(0, -sin(tk * PI) * arc)
			var tc := col
			tc.a = 0.55 - i * 0.09
			draw_circle(tp, (8.0 - i * 1.1) * big, tc)
		draw_circle(pos, 8.0 * big, col)
		draw_circle(pos, 4.0 * big, col.lightened(0.6))

func _draw_effect(e: Dictionary) -> void:
	var k: float = e["t"] / e["dur"]
	var col: Color = e["color"]
	col.a = 1.0 - k
	var pos: Vector2 = e["pos"]
	match e["kind"]:
		"lightning", "heal_chain":
			var start: Vector2 = e["from"]
			var points := PackedVector2Array()
			for i in 9:
				var p := start.lerp(pos,i/8.)
				if i > 0 and i < 8:
					p.y += sin(i*17.+floor(k*8.))*14.
				points.append(p)
			draw_polyline(points,col,5.)
			draw_polyline(points,Color(1,1,1,col.a),2.)
		"shockwave", "shout":
			_ellipse(pos+Vector2(0,35),Vector2(15.+k*100.,6.+k*24.),col,false,4.)
			_ellipse(pos+Vector2(0,35),Vector2(8.+k*65.,4.+k*16.),col,false,2.)
		"shield", "earth":
			_ellipse(pos,Vector2(35.+k*12.,48.+k*12.),col,false,4.)
		"explosion":
			for i in 12:
				var angle := i*TAU/12.
				var p := pos+Vector2(cos(angle),sin(angle))*(12.+k*65.)
				draw_rect(Rect2(p,Vector2(10,10)*(1.-k)+Vector2(2,2)),col)
			draw_arc(pos,10.+k*55.,0.,TAU,20,col,3.)
		"heavy", "shield_hit", "bleed":
			draw_line(pos+Vector2(-25,-30),pos+Vector2(25,30),col,8.*(1.-k)+1.)
			for i in 5:
				var p := pos+Vector2((i-2)*10.*k,-20.+k*55.)
				draw_rect(Rect2(p,Vector2(5,5)),col)
		"whirlwind":
			for i in 3:
				draw_arc(pos,30.+i*9.,k*TAU+i,k*TAU+i+PI,16,col,4.)
		"curse":
			draw_arc(pos,28.,-k*TAU,PI-k*TAU,16,col,3.)
			draw_line(pos+Vector2(-14,-14),pos+Vector2(14,14),col,3.)
			draw_line(pos+Vector2(14,-14),pos+Vector2(-14,14),col,3.)
		"cleanse", "nature", "resurrect":
			for i in 6:
				var p := pos+Vector2((i-2.5)*12.,30.-k*100.+sin(i)*15.)
				draw_rect(Rect2(p-Vector2(2,6),Vector2(4,12)),col)
				draw_rect(Rect2(p-Vector2(6,2),Vector2(12,4)),col)
		"shadow_burst":
			var r: float = e["radius"]
			draw_circle(pos, 8.0 + k * r, Color(Color("#1a0a24"), (1.0 - k) * 0.55))
			draw_arc(pos, 8.0 + k * r, 0.0, TAU, 24, col, 4.0)
			for i in 8:
				var ang := i * TAU / 8.0 + k * 1.5
				var p := pos + Vector2(cos(ang), sin(ang)) * (10.0 + k * r * 1.1)
				draw_circle(p, 5.0 * (1.0 - k) + 1.0, col)
		"quake":
			for i in 3:
				var w := 20.0 + k * 90.0 + i * 12.0
				draw_line(pos + Vector2(-w, 48 + i * 4), pos + Vector2(w, 48 + i * 4), col, 3.0)
			for i in 6:
				var p := pos + Vector2((i - 2.5) * 22.0, 40.0 - sin(k * PI) * (16.0 + (i % 3) * 8.0))
				draw_rect(Rect2(p, Vector2(8, 8)), col.darkened(0.3))
		"burst":
			draw_circle(pos, 6.0 + k * e["radius"], Color(col, (1.0 - k) * 0.5))
			draw_arc(pos, 6.0 + k * e["radius"], 0.0, TAU, 20, col, 3.0)
		"ring":
			draw_arc(pos + Vector2(0, 40), 20.0 + k * 50.0, 0.0, TAU, 28, col, 4.0)
		"bubble":
			draw_arc(pos, 30.0 + k * 20.0, 0.0, TAU, 28, col, 5.0 * (1.0 - k) + 1.0)
		"sparkle":
			for i in 6:
				var ang := i * TAU / 6.0 + k * 2.0
				var p := pos + Vector2(cos(ang) * 26.0, sin(ang) * 30.0 - k * 40.0)
				draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), col)
		"slash":
			var a0 := -0.9 + k * 0.4
			draw_arc(pos, 34.0, a0, a0 + 1.8, 14, col, 5.0 * (1.0 - k) + 1.0)

func _ellipse(center: Vector2, radii: Vector2, col: Color, filled: bool = true, width: float = 2.0) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var ang := i * TAU / 24.0
		pts.append(center + Vector2(cos(ang) * radii.x, sin(ang) * radii.y))
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, width)

func _text(font: Font, pos: Vector2, text: String, size_px: int, col: Color, outline: int = 6) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, outline, Color(0, 0, 0, col.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)

func _get_preview_units() -> Array:
	var snaps: Array = Game.party_snapshots()
	var key := str(snaps)
	if key != _preview_key:
		_preview_key = key
		_preview_units.clear()
		for i in snaps.size():
			Roster.ensure_visuals(snaps[i])
			_preview_units.append(BattleUnit.new(i, 0, i, snaps[i]))
	return _preview_units

func _draw_summons(u: BattleUnit, home: Vector2) -> void:
	for i in u.summons.size():
		var summon: Dictionary = u.summons[i]
		var pos := home + Vector2(-34.-i*25.,0.)
		var col := Color("#8ee6ae") if summon["id"] == "healing_totem" else Color("#ff9c42")
		if summon["id"] == "beast":
			pos.x += sin(clock*6.)*5.
			draw_rect(Rect2(pos+Vector2(-15,-19),Vector2(26,12)),Color("#986947"))
			draw_rect(Rect2(pos+Vector2(7,-26),Vector2(13,15)),Color("#c99b69"))
			draw_rect(Rect2(pos+Vector2(9,-31),Vector2(5,8)),Color("#986947"))
			draw_rect(Rect2(pos+Vector2(15,-23),Vector2(3,3)),Color("#ffe2a0"))
			for leg in 2:
				draw_rect(Rect2(pos+Vector2(-10+leg*17,-8),Vector2(5,8)),Color("#67462f"))
		else:
			draw_rect(Rect2(pos+Vector2(-7,-28),Vector2(14,28)),Color("#79583e"))
			draw_rect(Rect2(pos+Vector2(-11,-23),Vector2(22,6)),col.darkened(.35))
			draw_rect(Rect2(pos+Vector2(-6,-33),Vector2(12,10)),col)
			draw_rect(Rect2(pos+Vector2(-2,-31),Vector2(4,5)),Color.WHITE)
			_ellipse(pos+Vector2(0,-30),Vector2(13,9),Color(col,.3+.2*sin(clock*5.)))
