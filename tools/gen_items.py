#!/usr/bin/env python3
"""Generates the item catalogue in the spirit of WoW Classic.

Writes scripts/data/item_catalog.gd for the game and docs/items/items_for_art.json
for the artists. Names and stat themes live here, the numbers come from the budget
rules in scripts/data/items.gd, so an item can be built at any item level.

    python tools/gen_items.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIERS = 6
ARMOR_SLOTS = ['head', 'armor', 'hands', 'legs', 'feet']

MATERIAL = {
    'cloth': ['из холста', 'из льна', 'из шерсти', 'из шёлка', 'из лунной ткани', 'из звёздной ткани'],
    'leather': ['из сыромятной кожи', 'из дублёной кожи', 'из толстой кожи', 'из кожи ящера', 'из кожи виверны', 'из драконьей кожи'],
    'mail': ['из медных колец', 'из железных колец', 'из стальных колец', 'из чернёных колец', 'из мифриловых колец', 'из драконьей чешуи'],
    'plate': ['из бронзы', 'из железа', 'из стали', 'из чёрной стали', 'из мифрила', 'из адамантита'],
}
NOUNS = {
    'cloth': {'head': ['Капюшон', 'Тюрбан', 'Венец'], 'armor': ['Мантия', 'Роба', 'Одеяние'], 'hands': ['Перчатки', 'Обмотки', 'Наручи'],
              'legs': ['Штаны', 'Поножи', 'Шаровары'], 'feet': ['Туфли', 'Сандалии', 'Башмаки']},
    'leather': {'head': ['Маска', 'Капюшон', 'Шапка'], 'armor': ['Куртка', 'Жилет', 'Панцирь'], 'hands': ['Перчатки', 'Краги', 'Наручи'],
                'legs': ['Штаны', 'Набедренники', 'Поножи'], 'feet': ['Сапоги', 'Мокасины', 'Ботинки']},
    'mail': {'head': ['Шлем', 'Койф', 'Чешуйчатый шлем'], 'armor': ['Кольчуга', 'Хауберк', 'Чешуйчатый доспех'], 'hands': ['Рукавицы', 'Кольчужные перчатки', 'Наручи'],
             'legs': ['Кольчужные поножи', 'Набедренники', 'Чешуйчатые поножи'], 'feet': ['Кольчужные сапоги', 'Тяжёлые сапоги', 'Чешуйчатые сапоги']},
    'plate': {'head': ['Шлем', 'Большой шлем', 'Корона'], 'armor': ['Кираса', 'Латы', 'Нагрудник'], 'hands': ['Латные перчатки', 'Рукавицы', 'Боевые рукавицы'],
              'legs': ['Латные поножи', 'Набедренники', 'Боевые поножи'], 'feet': ['Латные сапоги', 'Сабатоны', 'Боевые сапоги']},
}
WEAPON_BASES = {
    'sword': ['Короткий меч', 'Палаш', 'Сабля', 'Широкий меч', 'Рунный клинок', 'Драконий меч'],
    'greatsword': ['Тяжёлый меч', 'Двуручник', 'Большой меч', 'Цвайхандер', 'Рунный двуручник', 'Драконий двуручник'],
    'shield': ['Деревянный щит', 'Окованный щит', 'Круглый щит', 'Башенный щит', 'Рунный щит', 'Драконий щит'],
    'bow': ['Короткий лук', 'Охотничий лук', 'Длинный лук', 'Составной лук', 'Рунный лук', 'Драконий лук'],
    'staff': ['Простой посох', 'Дубовый посох', 'Резной посох', 'Посох мудреца', 'Рунный посох', 'Драконий посох'],
}
WEAPON_NOUNS = {
    'sword': ['Клинок', 'Палаш', 'Сабля'], 'greatsword': ['Двуручник', 'Цвайхандер', 'Большой клинок'],
    'shield': ['Щит', 'Павеза', 'Эгида'], 'bow': ['Лук', 'Длинный лук', 'Составной лук'], 'staff': ['Посох', 'Жезл', 'Скипетр'],
}
AMULET_BASES = ['Медный медальон', 'Серебряный медальон', 'Амулет с агатом', 'Амулет с опалом', 'Амулет с рубином', 'Амулет с алмазом']
AMULET_NOUNS = ['Амулет', 'Подвеска', 'Ожерелье']
ACCESSORY_NOUNS = ['Оберег', 'Талисман', 'Реликвия']

EPITHETS = {
    'melee': [['Новобранца', 'Наёмника', 'Десятника'], ['Рубаки', 'Дуэлянта', 'Сотника'], ['Ветерана', 'Берсерка', 'Капитана'],
              ['Гладиатора', 'Кровавого Клинка', 'Полководца'], ['Клятвопреступника', 'Бича Демонов', 'Короля-Воителя'], ['Драконоборца', 'Погибели Титанов', 'Завоевателя Миров']],
    'tank': [['Караульного', 'Щитоносца', 'Стража Ворот'], ['Часового', 'Хранителя Моста', 'Защитника Деревни'], ['Рыцаря', 'Несокрушимого', 'Стража Цитадели'],
             ['Паладина', 'Железной Стены', 'Защитника Королевства'], ['Храмовника', 'Нерушимой Клятвы', 'Хранителя Рубежа'], ['Бессмертного Стража', 'Драконьей Твердыни', 'Последнего Бастиона']],
    'ranged': [['Охотника', 'Следопыта', 'Разведчика'], ['Лесничего', 'Траппера', 'Зверолова'], ['Рейнджера', 'Снайпера', 'Ястребиного Глаза'],
               ['Теневого Стрелка', 'Ловчего Виверн', 'Мастера Стрел'], ['Неуловимого', 'Призрачного Лучника', 'Звёздного Следопыта'], ['Драконьего Ловчего', 'Вечной Охоты', 'Князя Стрел']],
    'caster': [['Ученика', 'Заклинателя', 'Адепта'], ['Чародея', 'Мистика', 'Волшебника'], ['Боевого Мага', 'Пиромансера', 'Заклинателя Бурь'],
               ['Архимага', 'Чернокнижника', 'Повелителя Льда'], ['Звёздного Пророка', 'Владыки Пустоты', 'Ткача Судеб'], ['Драконьего Мудреца', 'Вечного Пламени', 'Властелина Магии']],
    'healer': [['Послушника', 'Сиделки', 'Травника'], ['Целителя', 'Монаха', 'Знахаря'], ['Жреца', 'Милосердного', 'Настоятеля'],
               ['Святого Отца', 'Рассветного Пастыря', 'Хранителя Рощи'], ['Светоносца', 'Живых Вод', 'Верховного Жреца'], ['Вечного Рассвета', 'Драконьей Благодати', 'Пророка Жизни']],
}
ROLE_ARMOR = {'melee': ['plate', 'mail'], 'tank': ['plate'], 'ranged': ['leather', 'mail'], 'caster': ['cloth'], 'healer': ['cloth', 'leather']}
ROLE_WEAPONS = {'melee': ['sword', 'greatsword'], 'tank': ['sword', 'shield'], 'ranged': ['bow'], 'caster': ['staff'], 'healer': ['staff']}
ROLE_STATS = {
    'melee': [{'str': .7, 'crit': .3}, {'str': .6, 'hp': .4}, {'str': .6, 'haste': .2, 'crit': .2}],
    'tank': [{'hp': .6, 'armor': .4}, {'hp': .5, 'str': .3, 'armor': .2}, {'armor': .5, 'hp': .5}],
    'ranged': [{'agi': .7, 'crit': .3}, {'agi': .6, 'haste': .4}, {'agi': .6, 'hp': .2, 'crit': .2}],
    'caster': [{'power': .7, 'crit': .3}, {'power': .7, 'haste': .3}, {'power': .6, 'hp': .2, 'crit': .2}],
    'healer': [{'power': .6, 'hp': .4}, {'power': .6, 'haste': .4}, {'power': .5, 'hp': .3, 'haste': .2}],
}
ACCESSORY_EFFECTS = {
    'melee': {3: ['phys_5', 'life_3', 'double_5'], 4: ['phys_8', 'life_5', 'double_8', 'crit_20', 'boss_8', 'exec_15']},
    'tank': {3: ['thorns_10', 'shield_15', 'start_8'], 4: ['thorns_18', 'shield_25', 'start_12', 'life_5', 'boss_8', 'cd_8']},
    'ranged': {3: ['phys_5', 'double_5', 'dot_10'], 4: ['phys_8', 'double_8', 'crit_20', 'dot_15', 'aoe_12', 'cd_8']},
    'caster': {3: ['magic_5', 'cast_6', 'dot_10'], 4: ['magic_8', 'cast_10', 'crit_20', 'dot_15', 'aoe_12', 'cd_8']},
    'healer': {3: ['heal_6', 'shield_15', 'cast_6'], 4: ['heal_10', 'shield_25', 'cast_10', 'cd_8', 'heal_10', 'cast_10']},
}
WEAPON_PROCS = {
    'melee': ['proc_slash', 'double_8', 'life_5', 'crit_20'],
    'tank': ['thorns_18', 'proc_slash', 'life_5', 'boss_8'],
    'ranged': ['proc_shot', 'double_8', 'crit_20', 'boss_8'],
    'caster': ['proc_bolt', 'magic_8', 'crit_20', 'cast_10'],
    'healer': ['heal_10', 'cast_10', 'cd_8', 'shield_25'],
}

# name, slot or weapon type, armor type, role, first tier, effect, look for the artists
LEGENDARIES = [
    ('whisper_of_two_winds', 'Шёпот Двух Ветров', 'bow', '', 'ranged', 2, 'twin_wind', 'pale recurve bow with two parallel strings and wind ribbons'),
    ('song_of_the_storm', 'Песнь Бури', 'bow', '', 'ranged', 3, 'storm_bow', 'dark storm-iron longbow with crackling blue lightning on the limbs'),
    ('eye_of_the_old_hunter', 'Око Старого Ловчего', 'head', 'leather', 'ranged', 3, 'hunter_eye', 'leather hood with a single glowing amber eye sewn on the brow'),
    ('sting_of_the_serpent_mother', 'Жало Змеиной Матери', 'accessory', '', 'ranged', 2, 'serpent', 'curved green fang dripping venom, on a leather cord'),
    ('quiver_of_endless_rain', 'Колчан Вечного Ливня', 'accessory', '', 'ranged', 4, 'rain', 'small silver quiver charm with falling spectral arrows'),
    ('horn_of_the_wild_hunt', 'Рог Дикой Охоты', 'trinket', '', 'ranged', 3, 'beast', 'bone hunting horn pendant carved with running wolves'),
    ('thousand_cuts', 'Перчатки Тысячи Порезов', 'hands', 'leather', 'ranged', 4, 'cold_blood', 'black leather gloves with thin steel blades on each finger'),
    ('staff_of_the_first_flame', 'Посох Первого Пламени', 'staff', '', 'caster', 2, 'first_flame', 'charred staff holding a living orange flame in an iron claw'),
    ('heart_of_eternal_winter', 'Сердце Вечной Зимы', 'staff', '', 'caster', 3, 'frost', 'ice crystal staff with a frozen blue heart at the top'),
    ('crown_of_the_storm_king', 'Корона Грозового Короля', 'head', 'cloth', 'caster', 4, 'storm_crown', 'jagged silver circlet with arcs of lightning between the spikes'),
    ('robe_of_a_thousand_sparks', 'Мантия Тысячи Искр', 'armor', 'cloth', 'caster', 3, 'sparks', 'deep violet robe covered in tiny drifting golden sparks'),
    ('seed_of_the_abyss', 'Семя Бездны', 'accessory', '', 'caster', 4, 'abyss', 'black pulsing seed in a cage of bone, purple glow'),
    ('shroud_of_the_wandering_spirit', 'Саван Блуждающего Духа', 'armor', 'cloth', 'caster', 3, 'haunt', 'tattered translucent grey shroud with a ghostly face in the folds'),
    ('staff_of_mercy', 'Посох Милосердия', 'staff', '', 'healer', 2, 'mercy', 'white ash staff topped with a golden open hand and soft light'),
    ('chalice_of_living_water', 'Чаша Живых Вод', 'accessory', '', 'healer', 3, 'chalice', 'small silver chalice overflowing with glowing turquoise water'),
    ('robe_of_the_blooming_forest', 'Мантия Цветущего Леса', 'armor', 'cloth', 'healer', 3, 'forest', 'green robe woven with living vines and white blossoms'),
    ('reliquary_of_the_first_shield', 'Реликварий Первого Щита', 'trinket', '', 'healer', 4, 'ward', 'gold locket shaped like a tiny shield with a pale blue gem'),
    ('rosary_of_the_saint', 'Чётки Святой', 'accessory', '', 'healer', 4, 'prayer', 'white prayer beads with a radiant sun pendant'),
    ('hand_of_the_executioner', 'Рука Палача', 'greatsword', '', 'melee', 3, 'executioner', 'huge black executioner blade with a blunt tip and red runes'),
    ('final_verdict', 'Смертный Приговор', 'greatsword', '', 'melee', 4, 'verdict', 'massive pale gold greatsword engraved with a skull and scales'),
    ('storm_of_seven_blades', 'Вихрь Семи Клинков', 'sword', '', 'melee', 3, 'seven_blades', 'curved steel sword with seven ghostly blades orbiting it'),
    ('twin_bloodletters', 'Клинок Кровопийца', 'sword', '', 'melee', 2, 'bloodletter', 'dark red serrated sword with blood running along the fuller'),
    ('thunder_fist', 'Громовой Кулак', 'hands', 'plate', 'melee', 4, 'thunder', 'heavy steel gauntlets with crackling blue lightning at the knuckles'),
    ('crimson_sabre', 'Кровавая Сабля', 'sword', '', 'melee', 2, 'rend', 'crimson curved sabre leaving a red trail'),
    ('brand_of_the_kingslayer', 'Клеймо Цареубийцы', 'trinket', '', 'melee', 5, 'kingslayer', 'broken crown pendant with a blood red stone'),
    ('wall_of_the_last_stand', 'Стена Последнего Рубежа', 'shield', '', 'tank', 2, 'last_stand', 'tall iron tower shield with spikes and a burning sigil'),
    ('aegis_of_the_avenger', 'Эгида Мстителя', 'shield', '', 'tank', 3, 'avenger', 'round golden shield with a radiant winged sword emblem'),
    ('helm_of_the_mountain_king', 'Шлем Горного Короля', 'head', 'plate', 'tank', 3, 'mountain', 'massive stone-and-steel crowned helm with a thick beard guard'),
    ('cuirass_of_retribution', 'Кираса Возмездия', 'armor', 'plate', 'tank', 4, 'retribution', 'heavy silver cuirass with a glowing red sun on the chest'),
    ('heart_of_the_unbending', 'Сердце Несгибаемого', 'accessory', '', 'tank', 4, 'unbending', 'iron heart bound with chains, faint golden pulse'),
]

TIER_STYLE = ['crude, worn, simple', 'plain, serviceable', 'well made, some trim', 'ornate, engraved', 'masterwork, glowing runes', 'mythic, dragon motifs, strong glow']
ATYPE_EN = {'cloth': 'cloth', 'leather': 'leather', 'mail': 'chain mail', 'plate': 'steel plate'}
SLOT_EN = {'head': 'helmet or hood', 'armor': 'chest armor', 'hands': 'gloves', 'legs': 'leg armor', 'feet': 'boots'}
WEAPON_EN = {'sword': 'one-handed sword', 'greatsword': 'two-handed greatsword', 'shield': 'shield', 'bow': 'bow', 'staff': 'wizard staff'}
RIG_PARTS = {
    'head': ['head'], 'armor': ['chest', 'hem', 'upper_r', 'upper_l'], 'hands': ['fore_r', 'fore_l', 'fist_r', 'fist_l', 'palm_r', 'palm_l'],
    'legs': ['thigh_r', 'thigh_l', 'shin_r', 'shin_l'], 'feet': ['boot_r', 'boot_l'],
}


def make_catalog():
    bases = {'armor': {}, 'weapon': WEAPON_BASES, 'amulet': AMULET_BASES}
    for atype, slots in NOUNS.items():
        bases['armor'][atype] = {slot: ['%s %s' % (slots[slot][0], MATERIAL[atype][t]) for t in range(TIERS)] for slot in ARMOR_SLOTS}
    named, index = {}, {}

    def add(key, **spec):
        named[key] = spec
        slot_key = spec.get('wtype') or spec['slot']
        index.setdefault('%s|%d|%s|%d' % (spec['role'], spec['tier'], slot_key, spec['q']), []).append(key)

    for role, tiers in EPITHETS.items():
        for tier, names in enumerate(tiers):
            for v, epithet in enumerate(names):
                q = 4 if v == 2 else 3      # two rare lines and one epic line per tier
                shares = ROLE_STATS[role][v]
                prefix = '%s_t%d_%d' % (role, tier, v)
                for atype in ROLE_ARMOR[role]:
                    for slot in ARMOR_SLOTS:
                        add('%s_%s_%s' % (prefix, atype, slot), name='%s %s' % (NOUNS[atype][slot][v], epithet), slot=slot, atype=atype, role=role,
                            tier=tier, q=q, st=shares, look='%s_%s_t%d%s' % (atype, slot, tier + 1, '_epic' if q == 4 else ''))
                for wtype in ROLE_WEAPONS[role]:
                    spec = dict(name='%s %s' % (WEAPON_NOUNS[wtype][v], epithet), slot='offhand' if wtype == 'shield' else 'weapon', wtype=wtype, role=role,
                                tier=tier, q=q, st=shares, look='%s_t%d%s' % (wtype, tier + 1, '_epic' if q == 4 else ''))
                    if q == 4:
                        spec['effect'] = WEAPON_PROCS[role][tier % len(WEAPON_PROCS[role])]
                    add('%s_%s' % (prefix, wtype), **spec)
                add(prefix + '_amulet', name='%s %s' % (AMULET_NOUNS[v], epithet), slot='trinket', role=role, tier=tier, q=q, st=shares, look='amulet_%s_t%d' % (role, tier + 1))
                pool = ACCESSORY_EFFECTS[role][q]
                add(prefix + '_accessory', name='%s %s' % (ACCESSORY_NOUNS[v], epithet), slot='accessory', role=role, tier=tier, q=q, st=shares,
                    effect=pool[(tier + v) % len(pool)], look='accessory_%s_t%d' % (role, tier + 1))
    for key, name, kind, atype, role, tier, effect, look in LEGENDARIES:
        spec = dict(name=name, role=role, tier=tier, q=5, st=ROLE_STATS[role][0], effect=effect, look='legendary_' + key)
        if kind in WEAPON_BASES:
            spec.update(slot='offhand' if kind == 'shield' else 'weapon', wtype=kind)
        else:
            spec.update(slot=kind)
            if atype:
                spec['atype'] = atype
        add(key, **spec)
    return bases, named, index


def gd(value, depth=0):
    """Compact GDScript literal: one catalogue entry per line."""
    if isinstance(value, dict):
        if depth == 0:
            return '{\n' + ''.join('\t%s: %s,\n' % (json.dumps(k, ensure_ascii=False), gd(v, 1)) for k, v in value.items()) + '}'
        return '{' + ', '.join('%s: %s' % (json.dumps(k, ensure_ascii=False), gd(v, depth + 1)) for k, v in value.items()) + '}'
    if isinstance(value, list):
        return '[' + ', '.join(gd(v, depth + 1) for v in value) + ']'
    return json.dumps(value, ensure_ascii=False)


def crafted_items():
    """Crafted gear is drawn too: its recipes live in professions.gd."""
    text = (ROOT / 'scripts/data/professions.gd').read_text(encoding='utf8')
    out = []
    pattern = r'"(\w+)": \{"name": "([^"]+)", "prof": "(blacksmithing|tailoring)"[^\n]*\n[^\n]*\n\s*"item": \{([^\n]*)'
    for m in re.finditer(pattern, text):
        spec = m.group(4)
        if '"rarity": 1,' in spec:    # common gear uses the plain look of its tier
            continue
        slot = re.search(r'"slot": "(\w+)"', spec)
        wtype = re.search(r'"wtype": "(\w+)"', spec)
        out.append(dict(key=m.group(1), name=m.group(2), profession=m.group(3), slot=slot.group(1) if slot else None, wtype=wtype.group(1) if wtype else None))
    return out


def write_art(named):
    looks, items = {}, []

    def look_entry(spec):
        key = spec['look']
        if key in looks:
            looks[key]['used_by'] += 1
            return
        tier, epic = spec['tier'], spec['q'] == 4
        entry = dict(key=key, used_by=1, file='assets/gear/%s.png' % key, role=spec['role'], tier=tier + 1)
        wtype, slot, atype = spec.get('wtype'), spec['slot'], spec.get('atype')
        if spec['q'] == 5:
            entry['description_en'] = LEGEND_LOOK[key]
        elif wtype:
            entry['description_en'] = '%s, %s%s' % (WEAPON_EN[wtype], TIER_STYLE[tier], ', epic version with coloured glow' if epic else '')
        elif atype:
            entry['description_en'] = '%s %s, %s%s' % (ATYPE_EN[atype], SLOT_EN[slot], TIER_STYLE[tier], ', epic version with coloured glow' if epic else '')
        else:
            entry['description_en'] = 'small %s icon for a %s hero, %s' % ('amulet' if slot == 'trinket' else 'trinket charm', spec['role'], TIER_STYLE[tier])
        if wtype:
            entry.update(render='in_hand', weapon_type=wtype)
        elif atype:
            entry.update(render='on_body', slot=slot, armor_type=atype, rig_parts=RIG_PARTS[slot])
        else:
            entry.update(render='icon_only', slot=slot)
        looks[key] = entry

    for key, spec in named.items():
        look_entry(spec)
        items.append(dict(key=key, name=spec['name'], slot=spec['slot'], weapon_type=spec.get('wtype'), armor_type=spec.get('atype'), role=spec['role'],
                          quality=spec['q'], tier=spec['tier'] + 1, effect=spec.get('effect'), look=spec['look']))
    for atype in NOUNS:         # common and uncommon gear uses the plain look of its tier
        for slot in ARMOR_SLOTS:
            for tier in range(TIERS):
                look_entry(dict(look='%s_%s_t%d' % (atype, slot, tier + 1), tier=tier, q=1, slot=slot, atype=atype, role=''))
    for wtype in WEAPON_BASES:
        for tier in range(TIERS):
            look_entry(dict(look='%s_t%d' % (wtype, tier + 1), tier=tier, q=1, slot='weapon', wtype=wtype, role=''))
    crafted = crafted_items()
    for c in crafted:
        c['look'] = 'crafted_' + c['key']
        c['render'] = 'in_hand' if c['wtype'] else 'on_body'
    order = sorted(looks.values(), key=lambda e: (e['render'], e['key']))
    data = dict(
        format=1,
        quality_names=['poor', 'common', 'uncommon', 'rare', 'epic', 'legendary'],
        counts=dict(named_items=len(items), looks_to_draw=len(order), crafted_items=len(crafted)),
        looks=order, crafted=crafted, items=items)
    path = ROOT / 'docs/items/items_for_art.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf8', newline='\n')
    return len(order)


LEGEND_LOOK = {'legendary_' + row[0]: row[7] for row in LEGENDARIES}


def main():
    bases, named, index = make_catalog()
    lines = [
        'class_name ItemCatalog', 'extends RefCounted',
        '## Generated by tools/gen_items.py, do not edit by hand.',
        '## st holds stat shares of the item budget; the numbers come from Items.', '',
        'const BASES := ' + gd(bases), '', 'const NAMED := ' + gd(named), '',
        '## "role|tier|slot or weapon type|quality" -> item keys.',
        'const INDEX := ' + gd(index), '',
    ]
    (ROOT / 'scripts/data/item_catalog.gd').write_text('\n'.join(lines), encoding='utf8', newline='\n')
    looks = write_art(named)
    print('named items: %d, looks to draw: %d' % (len(named), looks))


if __name__ == '__main__':
    main()
