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
