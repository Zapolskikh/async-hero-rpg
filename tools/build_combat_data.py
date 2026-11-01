"""Reproducible combat definitions; placeholder icons are created only for missing files."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
def gd(value):
    return json.dumps(value, ensure_ascii=False, indent='\t')

branches = [('arcane', 'Чародейство', 'power'), ('life', 'Жизнь', 'hp'), ('bulwark', 'Оплот', 'armor'), ('assault', 'Натиск', 'atk')]
talents = {}
def branch(key, rows):
    for i, row in enumerate(rows):
        ident, name, ranks, desc, *extra = row
        data = dict(name=name, branch=key, tier=i//4, ranks=ranks, desc=desc,
                    icon='tal_'+ident)
        if extra:
            data.update(extra[0])
        talents[ident] = data

branch('arcane', [
 ('focus','Средоточие',5,'+3% силы заклинаний за ранг.',dict(stat='power',pct=.03)),
 ('fast_cast','Быстрый каст',5,'Время произнесения заклинаний −3% за ранг.'),
 ('spell_crit','Чародейская точность',3,'+2 п.п. крита атакующих заклинаний за ранг.'),
 ('long_burn','Долгое горение',3,'Периодический магический урон действует на 1 с дольше за ранг.'),
 ('ignition','Воспламенение',3,'Крит заклинания оставляет горение: 10/20/30% урона за 4 с.'),
 ('residual','Остаточная энергия',2,'Каст даёт щит на 15/30% силы заклинаний на 6 с. Обновляется.'),
 ('carry_fire','Догорание',3,'При смерти цели переносит 30/60/100% остатка твоего DoT на врага без него.'),
 ('spark','Искра',3,'Первое прямое атакующее заклинание волны: +30/60/90% силы заклинаний урона.'),
 ('echo','Отзвук',3,'Атакующее заклинание с кастом повторяется с шансом 10/20/30% и 50% силы.'),
 ('flame_feed','Подпитка пламенем',3,'Каждый импульс твоего магического DoT сокращает глобальное ожидание на 0,1/0,2/0,3 с.'),
 ('focused_aoe','Сосредоточенный разряд',3,'Массовые заклинания наносят на 10/20/30% больше урона, если враг один.'),
 ('countercast','Контрзаклинание',3,'Успешное прерывание с шансом 33/66/100% делает следующий каст мгновенным.'),
 ('hot_flame','Раскалённое пламя',3,'Магический DoT может критовать с шансом 10/20/30%.'),
 ('reflection','Отражение заклинаний',5,'Шанс отразить направленное атакующее заклинание: 10/20/30/40/50%.'),
 ('opening_silence','Молчание',1,'В начале каждой волны накладывает на врагов безмолвие на 5 с.'),
 ('fire_totem','Огненный тотем',3,'На всю волну: каждые 3 с огненный шар на 40/60/80% силы заклинаний.'),
])
branch('life', [
 ('life_gift','Дар жизни',5,'+3% исходящего лечения за ранг.'),
 ('life_health','Крепкое здоровье',5,'+3% максимального здоровья за ранг.',dict(stat='hp',pct=.03)),
 ('care','Бережный уход',3,'Периодическое лечение длится на 1/2/3 с дольше.'),
 ('respite','Передышка',3,'В конце волны лечит наиболее раненого: 5/10/15% его здоровья за 6 с.'),
 ('reserve','Запас жизни',3,'10/20/30% избыточного прямого лечения становится щитом, до 10% здоровья цели.'),
 ('passing_care','Переходящая забота',3,'Импульс HoT на здоровой цели переносит 30/60/100% лечения раненому союзнику.'),
 ('clean_slate','Чистый лист',3,'Очищение защищает от следующего DoT на 2/4/6 с.'),
 ('steady_hand','Уверенная рука',3,'Каст прямого лечения −5/10/15%.'),
 ('healing_trail','Целительный след',3,'Прямое лечение оставляет 10/20/30% своей силы как HoT на 4 с.'),
 ('living_cover','Живой покров',3,'Прямое лечение цели с твоим HoT вызывает дополнительный импульс на 30/60/100% силы.'),
 ('shared_care','Общая забота',3,'Другой раненый союзник получает 10/20/30% фактически восстановленного прямым лечением.'),
 ('emergency','Экстренная помощь',3,'Мгновенное прямое лечение вне очереди ниже 25% здоровья. КД 25/20/15 с.'),
 ('life_source','Источник жизни',3,'Твой фактический урон здоровью врага лечит каждого союзника на 1/3/5%.'),
 ('resurrection','Воскрешение',1,'Один раз за заход воскрешает погибшего союзника с 50% здоровья, пока герой жив.'),
 ('life_legacy','Завещание жизни',4,'Один раз за заход смерть героя даёт союзникам щиты на 25/50/75/100% их здоровья на 10 с.'),
 ('healing_totem','Тотем исцеления',3,'На всю волну: каждые 3 с лечит самого раненого на 20/30/40% силы заклинаний.'),
])
branch('bulwark', [
 ('toughness','Стойкость',5,'+3% максимального здоровья за ранг.',dict(stat='hp',pct=.03)),
 ('armor_training','Закалённая броня',4,'+5% брони за ранг.',dict(stat='armor',pct=.05)),
 ('readiness','Боевая готовность',3,'В начале каждой волны щит на 5/10/15% максимального здоровья.'),
 ('warrior_strength','Сила воина',4,'+4% силы за ранг.',dict(stat='str',pct=.04)),
 ('full_block','Полное блокирование',3,'Со щитом: 10/20/30% шанса полностью блокировать прямой физический удар.',dict(w='shield')),
 ('retaliation','Возмездие',3,'Возвращает 10/20/30% физического урона, снявшего здоровье.'),
 ('intercept','Перехват',3,'10/20/30% шанса перенаправить вражеское заклинание с союзника на себя.'),
 ('mortal_wounds','Смертельные удары',1,'Двуручные попадания снижают получаемое целью лечение на 50% на 6 с.',dict(w='greatsword')),
 ('wide_swing','Широкий замах',3,'Автоатаки двуручником задевают второго врага с 15/30/45% силы.',dict(w='greatsword')),
 ('deep_defense','Глухая оборона',4,'Ниже 50% здоровья получаемый урон −10/20/30/40%.'),
 ('unstoppable','Неудержимый удар',3,'Автоатака двуручником с шансом 10/20/30% даёт дополнительное попадание с 50% силы.',dict(w='greatsword')),
 ('unshaken','Непоколебимость',3,'Со щитом: 20/40/60% шанса избежать оглушения.',dict(w='shield')),
 ('undying','Несокрушимость',1,'Один раз за заход смертельный удар оставляет 1 HP и щит на 30% здоровья на 5 с.'),
 ('deep_wounds','Глубокие раны',4,'Крит двуручным оружием вызывает кровотечение на 10/20/30/40% урона за 6 с.',dict(w='greatsword')),
 ('caster_punish','Кара заклинателю',3,'Успешный сбой каста Ударом щитом: +200/300/400% силы урона.',dict(w='shield')),
 ('relentless','Неотступный страж',4,'Провокация действует на 2/4/6/8 с дольше.'),
])
branch('assault', [
 ('weapon_master','Мастер оружия',5,'+3% урона автоатак мечом и луком за ранг.'),
 ('accuracy','Меткость',5,'+1 п.п. крита оружейных атак за ранг.'),
 ('quick_hands','Быстрые руки',3,'Интервал автоатак −3/6/9%.'),
 ('poison_blades','Отравленные клинки',3,'Попадания мечом: 10/20/30% шанса отравить на 60% силы за 6 с.',dict(w='sword')),
 ('throwing','Метание',3,'Меч позволяет использовать выстрелы на 60/80/100% силы, от силы вместо ловкости.',dict(w='sword')),
 ('stunning_hit','Оглушающий удар',3,'Автоатаки мечом: 5/10/15% шанса оглушить на 1 с.',dict(w='sword')),
 ('kill_shot','Смертельный выстрел',1,'Казнь доступна с луком и рассчитывается от ловкости.',dict(w='bow')),
 ('battle_rhythm','Боевой ритм',3,'Попадания автоатак сокращают перезарядки способностей на 0,1/0,2/0,3 с.'),
 ('breathless','Сбитое дыхание',1,'Успешное прерывание накладывает безмолвие на 5 с.'),
 ('piercing_shot','Сквозной выстрел',4,'Одиночное попадание с луком: 10/20/30/40% шанса поразить всех врагов.',dict(w='bow')),
 ('strong_swing','Сильный замах',4,'Урон оружейных способностей +4/8/12/16%.'),
 ('focused_cleave','Сосредоточенное рассечение',3,'С мечом массовые оружейные способности сильнее на 10/20/30%, если враг один.',dict(w='sword')),
 ('weak_hunt','Охота на слабых',1,'Одиночные атаки с луком выбирают врага с наименьшей долей HP. Провокация важнее.',dict(w='bow')),
 ('sunder','Раскол брони',5,'Автоатаки снижают броню цели на 10/20/30/40/50% на 6 с. Не складывается.'),
 ('duelist','Дуэлянт',4,'Если враг один, весь урон +5/10/15/20%.'),
 ('paired_blades','Парные клинки',3,'Два меча: автоатака с шансом 20/40/60% даёт второе попадание на 50% силы; оно может наложить яд.',dict(w='dual')),
])
for b, _, _ in branches:
    assert sum(t['ranks'] for t in talents.values() if t['branch']==b)==51
header = 'class_name Talents\nextends RefCounted\n\nconst FIRST_LEVEL := 5\nconst POINTS_PER_LEVEL := 2\nconst MAX_RANK := 5\nconst GATES := [0, 10, 20, 30]\n'
header += 'const BRANCHES := '+gd([dict(id=b,name=n,icon=i) for b,n,i in branches])+'\nconst TALENTS := '+gd(talents)+'\n'
header += '''
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
'''
(ROOT/'scripts/data/talents.gd').write_text(header,encoding='utf-8')

spells={}
def spell(ident,name,group,kind,mult,cd=0,cast=0,rarity=0,desc='',**kwargs):
    spells[ident]=dict(name=name,group=group,kind=kind,mult=mult,cd=float(cd),cast=float(cast),rarity=rarity,
        desc=desc,fx=kwargs.pop('fx','orb'),color=kwargs.pop('color',{'melee':'#ece4cc','ranged':'#e5c994','bulwark':'#80bcf0','arcane':'#b58dff','life':'#84e4ab','universal':'#ffe7a1'}[group]),tags=kwargs.pop('tags',['dps']),**kwargs)

spell('kick','Пинок','universal','interrupt',0.4,8.0,0.0,0,desc='Реактивно сбивает доступный каст вне очереди. Любое оружие.',fx='slash',color='#ffe7a1',tags=['interrupt'],stat='str')
spell('cleanse','Очищение','universal','cleanse',0.6,0.0,0.0,0,desc='Снимает отрицательные эффекты и немного лечит союзника.',fx='cleanse',color='#a5ffb6',tags=['cleanse','heal'])
spell('purge','Развеивание','universal','purge',0,0.0,0.0,1,desc='Снимает один положительный эффект противника, включая щит.',fx='cleanse',color='#ffe7a1',tags=['dps'])
spell('bash','Оглушение','universal','stun',0.5,12.0,0.0,1,desc='Оглушение на 2 с и сбой каста. Боссы не оглушаются.',fx='stun',color='#ffe7a1',tags=['control'],dur=2.0,stat='str')
spell('battle_cry','Боевой клич','universal','buff_all',0,24.0,0.0,0,desc='Физический урон всей группы +30% на 8 с. Перезарядка короче на 3% за уровень.',fx='shout',color='#ffbb29',tags=['dps'],cd_lvl=0.03,dur=8.0,buff='physical',value=0.3)
spell('bloodlust','Жажда крови','universal','buff_all',0,30.0,0.0,2,desc='Касты и интервал применения способностей группы ускоряются на 30% на 8 с. Перезарядка короче на 3% за уровень.',fx='shout',color='#bf7fff',tags=['dps'],cd_lvl=0.03,dur=8.0,buff='bloodlust',value=0.3)
spell('rally','Ободряющий клич','universal','rally',0,24.0,0.0,1,desc='Временно даёт группе 20% максимального и текущего здоровья на 8 с.',fx='shout',color='#ffbb29',tags=['dps'],dur=8.0)
spell('prism','Священная призма','universal','prism',1.4,12.0,0.0,2,desc='Урон врагу и лечение всей группы в размере 60% силы удара.',fx='prism',color='#fff0a0',tags=['dps'])
spell('mass_dispel','Массовое рассеивание','universal','mass_dispel',0,12.0,1.0,3,desc='Очищает группу и снимает по одному положительному эффекту с врагов. Перезарядка короче на 3% за уровень.',fx='cleanse',color='#ffe7a1',tags=['dps'],cd_lvl=0.03)
spell('shatter','Сокрушительный бросок','universal','damage',1.5,10.0,0.0,1,desc='Удар от лучшей атакующей характеристики; тройной урон поглощению.',fx='blade',color='#ffe7a1',tags=['dps'],stat='best',school='physical',shield_bonus=3.0)
spell('fireball','Огненный шар','arcane','damage',2.8,0.0,1.5,0,desc='Сильный каст. По цели под твоим Поджогом урон +25%.',fx='fire',color='#ff8a2a',tags=['dps'])
spell('arcane_bolt','Чародейский обстрел','arcane','damage',1.8,0.0,0.0,0,desc='Мгновенный магический удар. Любое оружие.',fx='arcane',color='#b68aff',tags=['dps'])
spell('ignite','Поджог','arcane','dot',0.3,0.0,0.0,0,desc='Небольшой удар и горение 8 с. Усиливает твой Огненный шар.',fx='fire',color='#ff672d',tags=['dot'],dur=8.0,initial=0.5)
spell('frostbolt','Ледяная стрела','arcane','damage',2.1,8.0,1.5,1,desc='Урон и замедление автоатак на 20% на 6 с.',fx='frost',color='#9be8ff',tags=['dps'],debuff='slow',value=0.2,dur=6.0)
spell('weakness','Проклятие слабости','arcane','debuff',0,12.0,0.0,1,desc='Весь урон всех врагов −15% на 12 с.',fx='curse',color='#bb72c9',tags=['dps'],debuff='weakness',aoe=True,value=0.15,dur=12.0)
spell('chain_lightning','Цепная молния','arcane','aoe_damage',1.4,8.0,1.5,2,desc='Молния поражает до трёх врагов. Работает по одной цели.',fx='lightning',color='#9cdeff',tags=['dps'],max_targets=3)
spell('haunt','Блуждающий дух','arcane','damage',1.6,10.0,1.5,2,desc='Удар; твой DoT по цели +20%. Когда дух возвращается, лечит тебя на силу удара.',fx='spirit',color='#ba99ee',tags=['dps'],debuff='haunt',value=0.2,dur=10.0)
spell('living_bomb','Живая бомба','arcane','dot',0.25,10.0,0.0,1,desc='Горение 6 с, затем взрыв по всем врагам. Взрывается и при смерти цели.',fx='fire',color='#ff9d35',tags=['dot','aoe'],dur=6.0,explosion=1.3)
spell('seed','Семя порчи','arcane','seed',2.1,12.0,1.5,3,desc='Семя взрывается по всем врагам после урона цели в 300% силы заклинаний или её смерти.',fx='curse',color='#a26ad6',tags=['dps'],dur=12.0)
spell('heal','Исцеление','life','heal',3.8,0.0,1.5,0,desc='Сильное прямое лечение наиболее раненого союзника.',fx='heal',color='#75ed93',tags=['heal'],threshold=0.7)
spell('renew','Обновление','life','hot',0.35,4.0,0.0,0,desc='Периодическое лечение одного раненого союзника на 8 с.',fx='nature',color='#83e878',tags=['heal'],dur=8.0,threshold=0.9)
spell('barrier','Барьер','life','shield',3.0,8.0,0.0,0,desc='Поглощающий щит на переднего союзника без щита.',fx='shield',color='#83ceff',tags=['shield'],dur=8.0)
spell('riptide','Быстрина','life','riptide',1.5,8.0,0.0,1,desc='Мгновенное лечение и HoT на 6 с.',fx='water',color='#6de5db',tags=['heal'],dur=6.0,tick_mult=0.25,threshold=0.75)
spell('wild_growth','Буйный рост','life','hot_all',0.5,12.0,1.0,3,desc='Лечение группы на 6 с: первые импульсы сильнее последних.',fx='nature',color='#8ef09c',tags=['heal'],dur=6.0,threshold=0.85,decay=True)
spell('chain_heal','Цепное исцеление','life','chain_heal',2.6,8.0,2.0,1,desc='Лечит до трёх раненых союзников: 100%, 65%, 42% силы.',fx='heal_chain',color='#b4ffd2',tags=['heal'],threshold=0.8)
spell('earth_shield','Щит земли','life','earth_shield',1.05,12.0,0.0,2,desc='Пять зарядов: получение урона лечит владельца. Заряд не чаще раза в 2 с.',fx='earth',color='#d2be7a',tags=['heal'],dur=20.0,charges=5)
spell('penance','Искупление','life','penance',0.9,10.0,0.0,1,desc='Три импульса: лечит раненого союзника или атакует врага, если лечение не требуется.',fx='holy',color='#fff0b0',tags=['heal','dps'],channel=2.0,pulses=3,threshold=0.75)
spell('prayer','Молитва восстановления','life','prayer',1.6,14.0,0.0,2,desc='Пять лечебных зарядов. После урона лечит владельца и перескакивает на другого союзника.',fx='prayer',color='#ffe997',tags=['heal'],dur=20.0,charges=5)
spell('pain_suppression','Подавление боли','life','suppress',0,20.0,0.0,2,desc='Вне очереди: союзник ниже 30% здоровья получает на 40% меньше урона 6 с.',fx='holy',color='#fff0b0',tags=['heal'],dur=6.0,value=0.4,threshold=0.3)
spell('taunt','Провокация','bulwark','taunt',0,12.0,0.0,0,desc='Враги выбирают тебя 6 с. Применяется по готовности; последняя провокация важнее.',fx='shout',color='#ff7060',tags=['tank'],dur=6.0)
spell('shield_slam','Удар щитом','bulwark','stun',1.2,9.0,0.0,0,desc='Удар щитом, прерывание и оглушение 1 с. Боссу можно сбить доступный каст.',fx='shield_hit',color='#80bcf0',tags=['tank','interrupt'],dur=1.0,stat='str',req=['shield'],school='physical',weapon=True,reactive=True)
spell('shield_wall','Стена щитов','bulwark','buff_self',0,18.0,0.0,0,desc='Получаемый урон −40% на 5 с. Требует щит.',fx='shield',color='#80bcf0',tags=['tank'],dur=5.0,buff='wall',value=0.4,req=['shield'])
spell('thunder_clap','Удар грома','bulwark','aoe_damage',1.05,10.0,0.0,1,desc='Урон всем и замедление автоатак на 20% на 6 с. Любое оружие.',fx='shockwave',color='#80bcf0',tags=['dps'],stat='str',school='physical',debuff='slow',value=0.2,dur=6.0)
spell('shockwave','Ударная волна','bulwark','aoe_damage',1.1,16.0,0.0,3,desc='Урон всем врагам и оглушение на 1 с.',fx='shockwave',color='#80bcf0',tags=['dps'],stat='str',school='physical',stun=1.0)
spell('avenger','Щит мстителя','bulwark','aoe_damage',1.2,12.0,0.0,1,desc='Щит отскакивает к трём врагам; основной цели сбивает каст.',fx='shield_throw',color='#80bcf0',tags=['dps'],stat='str',req=['shield'],school='physical',weapon=True,max_targets=3,interrupt=True)
spell('vengeance','Щит возмездия','bulwark','self_shield',3.0,18.0,0.0,3,desc='Щит на себя; при разрушении или истечении взрывается на 50% поглощённого урона. Любое оружие.',fx='shield',color='#80bcf0',tags=['dps'],dur=8.0,stat='best',vengeance=True)
spell('intervene','Вмешательство','bulwark','intervene',0,15.0,0.0,1,desc='6 с принимаешь на себя половину урона по самому раненому союзнику. Любое оружие.',fx='shield',color='#80bcf0',tags=['tank'],dur=6.0,value=0.5,threshold=0.8)
spell('strike','Кровожадность','melee','damage',1.8,6.0,0.0,0,desc='Удар мечом, лечит себя на 20% фактического урона здоровью.',fx='slash',color='#ece4cc',tags=['dps'],stat='str',req=['sword','greatsword'],school='physical',weapon=True,leech=0.2)
spell('mortal_strike','Сокрушительный удар','melee','damage',2.35,6.0,0.0,0,desc='Тяжёлый удар, игнорирует 30% брони цели. С двуручником сильнее на 20%.',fx='heavy',color='#ece4cc',tags=['dps'],stat='str',req=['sword','greatsword'],school='physical',weapon=True,armor_pen=0.3,bonus={'w':'greatsword','mult':1.2})
spell('rend','Рваная рана','melee','dot',0.29,0.0,0.0,0,desc='Удар и кровотечение 8 с. Кровотечение обходит броню.',fx='bleed',color='#d94f55',tags=['dot'],dur=8.0,initial=0.5,stat='str',req=['sword','greatsword'],school='physical',weapon=True)
spell('cleave','Рассечение','melee','aoe_damage',1.35,5.0,0.0,1,desc='Удар максимум по двум врагам. Доступен против одного.',fx='slash',color='#ece4cc',tags=['dps'],stat='str',req=['sword','greatsword'],school='physical',weapon=True,max_targets=2)
spell('whirlwind','Вихрь клинка','melee','aoe_damage',0.95,8.0,0.0,1,desc='Урон всем врагам. Работает и по одной цели.',fx='whirlwind',color='#ece4cc',tags=['dps'],stat='str',req=['sword','greatsword'],school='physical',weapon=True,bonus={'w':'greatsword','mult':1.2})
spell('execute','Казнь','melee','execute',4.5,6.0,0.0,1,desc='Сильный удар по врагу ниже 30% здоровья. С талантом доступен с луком.',fx='heavy',color='#ece4cc',tags=['dps'],threshold=0.3,stat='str',req=['sword','greatsword'],school='physical',weapon=True,bonus={'w':'greatsword','mult':1.2})
spell('death_strike','Удар смерти','melee','damage',1.7,12.0,0.0,2,desc='Удар и лечение на 30% здоровья, потерянного за последние 5 с, минимум 5% максимального HP.',fx='spirit',color='#ece4cc',tags=['dps'],stat='str',req=['sword','greatsword'],school='physical',weapon=True,death_heal=True)
spell('bladestorm','Вихрь стали','melee','channel_aoe',1.1,20.0,0.0,3,desc='Три массовых удара за 2 с. Во время серии другие способности не применяются.',fx='whirlwind',color='#ece4cc',tags=['dps'],channel=2.0,pulses=3,stat='str',req=['sword','greatsword'],school='physical',weapon=True)
spell('aimed_shot','Прицельный выстрел','ranged','damage',3.0,0.0,1.5,0,desc='Сильный одиночный выстрел с подготовкой. Это оружейное действие, не магический каст.',fx='arrow',color='#e5c994',tags=['dps'],stat='agi',req=['bow'],school='physical',weapon=True)
spell('serpent_sting','Укус змеи','ranged','dot',0.35,0.0,0.0,0,desc='Яд на 8 с. Выстрел химеры обновляет его.',fx='poison_arrow',color='#8dd851',tags=['dot'],dur=8.0,stat='agi',req=['bow'],weapon=True)
spell('chimera','Выстрел химеры','ranged','damage',1.8,9.0,0.0,2,desc='Урон, обновление твоего Укуса змеи и немедленный урон в размере 40% его полной силы.',fx='poison_arrow',color='#8fe0af',tags=['dps'],stat='agi',req=['bow'],school='physical',weapon=True)
spell('explosive','Разрывной выстрел','ranged','explosive',1.8,12.0,0.0,1,desc='Стрела взрывается через 2 с по всем врагам. Один взрыв на применение.',fx='fire_arrow',color='#ff9545',tags=['dps'],dur=2.0,stat='agi',req=['bow'],weapon=True)
spell('tranq','Усмиряющий выстрел','ranged','damage',1.2,8.0,0.0,1,desc='Урон и снятие одного положительного эффекта противника.',fx='arrow',color='#e5c994',tags=['dps'],stat='agi',req=['bow'],school='physical',weapon=True,purge=True)
spell('arrow_rain','Град стрел','ranged','channel_aoe',0.65,10.0,0.0,1,desc='Три залпа по всем врагам за 2 с, по дальним врагам урон +50%. Работает против одного.',fx='arrow_rain',color='#e5c994',tags=['dps'],channel=2.0,pulses=3,stat='agi',req=['bow'],school='physical',weapon=True,ranged_bonus=0.5)
spell('beast','Призыв зверя','ranged','summon',1.0,20.0,0.0,3,desc='Призывает зверя на 10 с: атакует каждые 2 с. Любое оружие, не занимает место в группе.',fx='beast',color='#e5c994',tags=['dps'],dur=10.0,stat='best')
spell('hunters_mark','Метка охотника','ranged','mark',0,10.0,0.0,1,desc='Цель получает на 10% больше урона от всей группы 10 с.',fx='arrow',color='#e5c994',tags=['dps'],dur=10.0,value=0.1,req=['bow'])
assert len(spells)==53
db=ROOT/'scripts/data/db.gd'
text=db.read_text(encoding='utf-8')
start=text.index('\t# --- Player spells')
end=text.index('\t# --- Enemy spells ---')
lines=['\t# --- Player spells: generated by tools/build_combat_data.py ---\n']
for ident,s in spells.items():
    lines.append('\t'+gd(ident)+': '+json.dumps(s,ensure_ascii=False)+',\n')
# Historical IDs remain readable in old expedition snapshots, never drop from boxes.
for old,new in [('poison_cloud','living_bomb'),('drain','haunt'),('twin_strike','strike')]:
    s=dict(spells[new],hidden=True)
    lines.append('\t'+gd(old)+': '+json.dumps(s,ensure_ascii=False)+',\n')
text=text[:start]+''.join(lines)+'\n'+text[end:]
text=text.replace('const THRESHOLD_KINDS := ["heal", "hot_all"]','const THRESHOLD_KINDS := ["heal", "hot", "hot_all", "riptide", "chain_heal", "penance"]')
if 'if stat == "best":' not in text:
    text=text.replace('var stat: String = SPELLS[sid].get("stat", "power")','var stat: String = SPELLS[sid].get("stat", "power")\n\tif stat == "best":\n\t\treturn maxf(float(stats.get("str", 0.0)), maxf(float(stats.get("agi", 0.0)), float(stats.get("power", 0.0))))')
text=text.replace('"agi": "ловкость"}', '"agi": "ловкость", "best": "лучшая атакующая характеристика"}')
db.write_text(text,encoding='utf-8')

# Small, reproducible native pixel art, matching the existing 16px icon language.
from PIL import Image, ImageDraw, ImageFilter
colors={'arcane':'#ae80ed','life':'#74d98c','bulwark':'#79b7ec','assault':'#efb14b','universal':'#f1d47c','melee':'#e68561','ranged':'#94c86b'}
def make_icon(path, group, symbol, variant):
    # User-provided artwork is authoritative. Never replace an installed icon.
    if path.exists():
        return
    img=Image.new('RGBA',(16,16)); d=ImageDraw.Draw(img)
    col=colors[group]; light='#f1f3ed'
    shape={'shield':2,'shield_hit':2,'shield_throw':2,'earth':2,'fire':3,'fire_arrow':5,
           'heal':4,'heal_chain':4,'nature':4,'water':4,'cleanse':4,'holy':4,'prayer':4,
           'arrow':5,'poison_arrow':5,'arrow_rain':5,'lightning':6,'shout':6,'shockwave':6,
           'curse':7,'bleed':1,'heavy':1,'slash':1,'blade':1,'whirlwind':1,'stun':6}.get(symbol,variant%8)
    if shape==0: # spiral orb
        d.ellipse((3,3,12,12),fill=col);d.arc((4,4,11,11),20,300,fill=light,width=2);d.point((8,7),fill=light)
    elif shape==1: # weapon
        d.line((4,12,12,3),fill=light,width=3);d.line((3,9,7,13),fill=col,width=2);d.line((2,14,5,11),fill='#9b744d',width=2)
    elif shape==2: # shield
        d.polygon([(3,3),(12,3),(12,9),(8,14),(3,9)],fill=col);d.line((8,4,8,11),fill=light,width=2)
    elif shape==3: # flame
        d.polygon([(7,1),(10,6),(12,5),(13,11),(9,14),(4,13),(2,9),(5,7)],fill=col);d.polygon([(7,7),(10,12),(6,12)],fill=light)
    elif shape==4: # restorative cross
        d.rectangle((6,2,9,13),fill=col);d.rectangle((2,6,13,9),fill=col);d.point((7,3),fill=light)
    elif shape==5: # arrow
        d.line((2,13,12,3),fill='#c9b58b',width=2);d.polygon([(9,2),(14,1),(13,6)],fill=col);d.line((2,9,6,13),fill=light,width=2)
    elif shape==6: # charged lightning
        d.polygon([(8,1),(3,8),(7,8),(5,14),(13,6),(9,6),(12,1)],fill=col);d.line((8,3,6,6),fill=light)
    else: # rune / chain
        d.arc((2,3,9,10),0,330,fill=col,width=3);d.arc((7,7,14,14),150,480,fill=light,width=2)
    # One small accent distinguishes ranks of similar spell families without text.
    d.point((13,2+variant%3),fill=light)
    alpha=img.getchannel('A'); border=alpha.filter(ImageFilter.MaxFilter(3))
    out=Image.new('RGBA',(16,16),(24,27,39,0));out.putalpha(border);out.alpha_composite(img);out.save(path)
for index,(ident,s) in enumerate(spells.items()):
    make_icon(ROOT/f'assets/icons/sp_{ident}.png',s['group'],s['fx'],index)
for index,(ident,t) in enumerate(talents.items()):
    make_icon(ROOT/f'assets/icons/tal_{ident}.png',t['branch'],'talent',index)
print(f'Generated 64 talents (51 ranks per branch) and {len(spells)} abilities; installed artwork preserved, missing icons filled with placeholders.')

doc=['# Бой v9: таланты и способности\n',
     'Согласованный бесклассовый набор. Числа — начальная настройка для дальнейших игровых проверок.\n',
     '## Правила\n',
     '- Четыре вкладки талантов, по 16 талантов и 51 рангу. Ранг стоит 1 очко; ярусы: 0 / 10 / 20 / 30 очков в своей ветке.\n',
     '- Массовые способности применяются и против одной цели. Таланты повышают урон по единственной цели.\n',
     '- Три слота проверяются слева направо. Прерывания и провокация реактивны; провокация применяется по готовности.\n',
     '- Последняя провокация отменяет предыдущие: после её завершения старое агро не возвращается.\n',
     '- Два меча сохраняют общий базовый урон оружия, но наносят два отдельных попадания с проверками яда.\n',
     '- Броня снижает прямой физический урон; магия и периодический урон обходят броню. Физический блок не блокирует DoT.\n',
     '- Копии и дополнительный урон не запускают рекурсивные цепочки талантов.\n',
     '- Воскрешение, Несокрушимость и Завещание жизни расходуются на весь заход, а не на волну.\n',
     '- Наёмники генерируются из совместимого оружия, трёх случайных способностей и легально распределённых очков талантов. Оценочных тиров нет.\n',
     '## Миграция\n',
     'Таланты старых сохранений сбрасываются с возвратом очков. Уровни и копии заменённых способностей объединяются без потери стоимости улучшений. Старые таймлайны рассчитывают уже заработанные награды; фарм перезапускается с новым составом правил.\n',
     '## Таланты\n']
for bid,name,_ in branches:
    doc += [f'### {name}\n','| Ярус | Талант | Ранги | Эффект |\n|---|---|---|---|\n']
    for t in talents.values():
        if t['branch']==bid:
            doc.append(f"| {t['tier']+1} | {t['name']} | {t['ranks']} | {t['desc']} |\n")
doc += ['\n## Способности\n','Требования оружия относятся к действию, категории не являются классами. Метание разрешает выстрелы с мечом; Смертельный выстрел разрешает Казнь с луком.\n']
for group,name in [('universal','Универсальные'),('arcane','Чародейство'),('life','Жизнь'),('bulwark','Защита'),('melee','Мечи'),('ranged','Охота')]:
    doc += [f'### {name}\n','| Способность | Редкость | Каст / КД | Эффект |\n|---|---|---|---|\n']
    for s in spells.values():
        if s['group']==group:
            doc.append(f"| {s['name']} | {['Обычная','Редкая','Эпическая','Легендарная'][s['rarity']]} | {s['cast']:g} / {s['cd']:g} с | {s['desc']} |\n")
doc += ['\n## Проверки\n','```text\ngodot --headless --script res://tests/run_tests.gd\ngodot --headless --script res://tests/rules_tests.gd\ngodot --headless --script res://tests/combat_revision_tests.gd\ngodot --path . -- --qa --qa-combat\n```\n','`--qa` изолирует запуск от пользовательского сохранения. Визуальный прогон сохраняет изображения в `build/qa/`.\n']
(ROOT/'docs').mkdir(exist_ok=True)
(ROOT/'docs/COMBAT_V9.md').write_text(''.join(doc),encoding='utf-8')
