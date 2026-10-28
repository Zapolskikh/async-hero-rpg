class_name Talents
extends RefCounted

const FIRST_LEVEL := 5
const POINTS_PER_LEVEL := 2
const MAX_RANK := 5
const GATES := [0, 10, 20, 30]
const BRANCHES := [
	{
		"id": "arcane",
		"name": "Чародейство",
		"icon": "power"
	},
	{
		"id": "life",
		"name": "Жизнь",
		"icon": "hp"
	},
	{
		"id": "bulwark",
		"name": "Оплот",
		"icon": "armor"
	},
	{
		"id": "assault",
		"name": "Натиск",
		"icon": "atk"
	}
]
const TALENTS := {
	"focus": {
		"name": "Средоточие",
		"branch": "arcane",
		"tier": 0,
		"ranks": 5,
		"desc": "+3% силы заклинаний за ранг.",
		"icon": "tal_focus",
		"stat": "power",
		"pct": 0.03
	},
	"fast_cast": {
		"name": "Быстрый каст",
		"branch": "arcane",
		"tier": 0,
		"ranks": 5,
		"desc": "Время произнесения заклинаний −3% за ранг.",
		"icon": "tal_fast_cast"
	},
	"spell_crit": {
		"name": "Чародейская точность",
		"branch": "arcane",
		"tier": 0,
		"ranks": 3,
		"desc": "+2 п.п. крита атакующих заклинаний за ранг.",
		"icon": "tal_spell_crit"
	},
	"long_burn": {
		"name": "Долгое горение",
		"branch": "arcane",
		"tier": 0,
		"ranks": 3,
		"desc": "Периодический магический урон действует на 1 с дольше за ранг.",
		"icon": "tal_long_burn"
	},
	"ignition": {
		"name": "Воспламенение",
		"branch": "arcane",
		"tier": 1,
		"ranks": 3,
		"desc": "Крит заклинания оставляет горение: 10/20/30% урона за 4 с.",
		"icon": "tal_ignition"
	},
	"residual": {
		"name": "Остаточная энергия",
		"branch": "arcane",
		"tier": 1,
		"ranks": 2,
		"desc": "Каст даёт щит на 15/30% силы заклинаний на 6 с. Обновляется.",
		"icon": "tal_residual"
	},
	"carry_fire": {
		"name": "Догорание",
		"branch": "arcane",
		"tier": 1,
		"ranks": 3,
		"desc": "При смерти цели переносит 30/60/100% остатка твоего DoT на врага без него.",
		"icon": "tal_carry_fire"
	},
	"spark": {
		"name": "Искра",
		"branch": "arcane",
		"tier": 1,
		"ranks": 3,
		"desc": "Первое прямое атакующее заклинание волны: +30/60/90% силы заклинаний урона.",
		"icon": "tal_spark"
	},
	"echo": {
		"name": "Отзвук",
		"branch": "arcane",
		"tier": 2,
		"ranks": 3,
		"desc": "Атакующее заклинание с кастом повторяется с шансом 10/20/30% и 50% силы.",
		"icon": "tal_echo"
	},
	"flame_feed": {
		"name": "Подпитка пламенем",
		"branch": "arcane",
		"tier": 2,
		"ranks": 3,
		"desc": "Каждый импульс твоего магического DoT сокращает глобальное ожидание на 0,1/0,2/0,3 с.",
		"icon": "tal_flame_feed"
	},
	"focused_aoe": {
		"name": "Сосредоточенный разряд",
		"branch": "arcane",
		"tier": 2,
		"ranks": 3,
		"desc": "Массовые заклинания наносят на 10/20/30% больше урона, если враг один.",
		"icon": "tal_focused_aoe"
	},
	"countercast": {
		"name": "Контрзаклинание",
		"branch": "arcane",
		"tier": 2,
		"ranks": 3,
		"desc": "Успешное прерывание с шансом 33/66/100% делает следующий каст мгновенным.",
		"icon": "tal_countercast"
	},
	"hot_flame": {
		"name": "Раскалённое пламя",
		"branch": "arcane",
		"tier": 3,
		"ranks": 3,
		"desc": "Магический DoT может критовать с шансом 10/20/30%.",
		"icon": "tal_hot_flame"
	},
	"reflection": {
		"name": "Отражение заклинаний",
		"branch": "arcane",
		"tier": 3,
		"ranks": 5,
		"desc": "Шанс отразить направленное атакующее заклинание: 10/20/30/40/50%.",
		"icon": "tal_reflection"
	},
	"opening_silence": {
		"name": "Молчание",
		"branch": "arcane",
		"tier": 3,
		"ranks": 1,
		"desc": "В начале каждой волны накладывает на врагов безмолвие на 5 с.",
		"icon": "tal_opening_silence"
	},
	"fire_totem": {
		"name": "Огненный тотем",
		"branch": "arcane",
		"tier": 3,
		"ranks": 3,
		"desc": "На всю волну: каждые 3 с огненный шар на 40/60/80% силы заклинаний.",
		"icon": "tal_fire_totem"
	},
	"life_gift": {
		"name": "Дар жизни",
		"branch": "life",
		"tier": 0,
		"ranks": 5,
		"desc": "+3% исходящего лечения за ранг.",
		"icon": "tal_life_gift"
	},
	"life_health": {
		"name": "Крепкое здоровье",
		"branch": "life",
		"tier": 0,
		"ranks": 5,
		"desc": "+3% максимального здоровья за ранг.",
		"icon": "tal_life_health",
		"stat": "hp",
		"pct": 0.03
	},
	"care": {
		"name": "Бережный уход",
		"branch": "life",
		"tier": 0,
		"ranks": 3,
		"desc": "Периодическое лечение длится на 1/2/3 с дольше.",
		"icon": "tal_care"
	},
	"respite": {
		"name": "Передышка",
		"branch": "life",
		"tier": 0,
		"ranks": 3,
		"desc": "В конце волны лечит наиболее раненого: 5/10/15% его здоровья за 6 с.",
		"icon": "tal_respite"
	},
	"reserve": {
		"name": "Запас жизни",
		"branch": "life",
		"tier": 1,
		"ranks": 3,
		"desc": "10/20/30% избыточного прямого лечения становится щитом, до 10% здоровья цели.",
		"icon": "tal_reserve"
	},
	"passing_care": {
		"name": "Переходящая забота",
		"branch": "life",
		"tier": 1,
		"ranks": 3,
		"desc": "Импульс HoT на здоровой цели переносит 30/60/100% лечения раненому союзнику.",
		"icon": "tal_passing_care"
	},
	"clean_slate": {
		"name": "Чистый лист",
		"branch": "life",
		"tier": 1,
		"ranks": 3,
		"desc": "Очищение защищает от следующего DoT на 2/4/6 с.",
		"icon": "tal_clean_slate"
	},
	"steady_hand": {
		"name": "Уверенная рука",
		"branch": "life",
		"tier": 1,
		"ranks": 3,
		"desc": "Каст прямого лечения −5/10/15%.",
		"icon": "tal_steady_hand"
	},
	"healing_trail": {
		"name": "Целительный след",
		"branch": "life",
		"tier": 2,
		"ranks": 3,
		"desc": "Прямое лечение оставляет 10/20/30% своей силы как HoT на 4 с.",
		"icon": "tal_healing_trail"
	},
	"living_cover": {
		"name": "Живой покров",
		"branch": "life",
		"tier": 2,
		"ranks": 3,
		"desc": "Прямое лечение цели с твоим HoT вызывает дополнительный импульс на 30/60/100% силы.",
		"icon": "tal_living_cover"
	},
	"shared_care": {
		"name": "Общая забота",
		"branch": "life",
		"tier": 2,
		"ranks": 3,
		"desc": "Другой раненый союзник получает 10/20/30% фактически восстановленного прямым лечением.",
		"icon": "tal_shared_care"
	},
	"emergency": {
		"name": "Экстренная помощь",
		"branch": "life",
		"tier": 2,
		"ranks": 3,
		"desc": "Мгновенное прямое лечение вне очереди ниже 25% здоровья. КД 25/20/15 с.",
		"icon": "tal_emergency"
	},
	"life_source": {
		"name": "Источник жизни",
		"branch": "life",
		"tier": 3,
		"ranks": 3,
		"desc": "Твой фактический урон здоровью врага лечит каждого союзника на 1/3/5%.",
		"icon": "tal_life_source"
	},
	"resurrection": {
		"name": "Воскрешение",
		"branch": "life",
		"tier": 3,
		"ranks": 1,
		"desc": "Один раз за заход воскрешает погибшего союзника с 50% здоровья, пока герой жив.",
		"icon": "tal_resurrection"
	},
	"life_legacy": {
		"name": "Завещание жизни",
		"branch": "life",
		"tier": 3,
		"ranks": 4,
		"desc": "Один раз за заход смерть героя даёт союзникам щиты на 25/50/75/100% их здоровья на 10 с.",
		"icon": "tal_life_legacy"
	},
	"healing_totem": {
		"name": "Тотем исцеления",
		"branch": "life",
		"tier": 3,
		"ranks": 3,
		"desc": "На всю волну: каждые 3 с лечит самого раненого на 20/30/40% силы заклинаний.",
		"icon": "tal_healing_totem"
	},
	"toughness": {
		"name": "Стойкость",
		"branch": "bulwark",
		"tier": 0,
		"ranks": 5,
		"desc": "+3% максимального здоровья за ранг.",
		"icon": "tal_toughness",
		"stat": "hp",
		"pct": 0.03
	},
	"armor_training": {
		"name": "Закалённая броня",
		"branch": "bulwark",
		"tier": 0,
		"ranks": 4,
		"desc": "+5% брони за ранг.",
		"icon": "tal_armor_training",
		"stat": "armor",
		"pct": 0.05
	},
	"readiness": {
		"name": "Боевая готовность",
		"branch": "bulwark",
		"tier": 0,
		"ranks": 3,
		"desc": "В начале каждой волны щит на 5/10/15% максимального здоровья.",
		"icon": "tal_readiness"
	},
	"warrior_strength": {
		"name": "Сила воина",
		"branch": "bulwark",
		"tier": 0,
		"ranks": 4,
		"desc": "+4% силы за ранг.",
		"icon": "tal_warrior_strength",
		"stat": "str",
		"pct": 0.04
	},
	"full_block": {
		"name": "Полное блокирование",
		"branch": "bulwark",
		"tier": 1,
		"ranks": 3,
		"desc": "Со щитом: 10/20/30% шанса полностью блокировать прямой физический удар.",
		"icon": "tal_full_block",
		"w": "shield"
	},
	"retaliation": {
		"name": "Возмездие",
		"branch": "bulwark",
		"tier": 1,
		"ranks": 3,
		"desc": "Возвращает 10/20/30% физического урона, снявшего здоровье.",
		"icon": "tal_retaliation"
	},
	"intercept": {
		"name": "Перехват",
		"branch": "bulwark",
		"tier": 1,
		"ranks": 3,
		"desc": "10/20/30% шанса перенаправить вражеское заклинание с союзника на себя.",
		"icon": "tal_intercept"
	},
	"mortal_wounds": {
		"name": "Смертельные удары",
		"branch": "bulwark",
		"tier": 1,
		"ranks": 1,
		"desc": "Двуручные попадания снижают получаемое целью лечение на 50% на 6 с.",
		"icon": "tal_mortal_wounds",
		"w": "greatsword"
	},
	"wide_swing": {
		"name": "Широкий замах",
		"branch": "bulwark",
		"tier": 2,
		"ranks": 3,
		"desc": "Автоатаки двуручником задевают второго врага с 15/30/45% силы.",
		"icon": "tal_wide_swing",
		"w": "greatsword"
	},
	"deep_defense": {
		"name": "Глухая оборона",
		"branch": "bulwark",
		"tier": 2,
		"ranks": 4,
		"desc": "Ниже 50% здоровья получаемый урон −10/20/30/40%.",
		"icon": "tal_deep_defense"
	},
	"unstoppable": {
		"name": "Неудержимый удар",
		"branch": "bulwark",
		"tier": 2,
		"ranks": 3,
		"desc": "Автоатака двуручником с шансом 10/20/30% даёт дополнительное попадание с 50% силы.",
		"icon": "tal_unstoppable",
		"w": "greatsword"
	},
	"unshaken": {
		"name": "Непоколебимость",
		"branch": "bulwark",
		"tier": 2,
		"ranks": 3,
		"desc": "Со щитом: 20/40/60% шанса избежать оглушения.",
		"icon": "tal_unshaken",
		"w": "shield"
	},
	"undying": {
		"name": "Несокрушимость",
		"branch": "bulwark",
		"tier": 3,
		"ranks": 1,
		"desc": "Один раз за заход смертельный удар оставляет 1 HP и щит на 30% здоровья на 5 с.",
		"icon": "tal_undying"
	},
	"deep_wounds": {
		"name": "Глубокие раны",
		"branch": "bulwark",
		"tier": 3,
		"ranks": 4,
		"desc": "Крит двуручным оружием вызывает кровотечение на 10/20/30/40% урона за 6 с.",
		"icon": "tal_deep_wounds",
		"w": "greatsword"
	},
	"caster_punish": {
		"name": "Кара заклинателю",
		"branch": "bulwark",
		"tier": 3,
		"ranks": 3,
		"desc": "Успешный сбой каста Ударом щитом: +200/300/400% силы урона.",
		"icon": "tal_caster_punish",
		"w": "shield"
	},
	"relentless": {
		"name": "Неотступный страж",
		"branch": "bulwark",
		"tier": 3,
		"ranks": 4,
		"desc": "Провокация действует на 2/4/6/8 с дольше.",
		"icon": "tal_relentless"
	},
	"weapon_master": {
		"name": "Мастер оружия",
		"branch": "assault",
		"tier": 0,
		"ranks": 5,
		"desc": "+3% урона автоатак мечом и луком за ранг.",
		"icon": "tal_weapon_master"
	},
	"accuracy": {
		"name": "Меткость",
		"branch": "assault",
		"tier": 0,
		"ranks": 5,
		"desc": "+1 п.п. крита оружейных атак за ранг.",
		"icon": "tal_accuracy"
	},
	"quick_hands": {
		"name": "Быстрые руки",
		"branch": "assault",
		"tier": 0,
		"ranks": 3,
		"desc": "Интервал автоатак −3/6/9%.",
		"icon": "tal_quick_hands"
	},
	"poison_blades": {
		"name": "Отравленные клинки",
		"branch": "assault",
		"tier": 0,
		"ranks": 3,
		"desc": "Попадания мечом: 10/20/30% шанса отравить на 60% силы за 6 с.",
		"icon": "tal_poison_blades",
		"w": "sword"
	},
	"throwing": {
		"name": "Метание",
		"branch": "assault",
		"tier": 1,
		"ranks": 3,
		"desc": "Меч позволяет использовать выстрелы на 60/80/100% силы, от силы вместо ловкости.",
		"icon": "tal_throwing",
		"w": "sword"
	},
	"stunning_hit": {
		"name": "Оглушающий удар",
		"branch": "assault",
		"tier": 1,
		"ranks": 3,
		"desc": "Автоатаки мечом: 5/10/15% шанса оглушить на 1 с.",
		"icon": "tal_stunning_hit",
		"w": "sword"
	},
	"kill_shot": {
		"name": "Смертельный выстрел",
		"branch": "assault",
		"tier": 1,
		"ranks": 1,
		"desc": "Казнь доступна с луком и рассчитывается от ловкости.",
		"icon": "tal_kill_shot",
		"w": "bow"
	},
	"battle_rhythm": {
		"name": "Боевой ритм",
		"branch": "assault",
		"tier": 1,
		"ranks": 3,
		"desc": "Попадания автоатак сокращают перезарядки способностей на 0,1/0,2/0,3 с.",
		"icon": "tal_battle_rhythm"
	},
	"breathless": {
		"name": "Сбитое дыхание",
		"branch": "assault",
		"tier": 2,
		"ranks": 1,
		"desc": "Успешное прерывание накладывает безмолвие на 5 с.",
		"icon": "tal_breathless"
	},
	"piercing_shot": {
		"name": "Сквозной выстрел",
		"branch": "assault",
		"tier": 2,
		"ranks": 4,
		"desc": "Одиночное попадание с луком: 10/20/30/40% шанса поразить всех врагов.",
		"icon": "tal_piercing_shot",
		"w": "bow"
	},
	"strong_swing": {
		"name": "Сильный замах",
		"branch": "assault",
		"tier": 2,
		"ranks": 4,
		"desc": "Урон оружейных способностей +4/8/12/16%.",
		"icon": "tal_strong_swing"
	},
	"focused_cleave": {
		"name": "Сосредоточенное рассечение",
		"branch": "assault",
		"tier": 2,
		"ranks": 3,
		"desc": "С мечом массовые оружейные способности сильнее на 10/20/30%, если враг один.",
		"icon": "tal_focused_cleave",
		"w": "sword"
	},
	"weak_hunt": {
		"name": "Охота на слабых",
		"branch": "assault",
		"tier": 3,
		"ranks": 1,
		"desc": "Одиночные атаки с луком выбирают врага с наименьшей долей HP. Провокация важнее.",
		"icon": "tal_weak_hunt",
		"w": "bow"
	},
	"sunder": {
		"name": "Раскол брони",
		"branch": "assault",
		"tier": 3,
		"ranks": 5,
		"desc": "Автоатаки снижают броню цели на 10/20/30/40/50% на 6 с. Не складывается.",
		"icon": "tal_sunder"
	},
	"duelist": {
		"name": "Дуэлянт",
		"branch": "assault",
		"tier": 3,
		"ranks": 4,
		"desc": "Если враг один, весь урон +5/10/15/20%.",
		"icon": "tal_duelist"
	},
	"paired_blades": {
		"name": "Парные клинки",
		"branch": "assault",
		"tier": 3,
		"ranks": 3,
		"desc": "Два меча: автоатака с шансом 20/40/60% даёт второе попадание на 50% силы; оно может наложить яд.",
		"icon": "tal_paired_blades",
		"w": "dual"
	}
}

static func points_total(level: int) -> int:
	return max(0, level - FIRST_LEVEL + 1) * POINTS_PER_LEVEL

static func rank_cost(_rank: int) -> int:
	return 1

static func points_spent(talents: Dictionary, branch_id: String = "") -> int:
	var n := 0
	for id in talents:
		if TALENTS.has(id) and (branch_id == "" or TALENTS[id]["branch"] == branch_id):
			n += clampi(int(talents[id]), 0, TALENTS[id]["ranks"])
	return n

static func points_free(hero: Dictionary) -> int:
	return maxi(0, points_total(int(hero["level"])) - points_spent(hero.get("talents", {})))

static func unlocked(id: String, talents: Dictionary) -> bool:
	return points_spent(talents, TALENTS[id]["branch"]) >= GATES[TALENTS[id]["tier"]]

static func _active(t: Dictionary, weapons: Array) -> bool:
	return not t.has("w") or (weapons.count("sword") >= 2 if t["w"] == "dual" else t["w"] in weapons)

static func apply_stats(st: Dictionary, talents: Dictionary, weapons: Array) -> void:
	var bonuses := {}
	for id in talents:
		if not TALENTS.has(id):
			continue
		var t: Dictionary = TALENTS[id]
		if t.has("stat") and _active(t, weapons):
			bonuses[t["stat"]] = bonuses.get(t["stat"], 0.0) + t["pct"] * int(talents[id])
	for stat in bonuses:
		st[stat] = round(float(st.get(stat, 0.0)) * (1.0 + bonuses[stat]))

static func attack_mult(_talents: Dictionary, _weapons: Array) -> float:
	return 1.0 # applied in BattleSim, alongside other conditional damage effects

static func describe(id: String) -> String:
	var t: Dictionary = TALENTS[id]
	var text: String = t["desc"]
	if t.has("w"):
		text += " Требуется: " + Db.WEAPON_LABELS[t["w"]] + "."
	return text
