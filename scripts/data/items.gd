class_name Items
extends RefCounted
## Item rules in the spirit of WoW Classic. An item belongs to a role and carries only
## the stats of that role. Quality is a fixed ladder: poor and common items have no
## bonus stats, uncommon ones add a suffix ("Медведя"), rare and epic items are named,
## legendary ones have unique effects. ItemCatalog holds the names and stat shares.

const QUALITY_NAMES := ["Низкое", "Обычное", "Необычное", "Редкое", "Эпическое", "Легендарное"]
const POOR := 0
const COMMON := 1
const UNCOMMON := 2
const RARE := 3
const EPIC := 4
const LEGENDARY := 5

## Sum of stat shares an item of each quality gets, as parts of a full stat at its level.
## The steps grow on purpose: green is a small step up, blue and purple feel like a find,
## orange is far above everything.
const BUDGET := [0.3, 0.8, 1.2, 2.2, 3.4, 5.5]
## Weapon damage by quality.
const WEAPON_QUALITY := [0.75, 0.85, 0.95, 1.1, 1.25, 1.5]
const SLOT_WEIGHT := {"weapon": 1.0, "offhand": 0.8, "head": 1.0, "armor": 1.0, "legs": 1.0, "hands": 0.8, "feet": 0.8, "trinket": 0.8, "accessory": 0.7}
## Armor every piece carries by material, as a share of a full armor stat.
const ARMOR_SHARE := {"cloth": 0.1, "leather": 0.2, "mail": 0.3, "plate": 0.45}
const ILVL_PER_TIER := 5

## Chance weights of each quality by source.
const TABLES := {
	"drop": [25.0, 45.0, 29.0, 0.9, 0.09, 0.01],
	"first": [0.0, 50.0, 47.0, 2.7, 0.29, 0.01],
	"merc": [0.0, 15.0, 65.0, 18.0, 2.0, 0.0],
	"start": [0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
}
## Blue, purple and orange gear is meant to be crafted, merged or traded, not found.
## Share of drops made for the hero's own role, so a build finds usable gear.
const OWN_ROLE_CHANCE := 0.75

const ROLES := ["melee", "tank", "ranged", "caster", "healer"]
const ROLE_NAMES := {"melee": "Боец", "tank": "Танк", "ranged": "Стрелок", "caster": "Маг", "healer": "Лекарь"}
const ROLE_ARMOR := {"melee": ["plate", "mail"], "tank": ["plate"], "ranged": ["leather", "mail"], "caster": ["cloth"], "healer": ["cloth", "leather"]}
const ROLE_WEAPONS := {"melee": ["sword", "greatsword"], "tank": ["sword"], "ranged": ["bow"], "caster": ["staff"], "healer": ["staff"]}
const WEAPON_ROLE := {"sword": "melee", "greatsword": "melee", "shield": "tank", "bow": "ranged", "staff": "caster"}
const ARMOR_NAMES := {"cloth": "Ткань", "leather": "Кожа", "mail": "Кольчуга", "plate": "Латы"}

## Uncommon items: base item + suffix, always with the stats of its role.
const SUFFIXES := {
	"melee": [["Медведя", {"str": 0.6, "hp": 0.4}], ["Тигра", {"str": 0.7, "crit": 0.3}], ["Вепря", {"str": 0.7, "haste": 0.3}]],
	"tank": [["Черепахи", {"armor": 0.5, "hp": 0.5}], ["Скалы", {"hp": 0.7, "str": 0.3}], ["Стража", {"armor": 0.4, "hp": 0.4, "str": 0.2}]],
	"ranged": [["Обезьяны", {"agi": 0.6, "hp": 0.4}], ["Сокола", {"agi": 0.7, "crit": 0.3}], ["Рыси", {"agi": 0.7, "haste": 0.3}]],
	"caster": [["Орла", {"power": 0.6, "hp": 0.4}], ["Мага", {"power": 0.7, "crit": 0.3}], ["Совы", {"power": 0.7, "haste": 0.3}]],
	"healer": [["Кита", {"power": 0.5, "hp": 0.5}], ["Лебедя", {"power": 0.7, "haste": 0.3}], ["Единорога", {"power": 0.6, "hp": 0.2, "haste": 0.2}]],
}

## Equip effects. fx keys are read by the combat rules:
##   physical_bonus, magic_bonus, dot_bonus, aoe_bonus, boss_bonus, execute_bonus (target under 30%)
##   spell:<id>     - damage or healing of that spell
##   double_attack  - chance of a second basic attack
##   crit_power     - added to the crit multiplier
##   cd_refund      - chance a spell does not go on cooldown
##   cast_speed     - shorter cast times
##   heal_bonus, shield_bonus, lifesteal, thorns, start_shield (share of health)
##   procs          - [{sid, chance, scale}]: free damage spell on a hit
const EFFECTS := {
	"phys_5": {"text": "+5% физического урона", "fx": {"physical_bonus": 0.05}},
	"phys_8": {"text": "+8% физического урона", "fx": {"physical_bonus": 0.08}},
	"magic_5": {"text": "+5% магического урона", "fx": {"magic_bonus": 0.05}},
	"magic_8": {"text": "+8% магического урона", "fx": {"magic_bonus": 0.08}},
	"life_3": {"text": "3% нанесённого урона лечат героя", "fx": {"lifesteal": 0.03}},
	"life_5": {"text": "5% нанесённого урона лечат героя", "fx": {"lifesteal": 0.05}},
	"double_5": {"text": "5% шанс второй автоатаки", "fx": {"double_attack": 0.05}},
	"double_8": {"text": "8% шанс второй автоатаки", "fx": {"double_attack": 0.08}},
	"crit_20": {"text": "Критические удары сильнее на 20%", "fx": {"crit_power": 0.2}},
	"boss_8": {"text": "+8% урона по боссам", "fx": {"boss_bonus": 0.08}},
	"exec_15": {"text": "+15% урона по целям ниже 30% здоровья", "fx": {"execute_bonus": 0.15}},
	"thorns_10": {"text": "10% полученного урона возвращается врагу", "fx": {"thorns": 0.1}},
	"thorns_18": {"text": "18% полученного урона возвращается врагу", "fx": {"thorns": 0.18}},
	"shield_15": {"text": "Щиты прочнее на 15%", "fx": {"shield_bonus": 0.15}},
	"shield_25": {"text": "Щиты прочнее на 25%", "fx": {"shield_bonus": 0.25}},
	"start_8": {"text": "В начале похода щит на 8% здоровья", "fx": {"start_shield": 0.08}},
	"start_12": {"text": "В начале похода щит на 12% здоровья", "fx": {"start_shield": 0.12}},
	"cd_8": {"text": "8% шанс, что заклинание не уйдёт на перезарядку", "fx": {"cd_refund": 0.08}},
	"dot_10": {"text": "Периодический урон выше на 10%", "fx": {"dot_bonus": 0.1}},
	"dot_15": {"text": "Периодический урон выше на 15%", "fx": {"dot_bonus": 0.15}},
	"aoe_12": {"text": "Урон по площади выше на 12%", "fx": {"aoe_bonus": 0.12}},
	"cast_6": {"text": "Чтение заклинаний быстрее на 6%", "fx": {"cast_speed": 0.06}},
	"cast_10": {"text": "Чтение заклинаний быстрее на 10%", "fx": {"cast_speed": 0.1}},
	"heal_6": {"text": "Лечение сильнее на 6%", "fx": {"heal_bonus": 0.06}},
	"heal_10": {"text": "Лечение сильнее на 10%", "fx": {"heal_bonus": 0.1}},
	"proc_slash": {"text": "10% шанс при ударе нанести Рассечение", "fx": {"procs": [{"sid": "cleave", "chance": 0.1, "scale": 0.7}]}},
	"proc_shot": {"text": "10% шанс при ударе дать Усмиряющий выстрел", "fx": {"procs": [{"sid": "tranq", "chance": 0.1, "scale": 0.8}]}},
	"proc_bolt": {"text": "10% шанс при ударе выпустить Чародейский обстрел", "fx": {"procs": [{"sid": "arcane_bolt", "chance": 0.1, "scale": 0.7}]}},
	# legendary
	"twin_wind": {"text": "30% шанс выпустить вторую стрелу", "fx": {"double_attack": 0.3}},
	"storm_bow": {"text": "12% шанс при выстреле обрушить Цепную молнию", "fx": {"procs": [{"sid": "chain_lightning", "chance": 0.12, "scale": 0.8}]}},
	"hunter_eye": {"text": "Прицельный выстрел сильнее на 40%, криты сильнее на 20%", "fx": {"spell:aimed_shot": 0.4, "crit_power": 0.2}},
	"serpent": {"text": "Укус змеи сильнее на 60%, весь периодический урон на 10%", "fx": {"spell:serpent_sting": 0.6, "dot_bonus": 0.1}},
	"rain": {"text": "Град стрел сильнее на 50%, 10% шанс сброса перезарядки", "fx": {"spell:arrow_rain": 0.5, "cd_refund": 0.1}},
	"beast": {"text": "Призванный зверь сильнее на 60%", "fx": {"spell:beast": 0.6}},
	"cold_blood": {"text": "Критические удары сильнее на 50%", "fx": {"crit_power": 0.5}},
	"first_flame": {"text": "Огненный шар сильнее на 35%, 15% шанс добавить Поджог", "fx": {"spell:fireball": 0.35, "procs": [{"sid": "ignite", "chance": 0.15, "scale": 1.0}]}},
	"frost": {"text": "Ледяная стрела сильнее на 50%, 15% шанс сброса перезарядки", "fx": {"spell:frostbolt": 0.5, "cd_refund": 0.15}},
	"storm_crown": {"text": "Цепная молния сильнее на 40%, 10% шанс повторить её", "fx": {"spell:chain_lightning": 0.4, "procs": [{"sid": "chain_lightning", "chance": 0.1, "scale": 0.7}]}},
	"sparks": {"text": "Чародейский обстрел сильнее на 40%, чтение быстрее на 10%", "fx": {"spell:arcane_bolt": 0.4, "cast_speed": 0.1}},
	"abyss": {"text": "Семя порчи и Живая бомба сильнее на 50%", "fx": {"spell:seed": 0.5, "spell:living_bomb": 0.5}},
	"haunt": {"text": "Блуждающий дух сильнее на 50%, периодический урон на 15%", "fx": {"spell:haunt": 0.5, "dot_bonus": 0.15}},
	"mercy": {"text": "Исцеление сильнее на 35%, чтение быстрее на 15%", "fx": {"spell:heal": 0.35, "cast_speed": 0.15}},
	"chalice": {"text": "Цепное исцеление и Быстрина сильнее на 40%", "fx": {"spell:chain_heal": 0.4, "spell:riptide": 0.4}},
	"forest": {"text": "Буйный рост сильнее на 60%, Обновление на 40%", "fx": {"spell:wild_growth": 0.6, "spell:renew": 0.4}},
	"ward": {"text": "Щиты прочнее на 50%", "fx": {"shield_bonus": 0.5}},
	"prayer": {"text": "Молитва и Искупление сильнее на 40%", "fx": {"spell:prayer": 0.4, "spell:penance": 0.4}},
	"executioner": {"text": "Казнь сильнее на 60%, +20% урона по целям ниже 30% здоровья", "fx": {"spell:execute": 0.6, "execute_bonus": 0.2}},
	"verdict": {"text": "Сокрушительный удар сильнее на 40%, криты сильнее на 30%", "fx": {"spell:mortal_strike": 0.4, "crit_power": 0.3}},
	"seven_blades": {"text": "Вихрь клинка и Вихрь стали сильнее на 40%, 10% шанс второго удара", "fx": {"spell:whirlwind": 0.4, "spell:bladestorm": 0.4, "double_attack": 0.1}},
	"bloodletter": {"text": "10% урона лечат героя, 20% шанс второго удара", "fx": {"lifesteal": 0.1, "double_attack": 0.2}},
	"thunder": {"text": "10% шанс при ударе выпустить Цепную молнию", "fx": {"procs": [{"sid": "chain_lightning", "chance": 0.1, "scale": 0.8}]}},
	"rend": {"text": "Рваная рана сильнее на 60%, периодический урон на 20%", "fx": {"spell:rend": 0.6, "dot_bonus": 0.2}},
	"kingslayer": {"text": "+20% урона по боссам", "fx": {"boss_bonus": 0.2}},
	"last_stand": {"text": "30% полученного урона возвращается врагу, Удар щитом сильнее на 40%", "fx": {"thorns": 0.3, "spell:shield_slam": 0.4}},
	"avenger": {"text": "Щит мстителя сильнее на 50%, +10% урона по боссам", "fx": {"spell:avenger": 0.5, "boss_bonus": 0.1}},
	"mountain": {"text": "Удар грома и Ударная волна сильнее на 50%", "fx": {"spell:thunder_clap": 0.5, "spell:shockwave": 0.5}},
	"retribution": {"text": "Щит возмездия сильнее на 50%, 15% урона возвращается врагу", "fx": {"spell:vengeance": 0.5, "thorns": 0.15}},
	"unbending": {"text": "В начале похода щит на 20% здоровья", "fx": {"start_shield": 0.2}},
}

const AOE_KINDS := ["aoe_damage", "channel_aoe", "explosive", "seed"]

# ---------------------------------------------------------------- building

static func tier_of(ilvl: int) -> int:
	return clampi((ilvl - 1) / ILVL_PER_TIER, 0, 5)

static func role_of(weapons: Array) -> String:
	if "staff" in weapons:
		return "caster"
	if "bow" in weapons:
		return "ranged"
	return "tank" if "shield" in weapons else "melee"

## Random item of this quality. Empty slot, weapon type and role are picked here.
static func roll(rng: RandomNumberGenerator, ilvl: int, quality: int, slot: String, wtype: String, role: String) -> Dictionary:
	if wtype != "":
		slot = "offhand" if wtype == "shield" else "weapon"
		if role == "" or (wtype == "shield") != (role == "tank") and not wtype in ROLE_WEAPONS.get(role, []):
			role = WEAPON_ROLE[wtype]
	if role == "":
		role = ROLES[rng.randi_range(0, ROLES.size() - 1)]
	if slot == "offhand" and wtype == "":
		wtype = "shield"
	elif slot == "weapon" and wtype == "":
		var weapons: Array = ROLE_WEAPONS[role]
		wtype = weapons[rng.randi_range(0, weapons.size() - 1)]
	var id := "i%08x%08x" % [rng.randi(), rng.randi()]
	var atype := ""
	if wtype == "" and slot in ["head", "armor", "hands", "legs", "feet"]:
		var kinds: Array = ROLE_ARMOR[role]
		atype = kinds[rng.randi_range(0, kinds.size() - 1)]
	var tier := tier_of(ilvl)
	if quality >= RARE:
		var key := _pick_named(rng, role, tier, wtype if wtype != "" else slot, quality, atype)
		if key != "":
			return make(key, ilvl, id)
		quality = mini(quality, RARE)
	return _make_plain(rng, ilvl, quality, slot, wtype, atype, role, id)

static func _pick_named(rng: RandomNumberGenerator, role: String, tier: int, slot_key: String, quality: int, atype: String) -> String:
	var pool := []
	if quality == LEGENDARY:
		for t in range(tier, -1, -1):
			for key in ItemCatalog.INDEX.get("%s|%d|%s|%d" % [role, t, slot_key, quality], []):
				pool.append(key)
		if pool.is_empty():   # legendaries live in few slots: take any of the role
			for key in ItemCatalog.NAMED:
				var spec: Dictionary = ItemCatalog.NAMED[key]
				if int(spec["q"]) == LEGENDARY and spec["role"] == role and int(spec["tier"]) <= tier:
					pool.append(key)
	else:
		for key in ItemCatalog.INDEX.get("%s|%d|%s|%d" % [role, tier, slot_key, quality], []):
			if atype == "" or ItemCatalog.NAMED[key].get("atype", "") == atype:
				pool.append(key)
	return "" if pool.is_empty() else pool[rng.randi_range(0, pool.size() - 1)]

## Named item at an item level.
static func make(key: String, ilvl: int, id: String) -> Dictionary:
	var spec: Dictionary = ItemCatalog.NAMED[key]
	var it := assemble(id, spec["name"], spec["slot"], spec.get("wtype", ""), spec.get("atype", ""), spec["role"], int(spec["q"]), ilvl, spec["st"], spec["look"])
	it["key"] = key
	if spec.has("effect"):
		it["effect"] = spec["effect"]
	return it

static func _make_plain(rng: RandomNumberGenerator, ilvl: int, quality: int, slot: String, wtype: String, atype: String, role: String, id: String) -> Dictionary:
	var tier := tier_of(ilvl)
	var base: String
	var look: String
	if wtype != "":
		base = ItemCatalog.BASES["weapon"][wtype][tier]
		look = "%s_t%d" % [wtype, tier + 1]
	elif atype != "":
		base = ItemCatalog.BASES["armor"][atype][slot][tier]
		look = "%s_%s_t%d" % [atype, slot, tier + 1]
	else:
		base = ItemCatalog.BASES["amulet"][tier]
		look = "amulet_%s_t%d" % [role, tier + 1]
		slot = "trinket"
	var shares := {}
	var name := base
	if quality == POOR:
		name = base + " (изношено)"
	elif quality == UNCOMMON:
		var suffixes: Array = SUFFIXES[role]
		var suffix: Array = suffixes[rng.randi_range(0, suffixes.size() - 1)]
		name = "%s %s" % [base, suffix[0]]
		shares = suffix[1]
	return assemble(id, name, slot, wtype, atype, role, quality, ilvl, shares, look)

static func assemble(id: String, name: String, slot: String, wtype: String, atype: String, role: String, quality: int, ilvl: int, shares: Dictionary, look: String) -> Dictionary:
	var it := {"id": id, "slot": slot, "name": name, "rarity": quality, "ilvl": ilvl, "affixes": [], "role": role, "look": look}
	if wtype != "":
		var wt: Dictionary = Loot.WEAPON_TYPES[wtype]
		it["wtype"] = wtype
		if float(wt["dmg"]) > 0.0:
			it["dmg"] = round(float(wt["dmg"]) * (ilvl + 1) * float(WEAPON_QUALITY[quality]) * 0.92)
		it["affixes"].append({"stat": wt["implicit"][0], "value": round(float(wt["implicit"][1]) * ilvl * minf(1.0, float(WEAPON_QUALITY[quality])) * 0.85), "imp": true})
	if atype != "":
		it["atype"] = atype
		it["affixes"].append({"stat": "armor", "value": maxf(1.0, round(Loot.STAT_PER_ILVL["armor"] * ilvl * float(ARMOR_SHARE[atype]) * float(SLOT_WEIGHT[slot]))), "imp": true})
	for stat in shares:
		it["affixes"].append({"stat": stat, "value": stat_value(stat, float(shares[stat]), quality, slot, ilvl)})
	return it

## A stat taking `share` of the budget of an item.
static func stat_value(stat: String, share: float, quality: int, slot: String, ilvl: int) -> float:
	var budget: float = float(BUDGET[quality]) * float(SLOT_WEIGHT[slot])
	if Loot.FLAT_STATS.has(stat):
		return snappedf(Loot.FLAT_STATS[stat] * share * budget, 0.001)
	return maxf(1.0, round(Loot.STAT_PER_ILVL[stat] * ilvl * share * budget))

# ---------------------------------------------------------------- effects

static func effects_of(gear: Dictionary) -> Array:
	var out := []
	for slot in gear:
		var it = gear[slot]
		if it != null and it.has("effect"):
			out.append(it["effect"])
	return out

static func effect_text(id: String) -> String:
	return str(EFFECTS.get(id, {}).get("text", ""))

## Sums the fx of worn effects: same keys add up, procs are listed.
static func combine(effects: Array) -> Dictionary:
	var out := {}
	for id in effects:
		var fx: Dictionary = EFFECTS.get(id, {}).get("fx", {})
		for k in fx:
			if k == "procs":
				if not out.has("procs"):
					out["procs"] = []
				out["procs"].append_array(fx[k])
			else:
				out[k] = float(out.get(k, 0.0)) + float(fx[k])
	return out

## Added share of damage from gear effects for one hit.
static func damage_bonus(fx: Dictionary, sid: String, kind: String, is_dot: bool, school: String, boss: bool, target_frac: float) -> float:
	var bonus: float = fx.get("spell:" + sid, 0.0)
	bonus += float(fx.get("physical_bonus" if school == "physical" else "magic_bonus", 0.0))
	if is_dot:
		bonus += float(fx.get("dot_bonus", 0.0))
	if kind in AOE_KINDS:
		bonus += float(fx.get("aoe_bonus", 0.0))
	if boss:
		bonus += float(fx.get("boss_bonus", 0.0))
	if target_frac < 0.3:
		bonus += float(fx.get("execute_bonus", 0.0))
	return bonus
