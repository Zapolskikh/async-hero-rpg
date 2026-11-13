class_name MercGenerator
extends RefCounted
## Random classless companions. No quality tiers or pre-authored role templates.
## Tank, archer and healer: the balanced group of a new player.
const STARTERS := [
	{"weapons": ["sword", "shield"], "talents": "bulwark", "spells": ["shield_slam", "taunt", "strike"]},
	{"weapons": ["bow"], "talents": "assault", "spells": ["aimed_shot", "serpent_sting", "tranq"]},
	{"weapons": ["staff"], "talents": "life", "spells": ["heal", "renew", "barrier"]},
]

## Board mercenaries first roll a specialization. Half are hybrids (anything goes, as before);
## the other half are built for one job: weapons, spells, talent branch and gear all fit it.
const HYBRID_CHANCE := 0.5
const SPECS := {
	"healer": {"weapons": [["staff"]], "talents": "life", "role": "healer",
		"spells": ["heal", "renew", "barrier", "riptide", "wild_growth", "chain_heal", "earth_shield", "penance", "prayer", "pain_suppression", "prism", "cleanse"],
		"core": ["heal", "riptide", "chain_heal", "penance"]},
	"mage": {"weapons": [["staff"]], "talents": "arcane", "role": "caster",
		"spells": ["fireball", "arcane_bolt", "ignite", "frostbolt", "chain_lightning", "haunt", "living_bomb", "seed", "weakness", "kick", "spell_lock"],
		"core": ["fireball", "arcane_bolt", "frostbolt", "chain_lightning"]},
	"tank": {"weapons": [["sword", "shield"]], "talents": "bulwark", "role": "tank",
		"spells": ["shield_slam", "shield_wall", "thunder_clap", "shockwave", "avenger", "vengeance", "intervene", "kick", "spell_lock"],
		"core": ["taunt"]},
	"physical": {"weapons": [["greatsword"], ["sword", "sword"], ["bow"]], "talents": "assault", "role": "",
		"spells": ["strike", "mortal_strike", "rend", "cleave", "whirlwind", "execute", "death_strike", "bladestorm",
			"aimed_shot", "serpent_sting", "chimera", "explosive", "tranq", "arrow_rain", "beast", "hunters_mark", "kick", "battle_cry"],
		"core": ["mortal_strike", "strike", "aimed_shot"]},
}
## Mercenaries start with weapon, left hand, body and amulet; one more slot opens every 5 levels,
## so a level 30 mercenary wears a full set (still weaker than a player's: one roll per slot, no crafting).
const EXTRA_SLOTS := [[5, "head"], [10, "feet"], [15, "hands"], [20, "legs"], [25, "accessory1"], [30, "accessory2"]]
const SPEC_TALENT_WEIGHT := 20   # a specialist puts almost every point into its branch (a hybrid: 5)

## Talent branch of a specialist. A greatsword fighter goes Bulwark: most Assault talents
## need two swords or a bow, Bulwark has the greatsword ones.
static func spec_branch(spec: String, weapons: Array) -> String:
	if spec == "physical" and weapons.has("greatsword"):
		return "bulwark"
	return SPECS[spec]["talents"]

## Rolls the specialization of a new board mercenary.
static func roll_spec(rng: RandomNumberGenerator) -> String:
	if rng.randf() < HYBRID_CHANCE:
		return "hybrid"
	var names := SPECS.keys()
	return names[rng.randi_range(0, names.size() - 1)]

## Three spells for a specialist: one core spell of the job, two more from its pool.
static func spec_spells(rng: RandomNumberGenerator, spec: String, weapons: Array) -> Array:
	var d: Dictionary = SPECS[spec]
	var core := []
	for id in d["core"]:
		if Db.spell_usable(id, weapons):
			core.append(id)
	var picked := [core[rng.randi_range(0, core.size() - 1)]]
	var pool := []
	for id in d["spells"]:
		if not id in picked and Db.SPELLS.has(id) and Db.spell_usable(id, weapons):
			pool.append(id)
	while picked.size() < 3 and not pool.is_empty():
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		picked.append(id)
		pool.erase(id)
	return picked

## How strong offered mercenaries are. The reference is what the hero OWNS, not what he wears:
## the best item for every slot from worn gear and the bag, and the best spells of the
## collection. Putting on rare items or spells just before the board refreshes changes nothing.
## A mercenary is compared slot by slot (it has fewer slots at low levels): its target is
## REF_SHARE of the hero's best items in the slots it has plus his best spells, and it rolls
## within BAND of that target. An empty slot counts as nothing: an undergeared hero gets
## undergeared mercenaries (the first clears of levels 2-10 hand out gear, Rules.FIRST_CLEAR_GEAR).
const REF_SHARE := 0.9
const BAND := [0.9, 1.1]
const RAISE_ILVL_OVER := 5     # raising a mercenary: items up to its level + this
const RAISE_MAX_RARITY := 4    # and up to epic (legendaries are uniques, not for mercenaries)

static func power_ref(p: Dictionary) -> Dictionary:
	var items := []
	for slot in p["hero"]["equipped"]:
		if p["hero"]["equipped"][slot] != null:
			items.append(p["hero"]["equipped"][slot])
	items.append_array(p["inventory"])
	var best := {}
	var accs := []
	var one_hand := []
	var offhands := []
	var two_hand := 0.0
	for it in items:
		var g := Roster.item_gs(it)
		var slot := str(it["slot"])
		if slot == "accessory":
			accs.append(g)
		elif slot == "weapon" and Loot.is_two_handed(it):
			two_hand = maxf(two_hand, g)
		elif slot == "weapon" or slot == "offhand":
			if slot == "weapon":
				one_hand.append([g, it["id"]])
			if Loot.fits_offhand(it):
				offhands.append([g, it["id"]])
		else:
			best[slot] = maxf(float(best.get(slot, 0.0)), g)
	# both hands: a two-hander, or the best one-hander plus a different left-hand item
	var pair := two_hand
	for w in one_hand:
		var off := 0.0
		for o in offhands:
			if o[1] != w[1]:
				off = maxf(off, o[0])
		pair = maxf(pair, w[0] + off)
	accs.sort()
	accs.reverse()
	var slots := {"weapons": pair,
		"accessory1": accs[0] if accs.size() > 0 else 0.0, "accessory2": accs[1] if accs.size() > 1 else 0.0}
	for slot in ["head", "armor", "hands", "legs", "feet", "trinket"]:
		slots["slot_" + slot] = float(best.get(slot, 0.0))
	var spells := []
	for sid in p["collection"]:
		var l := int(p["collection"][sid].get("lvl", 0))
		if l > 0 and Db.SPELLS.has(sid):
			spells.append(Roster.spell_gs(sid, l))
	spells.sort()
	spells.reverse()
	var top := []
	for i in 3:
		top.append(spells[i] if i < spells.size() else 0.0)
	return {"slots": slots, "spells": top}

## REF_SHARE of the hero's best items in the slots this mercenary has, plus his best spells.
static func power_target(ref: Dictionary, m: Dictionary) -> float:
	var sl: Dictionary = ref["slots"]
	var t := float(sl["weapons"])
	for slot in m["gear"]:
		if slot == "weapon" or slot == "offhand":
			continue
		t += float(sl.get(slot, 0.0)) if slot.begins_with("accessory") else float(sl.get("slot_" + slot, 0.0))
	for i in mini(m["spells"].size(), ref["spells"].size()):
		t += float(ref["spells"][i])
	return t * REF_SHARE

## Brings a mercenary into BAND of its target: first down (fit_power), then up.
static func fit_ref(rng: RandomNumberGenerator, m: Dictionary, ref: Dictionary) -> void:
	if ref.is_empty():
		return
	var target := power_target(ref, m)
	var hi := target * float(BAND[1])
	fit_power(rng, m, hi)
	raise_power(rng, m, target * float(BAND[0]), hi)

## Raises a mercenary to at least `lo` without passing `hi` when it can: a random step among
## an item one quality up, an item 2 levels up, a spell one level up.
static func raise_power(rng: RandomNumberGenerator, m: Dictionary, lo: float, hi: float) -> void:
	var role := _role(m)
	var changed := false
	for guard in 200:
		var now := float(Roster.power_score(m))
		if now >= lo:
			break
		var steps := []   # [delta, kind, key]
		for slot in m["gear"]:
			var it = m["gear"][slot]
			if it == null:
				continue
			var hands := 2.0 if Loot.is_two_handed(it) else 1.0
			var q := int(it["rarity"])
			if q < RAISE_MAX_RARITY:
				steps.append([Roster.GS_PER_ILVL * float(it["ilvl"]) * hands * (Roster.GS_QUALITY[q + 1] - Roster.GS_QUALITY[q]), "rarity", slot])
			if int(it["ilvl"]) + 2 <= int(m["level"]) + RAISE_ILVL_OVER:
				steps.append([Roster.GS_PER_ILVL * 2.0 * hands * Roster.GS_QUALITY[q], "ilvl", slot])
		for i in m["spells"].size():
			var e: Dictionary = m["spells"][i]
			if int(e["lvl"]) < Rules.SPELL_MAX_LEVEL:
				steps.append([Roster.spell_gs(e["id"], int(e["lvl"]) + 1) - Roster.spell_gs(e["id"], int(e["lvl"])), "spell", i])
		if steps.is_empty():
			break
		var fitting := steps.filter(func(st): return now + float(st[0]) <= hi)
		var step: Array
		if not fitting.is_empty():
			step = fitting[rng.randi_range(0, fitting.size() - 1)]
		else:
			steps.sort_custom(func(a, b): return a[0] < b[0])
			step = steps[0]
		match step[1]:
			"spell":
				m["spells"][step[2]]["lvl"] = int(m["spells"][step[2]]["lvl"]) + 1
			_:
				var old: Dictionary = m["gear"][step[2]]
				var kind := "accessory" if old["slot"] == "accessory" else str(old["slot"])
				var ilvl := int(old["ilvl"]) + (2 if step[1] == "ilvl" else 0)
				var q2 := int(old["rarity"]) + (1 if step[1] == "rarity" else 0)
				m["gear"][step[2]] = Loot.roll_gear(rng, ilvl, "merc", kind if not old.has("wtype") else "", old.get("wtype", ""), role, q2)
		changed = true
	if changed:
		_restat(m)

static func _role(m: Dictionary) -> String:
	var role := Items.role_of(m["weapons"])
	if SPECS.has(m.get("spec", "")) and SPECS[m["spec"]]["role"] != "":
		role = SPECS[m["spec"]]["role"]
	return role

static func _restat(m: Dictionary) -> void:
	var st := Roster.apply_gear(m["base_stats"].duplicate(), m["gear"])
	Talents.apply_stats(st, m["talents"], m["weapons"])
	st.merge(Loot.attack_of(st, m["gear"]), true)
	m["stats"] = st
	m["effects"] = Items.effects_of(m["gear"])
	m["look"] = Roster.look(m["gear"])

## Brings a mercenary under `cap` (no cap when <= 0): its rarest item drops one quality and
## is rolled again for the same slot, then its highest spell loses a level, until it fits.
## Specialisation, weapons, spells and talents stay as rolled; only gear and spell levels give.
static func fit_power(rng: RandomNumberGenerator, m: Dictionary, cap: float) -> void:
	if cap <= 0.0:
		return
	var role := _role(m)
	for guard in 120:
		if Roster.power_score(m) <= cap:
			return
		var worst := ""
		for slot in m["gear"]:
			var it = m["gear"][slot]
			if it == null:
				continue
			var floor_q := Items.UNCOMMON if it["slot"] == "accessory" else Items.POOR
			if int(it["rarity"]) <= floor_q:
				continue
			if worst == "" or int(it["rarity"]) > int(m["gear"][worst]["rarity"]) or (int(it["rarity"]) == int(m["gear"][worst]["rarity"]) and Loot.item_score(it) > Loot.item_score(m["gear"][worst])):
				worst = slot
		if worst != "":
			var old: Dictionary = m["gear"][worst]
			var kind := "accessory" if old["slot"] == "accessory" else str(old["slot"])
			m["gear"][worst] = Loot.roll_gear(rng, int(m["level"]), "merc", kind if not old.has("wtype") else "", old.get("wtype", ""), role, int(old["rarity"]) - 1)
		else:
			var top := -1
			for i in m["spells"].size():
				if int(m["spells"][i]["lvl"]) > 1 and (top < 0 or int(m["spells"][i]["lvl"]) > int(m["spells"][top]["lvl"])):
					top = i
			if top < 0:
				# all poor and level I: accessories come off, then items get an older (lower) item level
				var removed := false
				for slot in ["accessory2", "accessory1"]:
					if m["gear"].get(slot) != null and not removed:
						m["gear"][slot] = null
						removed = true
				if not removed:
					var oldest := ""
					for slot in m["gear"]:
						var it = m["gear"][slot]
						if it != null and int(it["ilvl"]) > 1 and (oldest == "" or int(it["ilvl"]) > int(m["gear"][oldest]["ilvl"])):
							oldest = slot
					if oldest == "":
						return
					var o: Dictionary = m["gear"][oldest]
					m["gear"][oldest] = Loot.roll_gear(rng, maxi(1, int(o["ilvl"]) - 3), "merc", str(o["slot"]) if not o.has("wtype") else "", o.get("wtype", ""), role, int(o["rarity"]))
			else:
				m["spells"][top]["lvl"] = int(m["spells"][top]["lvl"]) - 1
		_restat(m)

static func make(rng: RandomNumberGenerator, level: int, forced_weapons: Array = [], forced_talents: String = "", forced_spells: Array = [], spec: String = "") -> Dictionary:
	if spec == "" and forced_weapons.is_empty() and forced_talents == "" and forced_spells.is_empty():
		spec = roll_spec(rng)
	var specialist := SPECS.has(spec)
	var choices := [["sword","shield"],["sword","sword"],["greatsword"],["staff"],["bow"]]
	if specialist:
		choices = SPECS[spec]["weapons"]
	var weapons: Array = choices[rng.randi_range(0,choices.size()-1)]
	if not forced_weapons.is_empty():
		weapons = forced_weapons.duplicate()
	var gear := Roster.empty_gear()
	var role := Items.role_of(weapons)
	if specialist and SPECS[spec]["role"] != "":
		role = SPECS[spec]["role"]
	gear["weapon"] = Loot.roll_gear(rng,level,"merc","weapon",weapons[0],role)
	if weapons.size() > 1:
		gear["offhand"] = Loot.roll_gear(rng,level,"merc","offhand",weapons[1],role)
	for slot in ["armor","trinket"]:
		gear[slot] = Loot.roll_gear(rng,level,"merc",slot,"",role)
	for extra in EXTRA_SLOTS:
		if level >= int(extra[0]):
			var slot: String = extra[1]
			if slot.begins_with("accessory"):
				# accessories are uncommon or better, as everywhere in the game (Items.make_accessory)
				var it := Loot.roll_gear(rng,level,"merc","accessory","",role)
				gear[slot] = it
			else:
				gear[slot] = Loot.roll_gear(rng,level,"merc",slot,"",role)
	var talents := {}
	var budget := Talents.points_total(level)
	var preferred: String = "arcane" if weapons.has("staff") else ("assault" if weapons.has("bow") or weapons.count("sword") == 2 else "bulwark")
	if rng.randf() < .25:
		preferred = "life"
	if forced_talents != "":
		preferred = forced_talents
	if specialist:
		preferred = spec_branch(spec, weapons)
	var weight := SPEC_TALENT_WEIGHT if specialist else 5
	for point in budget:
		var pool := []
		for id in Talents.TALENTS:
			var t: Dictionary = Talents.TALENTS[id]
			if int(talents.get(id,0)) < t["ranks"] and Talents.unlocked(id,talents) and Talents._active(t,weapons):
				pool.append(id)
				if t["branch"] == preferred:
					for w in weight:
						pool.append(id)
		if pool.is_empty():
			break
		var id: String = pool[rng.randi_range(0,pool.size()-1)]
		talents[id] = int(talents.get(id,0))+1
	var pool := []
	for id in Db.SPELLS:
		var s: Dictionary = Db.SPELLS[id]
		if s.get("enemy",false) or s.get("hidden",false):
			continue
		if Db.spell_usable(id,weapons) or (weapons.has("sword") and talents.get("throwing",0) > 0 and s.get("req",[]).has("bow")) or (id == "execute" and weapons.has("bow") and talents.get("kill_shot",0)):
			pool.append(id)
	var selected := []
	for i in 2:
		var id: String = pool[rng.randi_range(0,pool.size()-1)]
		selected.append(id)
		pool.erase(id)
	# Always retain one usable fallback; the other slots stay completely random.
	var fallback: String = "fireball" if weapons.has("staff") else ("aimed_shot" if weapons.has("bow") else "mortal_strike")
	if selected.has(fallback):
		fallback = "arcane_bolt"
	selected.append(fallback)
	if specialist:
		selected = spec_spells(rng, spec, weapons)
	if not forced_spells.is_empty():
		selected = forced_spells
	var spells := []
	for id in selected:
		spells.append({"id":id,"lvl":maxi(1,Roster.baseline_spell_level(level)-rng.randi_range(0,1))})
	var base := Db.hero_base_stats(level)
	for stat in ["hp","str","agi","power","armor"]:
		base[stat] = round(base[stat]*rng.randf_range(.9,1.1))
	var st := Roster.apply_gear(base,gear)
	Talents.apply_stats(st,talents,weapons)
	st.merge(Loot.attack_of(st,gear),true)
	var result := {"name":Db.MERC_NAMES[rng.randi_range(0,Db.MERC_NAMES.size()-1)],"color":Roster.MERC_COLORS[rng.randi_range(0,Roster.MERC_COLORS.size()-1)],"npc":true,"role":"Наёмник","level":level,"base_stats":base,"gear":gear,"stats":st,"weapons":weapons,"talents":talents,"effects":Items.effects_of(gear),"spells":spells,"target":"front","id":"m%d"%rng.randi(),"sprite":"hero","ranged":weapons.has("bow") or weapons.has("staff"),"look":Roster.look(gear)}
	result["spec"] = spec if specialist else "hybrid"
	result["appearance"] = CharacterAppearance.for_identity(result["id"])
	return result
