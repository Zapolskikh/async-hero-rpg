class_name MercGenerator
extends RefCounted
## Random classless companions. No quality tiers or pre-authored role templates.
static func make(rng: RandomNumberGenerator, level: int, forced_weapons: Array = []) -> Dictionary:
	var choices := [["sword","shield"],["sword","sword"],["greatsword"],["staff"],["bow"]]
	var weapons: Array = choices[rng.randi_range(0,choices.size()-1)]
	if not forced_weapons.is_empty():
		weapons = forced_weapons.duplicate()
	var gear := Roster.empty_gear()
	var pref: Array = ["power","haste","hp"] if weapons.has("staff") else (["agi","crit","hp"] if weapons.has("bow") else ["str","hp","armor"])
	gear["weapon"] = Loot.roll_gear(rng,level,0.,"weapon",weapons[0],pref)
	if weapons.size() > 1:
		gear["offhand"] = Loot.roll_gear(rng,level,0.,"offhand",weapons[1],pref)
	for slot in ["armor","trinket"]:
		gear[slot] = Loot.roll_gear(rng,level,0.,slot,"",pref)
	var talents := {}
	var budget := Talents.points_total(level)
	var preferred: String = "arcane" if weapons.has("staff") else ("assault" if weapons.has("bow") or weapons.count("sword") == 2 else "bulwark")
	if rng.randf() < .25:
		preferred = "life"
	for point in budget:
		var pool := []
		for id in Talents.TALENTS:
			var t: Dictionary = Talents.TALENTS[id]
			if int(talents.get(id,0)) < t["ranks"] and Talents.unlocked(id,talents) and Talents._active(t,weapons):
				pool.append(id)
				if t["branch"] == preferred:
					for weight in 5:
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
	var spells := []
	for id in selected:
		spells.append({"id":id,"lvl":maxi(1,Roster.baseline_spell_level(level)-rng.randi_range(0,1))})
	var base := Db.hero_base_stats(level)
	for stat in ["hp","str","agi","power","armor"]:
		base[stat] = round(base[stat]*rng.randf_range(.9,1.1))
	var st := Roster.apply_gear(base,gear)
	Talents.apply_stats(st,talents,weapons)
	st.merge(Loot.attack_of(st,gear),true)
	var result := {"name":Db.MERC_NAMES[rng.randi_range(0,Db.MERC_NAMES.size()-1)],"color":Roster.MERC_COLORS[rng.randi_range(0,Roster.MERC_COLORS.size()-1)],"npc":true,"role":"Наёмник","level":level,"base_stats":base,"gear":gear,"stats":st,"weapons":weapons,"talents":talents,"spells":spells,"target":"front","id":"m%d"%rng.randi(),"sprite":"hero","ranged":weapons.has("bow") or weapons.has("staff"),"look":Roster.look(gear)}
	result["appearance"] = CharacterAppearance.for_identity(result["id"])
	return result
