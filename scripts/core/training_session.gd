class_name TrainingSession
extends RefCounted
## Disposable combat state. No profile, collection, expedition or rewards are mutated.
var source: Dictionary
var sim: BattleSim
var rotation: Array = []
var weapons: Array = []
var spell_level := 1
var targets := 1
var retaliation := false
var low_health := false
var paused := false

func _init(snapshot: Dictionary) -> void:
	source = snapshot.duplicate(true)
	weapons = source.get("weapons", []).duplicate()
	for entry in source.get("spells", []):
		if rotation.size() < 3 and entry["id"] in catalog():
			rotation.append(entry["id"])
	while rotation.size() < 3:
		rotation.append("")
	restart()

static func catalog() -> Array:
	return Db.SPELLS.keys().filter(func(id): return not Db.SPELLS[id].get("enemy", false) and not Db.SPELLS[id].get("hidden", false))

func entries() -> Array:
	var out := []
	for id in rotation:
		if id != "":
			out.append({"id": id, "lvl": spell_level})
	return out

func set_spell(slot: int, id: String) -> void:
	if slot < 0 or slot >= 3 or (id != "" and id not in catalog()):
		return
	# One copy per rotation, just like the real loadout.
	var previous: int = rotation.find(id) if id != "" else -1
	if previous >= 0 and previous != slot:
		rotation[previous] = rotation[slot]
	rotation[slot] = id
	var hero: BattleUnit = sim.units[0]
	hero.spells = entries()
	hero.casting.clear()
	hero.channel.clear()
	hero.rot_index = 0
	hero.spell_cd = 0.

func restart() -> void:
	if sim != null:
		sim.release()
	var snap := source.duplicate(true)
	snap["weapons"] = weapons.duplicate()
	snap["ranged"] = "bow" in weapons
	var look: Array = snap.get("look", []).filter(func(layer): return not str(layer[0]).begins_with("w_") and layer[0] not in ["shield", "offhand_sword"])
	if not weapons.is_empty():
		look.append(["w_" + str(weapons[0]), ""])
	if weapons.count("sword") == 2:
		look.push_front(["offhand_sword", ""])
	elif "shield" in weapons:
		look.append(["shield", ""])
	snap["look"] = look
	snap["spells"] = entries()
	# Weapon presets use real weapon timing/formulas and preserve the hero's other stats.
	# With the original weapons the snapshot remains exact, including its offhand damage.
	if weapons != source.get("weapons", []):
		var gear := {}
		for i in weapons.size():
			var type: String = weapons[i]
			gear["weapon" if i == 0 else "offhand"] = {"wtype":type, "dmg":Loot.WEAPON_TYPES[type]["dmg"] * (int(source.get("level", 1)) + 1)}
		snap["stats"].merge(Loot.attack_of(snap["stats"], gear), true)
	var hero := BattleUnit.new(0, 0, 0, snap)
	var allies := [hero]
	for i in 3:
		allies.append(BattleUnit.new(i + 1, 0, i + 1, {"name": ["Рада", "Остап", "Ира"][i], "sprite": "hero", "stats": {"hp": hero.max_hp, "atk": 0., "power": 0.}, "spells": []}))
	var enemies := []
	for i in targets:
		enemies.append({"name": "Манекен %d" % (i + 1), "sprite": "training_dummy", "stats": {"hp": 1.e9, "atk": hero.max_hp * .025 if retaliation else 0., "power": hero.max_hp * .025, "armor": hero.armor}, "spells": [{"id":"e_bolt","lvl":1},{"id":"e_curse","lvl":1},{"id":"e_guard","lvl":1}] if retaliation else []})
	sim = BattleSim.new()
	sim.setup(allies, enemies, 7)
	for ally in allies:
		ally.hp = ally.max_hp * .55
	if low_health:
		for enemy in sim.side_units(1):
			enemy.hp = enemy.max_hp * .2

func advance(delta: float) -> void:
	if not paused:
		sim.advance(delta)

func dispose() -> void:
	if sim != null:
		sim.release()
