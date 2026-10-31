#!/usr/bin/env python3
"""Builds the brief for the gear artist: prompt, templates cut from the rig atlas,
the list of files to draw and the tools to check them.

    python tools/build_art_brief.py [out.zip]
"""
import gzip
import io
import json
import sys
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RIG = ROOT / 'assets/characters/rig'
SOURCE = ROOT / 'tools/art_brief'
WEAPONS = ['sword', 'greatsword', 'staff', 'shield', 'bow']
SLOT_PARTS = {
    'head': ['head'], 'armor': ['chest', 'hem', 'upper_r', 'upper_l'], 'hands': ['fore_r', 'fore_l', 'fist_r', 'fist_l', 'palm_r', 'palm_l'],
    'legs': ['thigh_r', 'thigh_l', 'shin_r', 'shin_l'], 'feet': ['boot_r', 'boot_l'],
}
PILOT = {'plate_head_t3', 'plate_armor_t3', 'plate_hands_t3', 'plate_legs_t3', 'plate_feet_t3', 'sword_t3', 'shield_t3'}
# clip, share of the clip: rest, a wind-up and a hit, so bent joints show up.
POSES = {
    'shield': [('idle_shield', 0.), ('sword_right_slash_shield', .3), ('sword_right_slash_shield', .55), ('cast_hold_shield', 0.)],
    'greatsword': [('idle_greatsword', 0.), ('cast_hold_greatsword', 0.)],
    'staff': [('idle_staff', 0.), ('cast_hold_staff', 0.)],
    'bow': [('idle_bow', 0.), ('cast_hold_bow', 0.)],
}


def png(im):
    out = io.BytesIO()
    im.save(out, 'PNG', optimize=True)
    return out.getvalue()


def main():
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'async_hero_gear_brief.zip'
    z = zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED)
    z.write(SOURCE / 'PROMPT.md', 'PROMPT.md')
    z.write(SOURCE / 'check_gear.py', 'tools/check_gear.py')
    z.write(SOURCE / 'preview_gear.py', 'tools/preview_gear.py')
    parts_spec, poses_spec, sizes, heads = {}, {}, {}, {}
    for sex in ('male', 'female'):
        rig = json.loads(gzip.open(RIG / ('clips_%s.json.gz' % sex)).read())
        skeleton, clips = rig['skeleton'], rig['clips']
        atlas = Image.open(RIG / ('atlas_%s.png' % sex)).convert('RGBA')
        z.write(RIG / ('atlas_%s.png' % sex), 'reference/atlas_%s.png' % sex)
        z.write(RIG / ('head_%s.png' % sex), 'templates/%s/head.png' % sex)
        head = Image.open(RIG / ('head_%s.png' % sex))
        heads[sex] = list(head.size)
        parts = {}
        for part, info in skeleton['parts'].items():
            folder = 'weapons' if part in WEAPONS else sex
            for layer in ('ink', 'fill'):
                x, y, w, h = info[layer]
                if part not in WEAPONS or sex == 'male':   # weapons are the same for both bodies
                    z.writestr('templates/%s/%s_%s.png' % (folder, part, layer), png(atlas.crop((x, y, x + w, y + h))))
            slot = next((s for s, names in SLOT_PARTS.items() if part in names), 'weapon' if part in WEAPONS else None)
            parts[part] = dict(size=info['ink'][2:], origin=info['origin'], slot=slot)
            sizes.setdefault(sex, {})[part] = info['ink'][2:]
        parts_spec[sex] = dict(parts=parts, skeleton={k: v for k, v in skeleton.items() if k not in ('parts', 'fields')})
        fields = skeleton['fields']
        poses_spec[sex] = []
        for loadout, picks in POSES.items():
            for clip, share in picks:
                frames = clips[clip]['frames']
                poses_spec[sex].append(dict(clip=clip, loadout=loadout, values=dict(zip(fields, frames[int(share * (len(frames) - 1))]))))
    z.writestr('spec/parts.json', json.dumps(parts_spec, indent=1))
    z.writestr('spec/poses.json', json.dumps(poses_spec))

    art = json.loads((ROOT / 'docs/items/items_for_art.json').read_text(encoding='utf8'))
    looks = []

    def body_files(key, slot):
        files = []
        for sex in ('male', 'female'):
            for part in SLOT_PARTS[slot]:
                size = heads[sex] if part == 'head' else sizes[sex][part]
                entry = dict(path='%s/%s/%s.png' % (key, sex, part), size=size)
                entry['template'] = 'templates/%s/%s.png' % (sex, 'head' if part == 'head' else part + '_ink')
                files.append(entry)
        return files

    def weapon_files(key, wtype):
        return [dict(path='%s/weapon.png' % key, size=sizes['male'][wtype])]

    for look in art['looks']:
        if look['render'] == 'icon_only':
            continue
        key = look['key']
        entry = dict(key=key, description_en=look['description_en'], tier=look['tier'], used_by=look['used_by'])
        if look['render'] == 'on_body':
            entry.update(slot=look['slot'], armor_type=look.get('armor_type'), files=body_files(key, look['slot']))
        else:
            entry.update(weapon_type=look['weapon_type'], files=weapon_files(key, look['weapon_type']))
        if key in PILOT:
            entry['pilot'] = True
        looks.append(entry)
    for item in art['crafted']:
        key = item['look']
        entry = dict(key=key, description_ru=item['name'], crafted_by=item['profession'], used_by=1)
        if item['wtype']:
            entry.update(weapon_type=item['wtype'], files=weapon_files(key, item['wtype']))
        else:
            entry.update(slot=item['slot'], files=body_files(key, item['slot']))
        looks.append(entry)
    total = sum(len(e['files']) for e in looks)
    z.writestr('spec/looks.json', json.dumps(dict(looks_total=len(looks), files_total=total, looks=looks), ensure_ascii=False, indent=1))
    z.close()
    print('%s: %d looks, %d files to draw, pilot %d files, %d KB' % (target.name, len(looks), total,
          sum(len(e['files']) for e in looks if e.get('pilot')), target.stat().st_size // 1024))


if __name__ == '__main__':
    main()
