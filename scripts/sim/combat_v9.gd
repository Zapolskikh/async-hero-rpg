class_name CombatV9
extends RefCounted
## The same seeded rules drive client, offline simulation and server workers.
const STEP := 0.1
const ENRAGE_DAMAGE := 1.8  # A boss still alive at its enrage timer hits this much harder.
const ENRAGE_HASTE := .4
const TIME_LIMIT := 150.0
const DOT_TICK := 1.0
var rng := RandomNumberGenerator.new()
var units: Array = []
var time := 0.0
var finished := false
var won := false
var end_reason := ""
var record_events := true
var events: Array = []
var event_seq := 0
var _acc := 0.0
var taunt_seq := 0

func setup(allies: Array, enemy_snaps: Array, seed_value: int) -> void:
	rng.seed = seed_value
	units = allies.duplicate()
	var uid := 0
	for u in allies:
		uid = maxi(uid, u.uid + 1)
	for i in enemy_snaps.size():
		units.append(BattleUnit.new(uid + i, 1, i, enemy_snaps[i]))
	for u in units:
		u.casting.clear()
		u.channel.clear()
		u.cooldowns.clear()
		u.summons.clear()
		u.counters.clear()
		u.damage_history.clear()
		if u.buffs.has("rally"):
			u.max_hp -= u.buffs["rally"]["amount"]
			u.hp = minf(u.hp,u.max_hp)
		u.buffs.clear()
		u.taunt = 0.
		u.taunt_order = -1
		u.silence = 0.
		u.attack_cd = rng.randf_range(.1, .6)
		u.spell_cd = rng.randf_range(.5, 1.2)
		if not u.alive():
			continue
		if u.rank("readiness"):
			_shield(u,u,u.max_hp*.05*u.rank("readiness"),12.,"readiness")
		if u.rank("fire_totem"):
			_summon(u,"fire_totem",999.,u.power*(.2+.2*u.rank("fire_totem")),3.)
		if u.rank("healing_totem"):
			_summon(u,"healing_totem",999.,u.power*(.1+.1*u.rank("healing_totem")),3.)
	for u in units:
		if u.alive() and u.rank("opening_silence"):
			for f in foes_of(u):
				_silence(f,5.)

func advance(dt: float) -> void:
	_acc += dt
	while _acc >= STEP and not finished:
		_acc -= STEP
		step()

func run_to_end() -> void:
	record_events = false
	while not finished:
		step()

func step() -> void:
	if finished:
		return
	time += STEP
	for u in units:
		if u.alive():
			_tick(u)
	for u in units:
		if u.alive():
			_act(u)
	_check_end()

func side_units(side: int) -> Array:
	return units.filter(func(u): return u.side == side and u.alive())

func foes_of(u: BattleUnit) -> Array:
	return side_units(1-u.side)

func friends_of(u: BattleUnit) -> Array:
	return side_units(u.side)

func unit_by_uid(id: int) -> BattleUnit:
	for u in units:
		if u.uid == id:
			return u
	return null

func pick_target(u: BattleUnit, rule: String = "") -> BattleUnit:
	var foes := foes_of(u)
	if foes.is_empty():
		return null
	var latest: BattleUnit = foes[0]
	for f in foes:
		if f.taunt_order > latest.taunt_order:
			latest = f
	if latest.taunt > 0.:
		return latest
	if rule == "":
		rule = "weak" if u.equipped("bow") and u.rank("weak_hunt") else u.target_rule
	if rule == "random":
		return foes[rng.randi_range(0,foes.size()-1)]
	var best: BattleUnit = foes[0]
	for f in foes:
		if (rule == "back" and f.slot > best.slot) or (rule == "weak" and f.hp_frac() < best.hp_frac()) or (rule == "front" and f.slot < best.slot):
			best = f
	return best

func _injured(u: BattleUnit, threshold: float = 1., exclude = null) -> BattleUnit:
	var best: BattleUnit = null
	for f in friends_of(u):
		if f != exclude and f.hp_frac() < threshold and (best == null or f.hp_frac() < best.hp_frac()):
			best = f
	return best

func _tick(u: BattleUnit) -> void:
	u.stun = maxf(0.,u.stun-STEP)
	u.silence = maxf(0.,u.silence-STEP)
	u.taunt = maxf(0.,u.taunt-STEP)
	for id in u.cooldowns.keys():
		u.cooldowns[id] -= STEP
		if u.cooldowns[id] <= 0.:
			u.cooldowns.erase(id)
	for id in u.buffs.keys():
		var b: Dictionary = u.buffs[id]
		b["remaining"] -= STEP
		if b["remaining"] <= 0.:
			u.buffs.erase(id)
			if id == "rally":
				u.max_hp -= b["amount"]
				u.hp = minf(u.hp,u.max_hp)
			elif id == "haunt":
				_heal(b["src"],b["src"],b["heal"],false,"haunt")
			elif id == "vengeance_charge":
				u.shield = maxf(0.,u.shield-b["left"])
				_vengeance_burst(u,b)
	if u.regen > 0.:
		u.hp = minf(u.max_hp,u.hp+u.max_hp*u.regen*STEP)
	if u.stats.get("enrage",0.) > 0. and not u.counters.has("enraged"):
		u.counters["age"] = u.counters.get("age",0.)+STEP
		if u.counters["age"] >= u.stats["enrage"]:
			u.counters["enraged"] = true
			u.dmg_mult *= ENRAGE_DAMAGE
			u.haste += ENRAGE_HASTE
			_status(u,"Ярость")
			_fx(u,u,"shout","#ff4a2a")
	if u.shield > 0.:
		u.shield_time -= STEP
		if u.shield_time <= 0.:
			_break_shield(u)
	for d in u.dots.duplicate():
		if not u.dots.has(d):
			continue
		d["remaining"] -= STEP
		d["tick"] -= STEP
		if d["tick"] <= 0. and u.alive():
			d["tick"] += 1.
			_deal(d["src"],u,d["per_tick"],false,true,d["id"],true,d["school"])
			if d["spell_dot"]:
				d["src"].spell_cd = maxf(0.,d["src"].spell_cd-.1*d["src"].rank("flame_feed"))
		if d["remaining"] <= 0. and u.dots.has(d):
			u.dots.erase(d)
			_explode_dot(d,u)
	for h in u.hots.duplicate():
		h["remaining"] -= STEP
		h["tick"] -= STEP
		if h["tick"] <= 0. and u.alive():
			h["tick"] += 1.
			var a: float = h["per_tick"]
			if h.get("decay",false):
				a *= .5+maxf(0.,h["remaining"])/h["duration"]
			_hot_tick(h["src"],u,a,h["id"])
		if h["remaining"] <= 0.:
			u.hots.erase(h)
	for s in u.summons.duplicate():
		s["remaining"] -= STEP
		s["tick"] -= STEP
		if s["tick"] <= 0.:
			s["tick"] += s["interval"]
			var t := _injured(u) if s["id"] == "healing_totem" else pick_target(u)
			if t != null:
				if s["id"] == "healing_totem":
					_heal(u,t,s["amount"],false,"heal")
					_fx(u,t,"heal","#86efa2",s["id"])
				else:
					_deal(u,t,s["amount"],false,false,"beast" if s["id"] == "beast" else "fireball",true,"physical" if s["id"] == "beast" else "magic",false)
					_fx(u,t,"beast" if s["id"] == "beast" else "fire","#edb45b",s["id"])
		if s["remaining"] <= 0.:
			u.summons.erase(s)
	for id in ["seed","explosive"]:
		if u.counters.has(id):
			u.counters[id]["remaining"] -= STEP
			if u.counters[id]["remaining"] <= 0.:
				_detonate(u,id)
	if u.rank("resurrection") and not u.spent.has("resurrection"):
		for f in units:
			if f.side == u.side and f != u and not f.alive():
				u.spent["resurrection"] = true
				f.hp = f.max_hp*.5
				f.counters.erase("death_done")
				_status(f,"Воскрешение")
				_fx(u,f,"resurrect","#fff0bb")
				break

func _act(u: BattleUnit) -> void:
	if u.stun > 0.:
		return
	if not u.channel.is_empty():
		if u.silence > 0.:
			u.channel.clear()
			return
		var c: Dictionary = u.channel
		c["tick"] -= STEP
		c["remaining"] -= STEP
		if c["tick"] <= 0.:
			c["tick"] += c["interval"]
			_channel_pulse(u,c)
			c["left"] -= 1
			if c["left"] <= 0:
				u.channel.clear()
		return
	if not u.casting.is_empty():
		if u.silence > 0.:
			u.casting.clear()
			return
		u.casting["remaining"] -= STEP
		if u.casting["remaining"] <= 0.:
			var c: Dictionary = u.casting.duplicate()
			u.casting.clear()
			var t = c["target"]
			if not t.alive():
				t = _find_spell_target(u,c["spell"],c.get("threshold",-1.))
			if t != null:
				_cast(u,c["spell"],c["lvl"],t)
		return
	if u.silence <= 0.:
		# Taunt uses its own cooldown rather than waiting for a rotation turn.
		for e in u.spells:
			if Db.SPELLS[e["id"]]["kind"] == "taunt" and not u.cooldowns.has(e["id"]):
				u.cooldowns[e["id"]] = Db.SPELLS[e["id"]]["cd"]
				_cast(u,e["id"],e.get("lvl",1),u)
				return
		for e in u.spells:
			var s: Dictionary = Db.SPELLS[e["id"]]
			if (s["kind"] == "interrupt" or s.get("reactive",false)) and not u.cooldowns.has(e["id"]) and _usable(u,e["id"]):
				for f in foes_of(u):
					if _interruptible(f):
						u.cooldowns[e["id"]] = s["cd"]
						_cast(u,e["id"],e.get("lvl",1),f)
						return
		if u.rank("emergency") and not u.cooldowns.has("emergency"):
			var f := _injured(u,.25)
			if f != null:
				for e in u.spells:
					if Db.SPELLS[e["id"]]["kind"] == "heal" and not u.cooldowns.has(e["id"]):
						u.cooldowns["emergency"] = 30.-5.*u.rank("emergency")
						_cast(u,e["id"],e.get("lvl",1),f)
						return
	u.spell_cd -= STEP
	if u.spell_cd <= 0. and u.silence <= 0. and not u.spells.is_empty():
		if _try_rotation(u):
			u.spell_cd = u.spell_interval()
			return
		u.spell_cd = BattleUnit.RETRY_DELAY
	if u.atk <= 0.:
		return
	u.attack_cd -= STEP
	if u.attack_cd <= 0.:
		u.attack_cd = u.attack_interval()
		var t := pick_target(u)
		if t != null:
			_autoattack(u,t)

func _autoattack(u: BattleUnit,t: BattleUnit) -> void:
	_emit({"t":"attack","uid":u.uid,"tgt":t.uid})
	var a: float = u.atk*rng.randf_range(.9,1.1)
	var offhand := minf(a,u.offhand_atk) if u.equipped("dual") else 0.
	_deal(u,t,a-offhand,true,false,"attack")
	if offhand > 0.:
		_deal(u,t,offhand,true,false,"attack")
	if u.gear_fx.has("double_attack") and rng.randf() < u.gear_fx["double_attack"]:
		_deal(u,t,a,true,false,"attack",true)
	for id in u.cooldowns:
		if Db.SPELLS.has(id):
			u.cooldowns[id] = maxf(0.,u.cooldowns[id]-.1*u.rank("battle_rhythm")*(2. if offhand > 0. else 1.))
	if u.rank("sunder"):
		_buff(t,"sunder",.1*u.rank("sunder"),6.,u)
	if u.equipped("sword") and rng.randf() < .05*u.rank("stunning_hit"):
		_stun(t,1.)
	if u.equipped("greatsword"):
		if rng.randf() < .1*u.rank("unstoppable"):
			_deal(u,t,a*.5,true,false,"attack",true)
		if u.rank("wide_swing"):
			for other in foes_of(u):
				if other != t:
					_deal(u,other,a*.15*u.rank("wide_swing"),false,false,"attack",true)
					break
	if u.equipped("dual") and rng.randf() < .2*u.rank("paired_blades"):
		_deal(u,t,a*.5,true,false,"attack",true)
		_poison(u,t)

func _usable(u: BattleUnit,sid: String) -> bool:
	return Db.spell_usable(sid,u.weapons) or (sid == "execute" and u.equipped("bow") and u.rank("kill_shot") > 0) or (Db.SPELLS[sid].get("req",[]).has("bow") and u.equipped("sword") and u.rank("throwing") > 0)

func _try_rotation(u: BattleUnit) -> bool:
	for idx in u.spells.size():
		var e: Dictionary = u.spells[idx]
		var sid: String = e["id"]
		if u.cooldowns.has(sid):
			continue
		var t = _find_spell_target(u,sid,e.get("threshold",-1.))
		if t == null:
			continue
		var s: Dictionary = Db.SPELLS[sid]
		u.rot_index = idx
		if s.get("cd",0.) > 0. and not (u.gear_fx.has("cd_refund") and rng.randf() < u.gear_fx["cd_refund"]):
			u.cooldowns[sid] = s["cd"]
		var duration: float = s.get("cast",0.)
		if not s.get("weapon",false):
			duration *= 1.-.03*u.rank("fast_cast")-u.gear_fx.get("cast_speed",0.)
			if s["kind"] in ["heal","chain_heal"]:
				duration *= 1.-.05*u.rank("steady_hand")
			if duration > 0. and u.counters.get("instant",false):
				u.counters.erase("instant")
				duration = 0.
		duration /= 1.+u.haste+u.buff("bloodlust")
		if duration > 0.:
			u.casting = {"spell":sid,"lvl":e.get("lvl",1),"remaining":duration,"total":duration,"target":t,"interruptible":s.get("interruptible",true),"threshold":e.get("threshold",-1.)}
			_emit({"t":"cast","uid":u.uid,"text":s["name"],"sid":sid})
		else:
			_cast(u,sid,e.get("lvl",1),t)
		return true
	return false

func _find_spell_target(u: BattleUnit,sid: String,thr: float = -1.):
	if not Db.SPELLS.has(sid) or not _usable(u,sid) or foes_of(u).is_empty():
		return null
	var s: Dictionary = Db.SPELLS[sid]
	var threshold: float = thr if thr > 0. else s.get("threshold",.7)
	match s["kind"]:
		"heal","riptide","chain_heal":
			return _injured(u,threshold)
		"hot","hot_all":
			for f in friends_of(u):
				if f.hp_frac() < threshold and not f.has_hot(sid):
					return u if s["kind"] == "hot_all" else f
			return null
		"shield":
			for f in friends_of(u):
				if f.shield <= 0.:
					return f
			return null
		"earth_shield","prayer":
			for f in friends_of(u):
				if f.buffs.has(sid) and f.buffs[sid]["src"] == u:
					return null
			return friends_of(u)[0]
		"cleanse":
			for f in friends_of(u):
				if _debuffed(f):
					return f
			return null
		"purge":
			for f in foes_of(u):
				if _positive(f):
					return f
			return null
		"mass_dispel":
			for f in friends_of(u):
				if _debuffed(f):
					return u
			for f in foes_of(u):
				if _positive(f):
					return u
			return null
		"interrupt":
			for f in foes_of(u):
				if _interruptible(f):
					return f
			return null
		"stun":
			for f in foes_of(u):
				if _interruptible(f):
					return f
			for f in foes_of(u):
				if not f.is_boss and f.stun <= 0.:
					return f
			if sid == "shield_slam":
				return pick_target(u)
			return null
		"execute":
			var target := pick_target(u)
			if target.hp_frac() < s.get("threshold",.3):
				return target
			for f in foes_of(u):
				if f.hp_frac() < s.get("threshold",.3):
					return f
			return null
		"dot":
			var target := pick_target(u)
			if _own_dot(target,u,sid) == null:
				return target
			if u.equipped("bow") and u.rank("weak_hunt"):
				return null
			for f in foes_of(u):
				if _own_dot(f,u,sid) == null:
					return f
			return null
		"debuff":
			for f in foes_of(u):
				if not f.buffs.has(s["debuff"]) or f.buffs[s["debuff"]]["remaining"] <= 2.:
					return f
			return null
		"seed","explosive":
			if u.equipped("bow") and u.rank("weak_hunt"):
				var target := pick_target(u)
				return target if not target.counters.has(s["kind"]) else null
			for f in foes_of(u):
				if not f.counters.has(s["kind"]):
					return f
			return null
		"buff_all","buff_self","rally":
			return u if not u.buffs.has(s.get("buff","rally")) else null
		"self_shield":
			return u if u.shield <= 0. else null
		"shield_all":
			for f in friends_of(u):
				if f.shield <= 0.:
					return u
			return null
		"taunt","summon","aoe_damage","aoe_dot","channel_aoe":
			return u
		"penance":
			var f := _injured(u,threshold)
			return f if f != null else pick_target(u)
	return pick_target(u)

func _amount(u: BattleUnit,sid: String,lvl: int) -> float:
	var st := u.stats.duplicate()
	if sid == "execute" and u.equipped("bow"):
		st["str"] = st.get("agi",u.power)
	if Db.SPELLS[sid].get("req",[]).has("bow") and not u.equipped("bow") and u.equipped("sword"):
		st["agi"] = st.get("str",u.power)
		return Db.spell_amount(sid,lvl,st,u.weapons)*(.4+.2*u.rank("throwing"))
	return Db.spell_amount(sid,lvl,st,u.weapons)

func _cast(u: BattleUnit,sid: String,lvl: int,target,scale: float = 1.,copy: bool = false,fixed_amount: float = -1.) -> void:
	var s: Dictionary = Db.SPELLS[sid]
	var a := _amount(u,sid,lvl)*scale
	if fixed_amount >= 0.:
		a = fixed_amount
	if not copy and target.side != u.side and s.get("school","magic") == "magic" and s["kind"] in ["damage","dot","seed","explosive","debuff","drain"]:
		for protector in friends_of(target):
			if protector != target and rng.randf() < .1*protector.rank("intercept"):
				target = protector
				_status(target,"Перехват")
				break
		if rng.randf() < .1*target.rank("reflection"):
			_status(target,"Отражено")
			_cast(target,sid,lvl,u,scale,true,a)
			return
	_emit({"t":"spell","uid":u.uid,"text":s["name"],"sid":sid,"kind":s["kind"],"tgt":target.uid})
	if s.has("channel") and not copy:
		var duration: float = s["channel"]/(1.+u.haste+u.buff("bloodlust"))
		u.channel = {"spell":sid,"amount":a,"target":target,"left":s["pulses"],"interval":duration/maxf(1.,s["pulses"]-1.),"tick":0.,"remaining":duration,"total":duration,"interruptible":true}
		return
	match s["kind"]:
		"damage","execute","interrupt","stun","drain":
			if s["kind"] in ["interrupt","stun"]:
				var interrupted := _interrupt(u,target)
				if interrupted and sid == "shield_slam" and u.rank("caster_punish"):
					a += float(u.stats.get("str",u.atk))*(1.+u.rank("caster_punish"))
			if s["kind"] == "stun":
				_stun(target,s.get("dur",1.))
			if sid == "fireball" and _own_dot(target,u,"ignite") != null:
				a *= 1.25
			var dealt := _deal(u,target,a,true,false,sid,copy)
			if s.get("leech",0.) > 0. or s["kind"] == "drain":
				_heal(u,u,dealt*s.get("leech",1.),false,sid)
			if s.get("death_heal",false):
				var lost := 0.
				for h in u.damage_history:
					if h[0] >= time-5.:
						lost += h[1]
				_heal(u,u,maxf(u.max_hp*.05,lost*.3),false,sid)
			if s.has("debuff") and target.alive():
				_buff(target,s["debuff"],s["value"],s["dur"],u)
				if s["debuff"] == "haunt":
					target.buffs["haunt"]["heal"] = dealt
			if s.get("purge",false):
				_purge(target)
			if sid == "chimera":
				var d = _own_dot(target,u,"serpent_sting")
				if d != null:
					d["remaining"] = d["duration"]
					_deal(u,target,d["per_tick"]*d["duration"]*.4,false,true,sid,true)
		"aoe_damage","aoe_dot":
			var foes := foes_of(u)
			for i in mini(foes.size(),s.get("max_targets",99)):
				var f: BattleUnit = foes[i]
				if s["kind"] == "aoe_dot":
					_apply_dot(u,f,sid,a,s.get("dur",6.))
				else:
					if s.get("interrupt",false) and i == 0:
						_interrupt(u,f)
					_deal(u,f,a,true,false,sid,copy)
					if s.has("debuff"):
						_buff(f,s["debuff"],s["value"],s["dur"],u)
					if s.get("stun",0.) > 0.:
						_interrupt(u,f)
						_stun(f,s["stun"])
		"dot":
			if s.get("initial",0.) > 0.:
				_deal(u,target,a*s["initial"]/s["mult"],true,false,sid,copy)
			if target.alive():
				_apply_dot(u,target,sid,a,s.get("dur",6.))
				_fx(u,target,s.get("fx","orb"),s.get("color","#99cfff"))
		"heal","riptide","chain_heal":
			_heal(u,target,a,true,sid,true)
			_fx(u,target,s.get("fx","orb"),s.get("color","#99cfff"))
			if s["kind"] == "riptide":
				_hot(u,target,sid,u.power*s["tick_mult"]*Db.spell_level_mult(lvl),s["dur"])
			if s["kind"] == "chain_heal":
				var healed := [target]
				var last: BattleUnit = target
				for i in 2:
					var next: BattleUnit = null
					for f in friends_of(u):
						if not healed.has(f) and f.hp_frac() < 1. and (next == null or f.hp_frac() < next.hp_frac()):
							next = f
					if next == null:
						break
					healed.append(next)
					_heal(u,next,a*pow(.65,i+1),true,sid,true)
					_fx(last,next,"heal_chain",s["color"])
					last = next
		"hot","hot_all":
			for f in (friends_of(u) if s["kind"] == "hot_all" else [target]):
				_hot(u,f,sid,a,s["dur"],s.get("decay",false))
				_fx(u,f,s.get("fx","heal"),s.get("color","#83efa0"))
		"shield","self_shield":
			_shield(u,u if s["kind"] == "self_shield" else target,a,s.get("dur",8.),sid)
		"shield_all":
			for f in friends_of(u):
				_shield(u,f,a,s.get("dur",8.),sid)
				_fx(u,f,"shield",s.get("color","#7fe0ff"))
		"silence":
			_silence(target,s.get("dur",3.))
			_fx(u,target,"curse","#3ac0a8")
		"taunt":
			taunt_seq += 1
			for f in friends_of(u):
				f.taunt = 0.
			u.taunt = s["dur"]+2.*u.rank("relentless")
			u.taunt_order = taunt_seq
			_status(u,"Провокация")
			_fx(u,u,"shout","#ff7457")
		"cleanse":
			_cleanse(target)
			_heal(u,target,a,true,sid,true)
			if u.rank("clean_slate"):
				_buff(target,"dot_guard",1.,2.*u.rank("clean_slate"),u)
			_fx(u,target,"cleanse","#aaffdd")
		"purge":
			_purge(target)
			_fx(u,target,"cleanse","#caaaff")
		"mass_dispel":
			for f in friends_of(u):
				_cleanse(f)
				_fx(u,f,"cleanse","#aaffdd")
			for f in foes_of(u):
				_purge(f)
				_fx(u,f,"cleanse","#caaaff")
		"prism":
			_deal(u,target,a,true,false,sid,copy)
			for f in friends_of(u):
				_heal(u,f,a*.6,true,sid,true)
				_fx(target,f,"holy","#fff1b2")
		"buff_all","buff_self":
			for f in (friends_of(u) if s["kind"] == "buff_all" else [u]):
				_buff(f,s["buff"],s["value"],s["dur"],u)
				_fx(u,f,s["fx"],s["color"])
		"rally":
			for f in friends_of(u):
				if not f.buffs.has("rally"):
					var extra: float = f.max_hp*.2
					f.max_hp += extra
					f.hp += extra
					_buff(f,"rally",.2,s["dur"],u)
					f.buffs["rally"]["amount"] = extra
					_fx(u,f,"shout","#ffd377")
		"debuff":
			_buff(target,s["debuff"],s["value"],s["dur"],u)
			_fx(u,target,"curse",s["color"])
		"earth_shield","prayer":
			_buff(target,sid,a,s["dur"],u)
			target.buffs[sid].merge({"charges":s["charges"],"ready":0.})
			_fx(u,target,s.get("fx","orb"),s.get("color","#99cfff"))
		"seed","explosive":
			if copy and target.counters.has(s["kind"]):
				target.counters[s["kind"]]["amount"] += a
			else:
				target.counters[s["kind"]] = {"src":u,"amount":a,"remaining":s["dur"],"threshold":u.power*3.,"damage":0.,"id":sid}
			_fx(u,target,s.get("fx","orb"),s.get("color","#99cfff"))
		"summon":
			_summon(u,sid,s["dur"],a,2.)
	if not copy and not s.get("weapon",false) and s.get("cast",0.) > 0.:
		if u.rank("residual"):
			_shield(u,u,u.power*.15*u.rank("residual"),6.,"residual",false)
		if _offensive(s) and rng.randf() < .1*u.rank("echo"):
			_cast(u,sid,lvl,target,.5,true)

func _channel_pulse(u: BattleUnit,c: Dictionary) -> void:
	var sid: String = c["spell"]
	if sid == "penance":
		var t: BattleUnit = c["target"]
		if not t.alive():
			t = _injured(u,.75)
			if t == null:
				t = pick_target(u)
		if t != null:
			if t.side == u.side:
				_heal(u,t,c["amount"],true,sid,true)
				_fx(u,t,"holy","#fff0b0")
			else:
				_deal(u,t,c["amount"],true,false,sid)
	else:
		for f in foes_of(u):
			_deal(u,f,c["amount"],true,false,sid)

func _offensive(s: Dictionary) -> bool:
	return s["kind"] in ["damage","execute","dot","aoe_dot","aoe_damage","seed","explosive","prism","drain"]

func _buff(t: BattleUnit,id: String,value: float,dur: float,src: BattleUnit) -> void:
	if t.buffs.has(id) and t.buffs[id]["value"] > value:
		return
	t.buffs[id] = {"value":value,"remaining":dur,"src":src}

func _debuffed(t: BattleUnit) -> bool:
	return t.is_debuffed() or t.silence > 0. or t.buffs.keys().any(func(id): return id in ["slow","weakness","haunt","sunder","mortal_wounds"])

func _positive(t: BattleUnit) -> bool:
	return t.shield > 0. or not t.hots.is_empty() or t.buffs.keys().any(func(id): return id in ["wall","physical","bloodlust","earth_shield","prayer"])

func _cleanse(t: BattleUnit) -> void:
	t.dots.clear()
	t.stun = 0.
	t.silence = 0.
	for id in ["slow","weakness","haunt","sunder","mortal_wounds"]:
		t.buffs.erase(id)
	_status(t,"Очищен")

func _purge(t: BattleUnit) -> void:
	if t.shield > 0.:
		t.shield = 0.
		t.shield_sid = ""
		t.buffs.erase("vengeance_charge")
	elif not t.hots.is_empty():
		t.hots.pop_front()
	else:
		for id in ["wall","physical","bloodlust","earth_shield","prayer"]:
			if t.buffs.has(id):
				t.buffs.erase(id)
				break
	_status(t,"Рассеяно")

func _interruptible(t: BattleUnit) -> bool:
	return t.is_casting() and (t.casting.get("interruptible",true) if not t.casting.is_empty() else t.channel.get("interruptible",true))

func _interrupt(src: BattleUnit,t: BattleUnit) -> bool:
	if not _interruptible(t):
		return false
	t.casting.clear()
	t.channel.clear()
	t.spell_cd = t.spell_interval()
	_emit({"t":"interrupt","uid":t.uid,"text":"Прервано!"})
	if src.rank("breathless"):
		_silence(t,5.)
	if rng.randf() < float(src.rank("countercast"))/3.:
		src.counters["instant"] = true
	return true

func _silence(t: BattleUnit,dur: float) -> void:
	t.silence = maxf(t.silence,dur)
	t.casting.clear()
	t.channel.clear()
	_status(t,"Безмолвие")

func _stun(t: BattleUnit,dur: float) -> void:
	if t.is_boss or (t.equipped("shield") and rng.randf() < .2*t.rank("unshaken")):
		return
	t.stun = maxf(t.stun,dur)
	t.casting.clear()
	t.channel.clear()
	_status(t,"Оглушён")

func _own_dot(t: BattleUnit,src: BattleUnit,sid: String) -> Variant:
	for d in t.dots:
		if d["id"] == sid and d["src"] == src:
			return d
	return null

func _apply_dot(src: BattleUnit,t: BattleUnit,sid: String,amount: float,dur: float,rolling: bool = false,school: String = "") -> void:
	if not t.alive():
		return
	if t.buffs.has("dot_guard"):
		t.buffs.erase("dot_guard")
		_status(t,"Защита от DoT")
		return
	var s: Dictionary = Db.SPELLS.get(sid,{})
	var spell_dot: bool = not s.get("weapon",false) and sid not in ["poison_blades","deep_wounds"]
	if school == "":
		school = s.get("school","magic")
	if spell_dot:
		dur += src.rank("long_burn")
	var old = _own_dot(t,src,sid)
	if old != null:
		if rolling:
			amount += old["per_tick"]*maxf(0.,old["remaining"])/dur
		old.merge({"remaining":dur,"duration":dur,"per_tick":amount},true)
		return
	t.dots.append({"id":sid,"src":src,"per_tick":amount,"remaining":dur,"duration":dur,"tick":1.,"school":school,"spell_dot":spell_dot})

func _hot(src: BattleUnit,t: BattleUnit,sid: String,amount: float,dur: float,decay: bool = false) -> void:
	if not t.alive():
		return
	dur += src.rank("care")
	for h in t.hots:
		if h["id"] == sid and h["src"] == src:
			h.merge({"remaining":dur,"duration":dur,"per_tick":amount},true)
			return
	t.hots.append({"id":sid,"src":src,"per_tick":amount,"remaining":dur,"duration":dur,"tick":1.,"decay":decay})

func _hot_tick(src: BattleUnit,t: BattleUnit,a: float,sid: String) -> void:
	if t.hp >= t.max_hp and src.rank("passing_care"):
		var f := _injured(src,1.,t)
		if f != null:
			_heal(src,f,a*[0.,.3,.6,1.][src.rank("passing_care")],false,sid)
	else:
		_heal(src,t,a,false,sid)

func _shield(src: BattleUnit,t: BattleUnit,a: float,dur: float,sid: String,additive: bool = true) -> void:
	a *= 1.+src.gear_fx.get("shield_bonus",0.)
	t.shield = t.shield+a if additive else maxf(t.shield,a)
	t.shield_time = maxf(t.shield_time,dur)
	t.shield_owner = src
	t.shield_sid = sid
	if sid == "vengeance":
		_buff(t,"vengeance_charge",0.,dur,src)
		t.buffs["vengeance_charge"].merge({"left":a,"absorbed":0.})
	_emit({"t":"shield","uid":t.uid,"v":a})
	_fx(src,t,"shield","#8fcfff")

func _break_shield(t: BattleUnit) -> void:
	t.shield = 0.
	t.shield_sid = ""
	t.shield_absorbed = 0.
	if t.buffs.has("vengeance_charge"):
		var charge: Dictionary = t.buffs["vengeance_charge"]
		t.buffs.erase("vengeance_charge")
		_vengeance_burst(t,charge)

func _vengeance_burst(t: BattleUnit,charge: Dictionary) -> void:
	for f in foes_of(charge["src"]):
		_deal(charge["src"],f,charge["absorbed"]*.5,false,false,"vengeance",true,"magic")
		_fx(t,f,"explosion","#ffd179")

func _summon(u: BattleUnit,sid: String,dur: float,a: float,interval: float) -> void:
	u.summons.append({"id":sid,"remaining":dur,"amount":a,"interval":interval,"tick":interval})
	_status(u,{"beast":"Зверь","fire_totem":"Огненный тотем","healing_totem":"Тотем исцеления"}.get(sid,sid))

func _poison(src: BattleUnit,t: BattleUnit) -> void:
	if t.alive() and src.rank("poison_blades") and rng.randf() < .1*src.rank("poison_blades"):
		_apply_dot(src,t,"poison_blades",float(src.stats.get("str",src.atk))*.1,6.,false,"magic")

func _deal(src: BattleUnit,t: BattleUnit,amount: float,can_crit: bool,is_dot: bool,sid: String = "",proc: bool = false,school: String = "",with_fx: bool = true) -> float:
	if not t.alive():
		return 0.
	if amount <= 0.:
		return 0.
	var s: Dictionary = Db.SPELLS.get(sid,{})
	if school == "":
		school = s.get("school","physical" if sid in ["attack","","e_smash","e_volley","e_backstab","e_cleave","e_crush","e_quake","e_execute"] else "magic")
	if not is_dot and school == "physical" and t.equipped("shield") and rng.randf() < .1*t.rank("full_block"):
		_status(t,"Блок")
		return 0.
	var dmg: float = amount*src.dmg_mult*(1.-src.buff("weakness"))*(1.-t.buff("wall"))
	if not src.gear_fx.is_empty():
		dmg *= 1.+Items.damage_bonus(src.gear_fx,sid,s.get("kind",""),is_dot,school,t.is_boss,t.hp_frac())
	if school == "physical":
		dmg *= 1.+src.buff("physical")
		if not is_dot:
			dmg *= 100./(100.+t.armor*(1.-t.buff("sunder")))
	elif school == "magic":
		dmg *= 1.-float(t.stats.get("magic_resist",0.))
	if t.hp_frac() < .5:
		dmg *= 1.-.1*t.rank("deep_defense")
	var weapon: bool = s.get("weapon",false) or sid == "attack"
	if foes_of(src).size() == 1:
		dmg *= 1.+.05*src.rank("duelist")
		if s.get("kind","") in ["aoe_damage","channel_aoe","explosive","seed"] or (sid == "living_bomb" and not is_dot):
			if weapon:
				if src.equipped("sword"):
					dmg *= 1.+.1*src.rank("focused_cleave")
			else:
				dmg *= 1.+.1*src.rank("focused_aoe")
	if sid == "attack" and (src.equipped("sword") or src.equipped("bow")):
		dmg *= 1.+.03*src.rank("weapon_master")
	elif weapon and (src.equipped("sword") or src.equipped("bow")):
		dmg *= 1.+.04*src.rank("strong_swing")
	if is_dot and t.buffs.has("haunt") and t.buffs["haunt"]["src"] == src:
		dmg *= 1.+t.buff("haunt")
	var chance: float = src.crit+(.01*src.rank("accuracy") if weapon else .02*src.rank("spell_crit"))
	if is_dot:
		chance = .1*src.rank("hot_flame") if school == "magic" else 0.
	var crit: bool = (can_crit or is_dot and school == "magic") and rng.randf() < chance
	if crit:
		dmg *= 2.+src.gear_fx.get("crit_power",0.)
	if not proc and not is_dot and not weapon and src.rank("spark") and not src.counters.has("spark"):
		dmg += src.power*.3*src.rank("spark")
		src.counters["spark"] = true
	dmg = maxf(1.,round(dmg))
	if s.get("shield_bonus",1.) > 1. and t.shield > 0.:
		var extra := minf(t.shield,dmg*(s["shield_bonus"]-1.))
		t.shield -= extra
		t.shield_absorbed += extra
		_charge_vengeance(t,extra)
	var absorbed := minf(t.shield,dmg)
	t.shield -= absorbed
	t.shield_absorbed += absorbed
	_charge_vengeance(t,absorbed)
	dmg -= absorbed
	if absorbed > 0.:
		_emit({"t":"absorb","uid":t.uid,"v":absorbed})
	if t.shield <= 0. and t.shield_sid != "":
		_break_shield(t)
	if dmg >= t.hp and t.rank("undying") and not t.spent.has("undying"):
		t.spent["undying"] = true
		dmg = maxf(0.,t.hp-1.)
		_shield(t,t,t.max_hp*.3,5.,"undying")
		_status(t,"Несокрушимость")
	var lost := minf(t.hp,dmg)
	t.hp = maxf(0.,t.hp-dmg)
	if dmg > 0.:
		_emit({"t":"dmg","uid":t.uid,"v":round(dmg),"crit":crit,"dot":is_dot,"src":src.uid})
		t.damage_history.append([time,lost])
		while not t.damage_history.is_empty() and t.damage_history[0][0] < time-5.:
			t.damage_history.pop_front()
	src.dealt += lost+absorbed
	var meter_id: String = sid if Db.SPELLS.has(sid) else "attack"
	src.dealt_by[meter_id] = src.dealt_by.get(meter_id,0.)+lost+absorbed
	if not is_dot and sid != "attack" and with_fx:
		_fx(src,t,s.get("fx","slash"),s.get("color","#ffffff"))
	if lost > 0. and src.alive() and src.rank("life_source"):
		for f in friends_of(src):
			_heal(src,f,lost*[0.,.01,.03,.05][src.rank("life_source")],false,meter_id)
	if not proc and not is_dot:
		if weapon and src.equipped("sword"):
			_poison(src,t)
		if weapon and src.equipped("greatsword"):
			if src.rank("mortal_wounds"):
				_buff(t,"mortal_wounds",.5,6.,src)
			if crit and src.rank("deep_wounds"):
				_apply_dot(src,t,"deep_wounds",(lost+absorbed)*.1*src.rank("deep_wounds")/6.,6.,true,"physical")
		if crit and not weapon and src.rank("ignition"):
			_apply_dot(src,t,"ignition",(lost+absorbed)*.1*src.rank("ignition")/4.,4.,true)
		if src.equipped("bow") and weapon and s.get("kind","") not in ["aoe_damage","channel_aoe","explosive","dot"] and rng.randf() < .1*src.rank("piercing_shot"):
			for other in foes_of(src):
				if other != t:
					_deal(src,other,amount,can_crit,false,sid,true,school)
	if lost > 0.:
		_gear_procs(src,t,lost,proc or is_dot)
	if lost > 0. and t.alive():
		_reactive_heals(t)
	if lost > 0. and not proc and not is_dot and school == "physical" and t.rank("retaliation"):
		_deal(t,src,lost*.1*t.rank("retaliation"),false,false,"attack",true,"physical")
	if t.counters.has("seed"):
		t.counters["seed"]["damage"] += lost
		if t.counters["seed"]["damage"] >= t.counters["seed"]["threshold"] or not t.alive():
			_detonate(t,"seed")
	if not t.alive():
		if t.counters.has("explosive"):
			_detonate(t,"explosive")
		_on_death(t)
	return lost

func _charge_vengeance(t: BattleUnit,absorbed: float) -> void:
	if t.buffs.has("vengeance_charge"):
		var charge: Dictionary = t.buffs["vengeance_charge"]
		var contribution := minf(charge["left"],absorbed)
		charge["left"] -= contribution
		charge["absorbed"] += contribution
		if charge["left"] <= 0.:
			t.buffs.erase("vengeance_charge")
			_vengeance_burst(t,charge)

func _reactive_heals(t: BattleUnit) -> void:
	for id in ["earth_shield","prayer"]:
		if not t.buffs.has(id):
			continue
		var b: Dictionary = t.buffs[id]
		if b["ready"] > time:
			continue
		_heal(b["src"],t,b["value"],true,id)
		b["charges"] -= 1
		b["ready"] = time+(2. if id == "earth_shield" else .5)
		if id == "prayer":
			t.buffs.erase(id)
			var next: BattleUnit = null
			for f in friends_of(t):
				if f != t and (next == null or f.hp_frac() < next.hp_frac()):
					next = f
			if next != null and b["charges"] > 0:
				next.buffs[id] = b
				_fx(t,next,"prayer","#fff0ab")
		elif b["charges"] <= 0:
			t.buffs.erase(id)

## Lifesteal, thorns and free spells of worn gear. `quiet` hits (procs, dots) start no new procs.
func _gear_procs(src: BattleUnit,t: BattleUnit,lost: float,quiet: bool) -> void:
	if src.gear_fx.has("lifesteal") and src.alive():
		_heal(src,src,lost*src.gear_fx["lifesteal"],false,"lifesteal")
	if quiet:
		return
	if t.gear_fx.has("thorns") and src.alive():
		_deal(t,src,lost*t.gear_fx["thorns"],false,false,"attack",true,"physical")
	for p in src.gear_fx.get("procs",[]):
		if t.alive() and not src.counters.has("gear_proc") and rng.randf() < p["chance"]:
			src.counters["gear_proc"] = true
			var lvl := 1
			for e in src.spells:
				lvl = maxi(lvl,int(e["lvl"]))
			_cast(src,p["sid"],lvl,t,p["scale"],true)
			src.counters.erase("gear_proc")

func _heal(src: BattleUnit,t: BattleUnit,amount: float,can_crit: bool,sid: String = "",direct: bool = false) -> void:
	if not t.alive():
		return
	var h: float = amount*src.heal_mult*(1.+.03*src.rank("life_gift"))*(1.-t.buff("mortal_wounds"))
	if not src.gear_fx.is_empty():
		h *= 1.+src.gear_fx.get("heal_bonus",0.)+src.gear_fx.get("spell:"+sid,0.)
	var crit: bool = can_crit and rng.randf() < src.crit
	if crit:
		h *= 2.
	var excess := maxf(0.,h-(t.max_hp-t.hp))
	var actual := minf(h,t.max_hp-t.hp)
	t.hp += actual
	src.healed += actual
	var meter_id: String = sid if Db.SPELLS.has(sid) else "heal"
	src.healed_by[meter_id] = src.healed_by.get(meter_id,0.)+actual
	if actual > 0.:
		_emit({"t":"heal","uid":t.uid,"v":round(actual),"crit":crit})
	if not direct:
		return
	if src.rank("reserve") and excess > 0.:
		var shield := minf(excess*.1*src.rank("reserve"),maxf(0.,t.max_hp*.1-t.shield))
		if shield > 0.:
			_shield(src,t,shield,8.,"reserve")
	if src.rank("living_cover"):
		for hot in t.hots.duplicate():
			if hot["src"] == src:
				_hot_tick(src,t,hot["per_tick"]*[0.,.3,.6,1.][src.rank("living_cover")],hot["id"])
	if src.rank("shared_care") and actual > 0.:
		var f := _injured(src,1.,t)
		if f != null:
			_heal(src,f,actual*.1*src.rank("shared_care"),false,sid)
	if src.rank("healing_trail"):
		_hot(src,t,"healing_trail",amount*.1*src.rank("healing_trail")/4.,4.)

func _explode_dot(d: Dictionary,target: BattleUnit) -> void:
	if d["id"] in ["living_bomb","poison_cloud"]:
		for f in foes_of(d["src"]):
			_deal(d["src"],f,d["per_tick"]*5.2,false,false,"living_bomb",true)
			_fx(target,f,"explosion","#ff9954")

func _detonate(t: BattleUnit,id: String) -> void:
	var b: Dictionary = t.counters[id]
	t.counters.erase(id)
	for f in foes_of(b["src"]):
		_deal(b["src"],f,b["amount"],true,false,b["id"],true)
		_fx(t,f,"explosion","#b57de0" if id == "seed" else "#ffa452")

func _on_death(t: BattleUnit) -> void:
	if t.counters.get("death_done",false):
		return
	t.counters["death_done"] = true
	for d in t.dots.duplicate():
		_explode_dot(d,t)
		var src: BattleUnit = d["src"]
		if src.rank("carry_fire") and d["spell_dot"]:
			for f in foes_of(src):
				if _own_dot(f,src,d["id"]) == null:
					# Transfer a fraction of the remainder without adding talent duration again.
					var duration: float = maxf(1.,d["remaining"])
					_apply_dot(src,f,d["id"],d["per_tick"]*[0.,.3,.6,1.][src.rank("carry_fire")],duration,false,d["school"])
					var transferred = _own_dot(f,src,d["id"])
					if transferred != null:
						transferred["remaining"] = duration
						transferred["duration"] = duration
					break
	if t.buffs.has("haunt"):
		var h: Dictionary = t.buffs["haunt"]
		_heal(h["src"],h["src"],h["heal"],false,"haunt")
	if t.rank("life_legacy") and not t.spent.has("life_legacy"):
		t.spent["life_legacy"] = true
		for f in friends_of(t):
			_shield(t,f,f.max_hp*.25*t.rank("life_legacy"),10.,"life_legacy")
	if t.buffs.has("rally"):
		t.max_hp -= t.buffs["rally"]["amount"]
	t.casting.clear()
	t.channel.clear()
	t.dots.clear()
	t.hots.clear()
	t.buffs.clear()
	t.summons.clear()
	t.shield = 0.
	_emit({"t":"death","uid":t.uid})

func end_wave() -> void:
	for u in units:
		if u.side == 0 and u.alive() and u.rank("respite"):
			var f := _injured(u)
			if f != null:
				_hot(u,f,"respite",f.max_hp*.05*u.rank("respite")/6.,6.)

func _check_end() -> void:
	if side_units(1).is_empty():
		finished = true
		won = true
		end_reason = "Волна зачищена"
	elif side_units(0).is_empty():
		finished = true
		end_reason = "Группа погибла"
	elif time >= TIME_LIMIT:
		finished = true
		end_reason = "Время вышло"

func _status(u: BattleUnit,text: String) -> void:
	_emit({"t":"status","uid":u.uid,"text":text})

func _fx(src: BattleUnit,dst: BattleUnit,kind: String,color: String,summon_id: String = "") -> void:
	_emit({"t":"fx","uid":src.uid,"tgt":dst.uid,"kind":kind,"color":color,"summon":summon_id})

func _emit(e: Dictionary) -> void:
	if record_events:
		event_seq += 1
		e["n"] = event_seq
		e["time"] = time # Visual timeline metadata only; never drives combat resolution.
		events.append(e)
		if events.size() > 500:
			events = events.slice(250)

func release(enemies_only: bool = false) -> void:
	# Break source/target RefCounted cycles in long-running offline/server workers.
	for u in units:
		if enemies_only and u.side == 0:
			continue
		u.casting.clear()
		u.channel.clear()
		u.buffs.clear()
		u.dots.clear()
		u.hots.clear()
		u.counters.clear()
		u.shield_owner = null
