#!/usr/bin/env python3
"""Puts drawn gear on the hero in several poses, the way the game draws it.

    python tools/preview_gear.py output plate_head_t3,plate_armor_t3 --weapon sword_t3 --offhand shield_t3
    python tools/preview_gear.py        (no gear: shows the bare hero)

Writes preview_male.png and preview_female.png into the current folder.
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image

BRIEF = Path(__file__).resolve().parents[1]
RES = 2
CANVAS = (900, 920)
ANCHOR = (24, 0)      # Sprite units to shift the hero by, so wide poses stay on the canvas.
SHIELD_OFFSET = (6., 0.)
SLOTS = {'upper_r': 'armor', 'upper_l': 'armor', 'chest': 'armor', 'hem': 'armor',
         'fore_r': 'hands', 'fore_l': 'hands', 'fist_r': 'hands', 'fist_l': 'hands', 'palm_r': 'hands', 'palm_l': 'hands',
         'thigh_r': 'legs', 'thigh_l': 'legs', 'shin_r': 'legs', 'shin_l': 'legs', 'boot_r': 'feet', 'boot_l': 'feet'}


def ray(at, degrees, length):
    a = math.radians(degrees)
    return at[0] + math.cos(a) * length, at[1] + math.sin(a) * length


def turn(v, degrees):
    a = math.radians(degrees)
    return v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a)


def add(a, b):
    return a[0] + b[0], a[1] + b[1]


def solve(s, p):
    hip = (p['hx'], p['hy'])
    waist = add(hip, turn(s['waist'], p['ha']))
    bones = {'hem': (hip, p['ha'], 1.), 'chest': (waist, p['ca'], 1.), 'head': (add(waist, turn(s['neck'], p['ca'])), p['na'], 1.)}
    for i, side in enumerate('rl'):
        v = lambda k: p[side + k]
        shoulder = add(waist, turn((v('sx'), v('sy')), p['ca']))
        elbow = ray(shoulder, v('ua'), s['l1'] * v('uf'))
        wrist = ray(elbow, v('fa'), s['l2'])
        joint = add(hip, turn((s['hipx'][i], 0.), p['ha']))
        knee = ray(joint, v('ta'), s['lt'])
        ankle = ray(knee, v('ca'), s['ls'])
        bones.update({'upper_' + side: (shoulder, v('ua'), v('uf')), 'fore_' + side: (elbow, v('fa'), 1.), 'hand_' + side: (wrist, v('ha'), 1.),
                      'thigh_' + side: (joint, v('ta'), 1.), 'shin_' + side: (knee, v('ca'), 1.), 'boot_' + side: (ankle, v('ba'), 1.)})
    bones['grip_r'] = ray(bones['hand_r'][0], p['rha'], s['grip'])
    bones['grip_l'] = ray(bones['hand_l'][0], p['lha'], s['grip'])
    return bones


def blit(canvas, im, bone, origin):
    """Draws `im` with its corner at `origin` sprite units in the frame of `bone`."""
    at, angle, stretch = bone
    a = math.radians(angle)
    c, n = math.cos(a), math.sin(a)
    x0, y0 = (at[0] + ANCHOR[0]) * RES, (at[1] + ANCHOR[1]) * RES
    # Inverse map: canvas pixel -> image pixel.
    coeffs = (c / stretch, n / stretch, (-c * x0 - n * y0) / stretch - origin[0] * RES,
              -n, c, n * x0 - c * y0 - origin[1] * RES)
    canvas.alpha_composite(im.transform(CANVAS, Image.AFFINE, coeffs, Image.BILINEAR))


class Hero:
    def __init__(self, sex, output, gear, weapon, offhand):
        self.sex, self.output = sex, output
        self.spec = json.loads((BRIEF / 'spec/parts.json').read_text(encoding='utf8'))[sex]
        self.poses = json.loads((BRIEF / 'spec/poses.json').read_text(encoding='utf8'))[sex]
        self.gear, self.weapon, self.offhand = gear, weapon, offhand
        self.folder = BRIEF / 'templates' / sex

    def part(self, name, layer):
        folder = BRIEF / 'templates/weapons' if name in ('sword', 'greatsword', 'staff', 'shield', 'bow') else self.folder
        return Image.open(folder / ('%s_%s.png' % (name, layer))).convert('RGBA')

    def worn(self, part):
        look = self.gear.get(SLOTS.get(part, part))
        path = self.output / look / self.sex / (part + '.png') if look and self.output else None
        return Image.open(path).convert('RGBA') if path and path.exists() else None

    def limbs(self, canvas, bones, items):
        for layer in ('ink', 'fill'):
            for part, bone in items:
                blit(canvas, self.part(part, layer), bones[bone], self.spec['parts'][part]['origin'])
        for part, bone in items:
            im = self.worn(part)
            if im:
                blit(canvas, im, bones[bone], self.spec['parts'][part]['origin'])

    def held(self, canvas, name, at, angle, look):
        origin = self.spec['parts'][name]['origin']
        im = None
        if look and self.output and (self.output / look / 'weapon.png').exists():
            im = Image.open(self.output / look / 'weapon.png').convert('RGBA')
        if im:
            blit(canvas, im, (at, angle, 1.), origin)
        else:
            for layer in ('ink', 'fill'):
                blit(canvas, self.part(name, layer), (at, angle, 1.), origin)

    def draw(self, pose):
        p = pose['values']
        s = self.spec['skeleton']
        bones = solve(s, p)
        loadout = pose['loadout']
        canvas = Image.new('RGBA', CANVAS, (74, 106, 90, 255))
        hand_r = ('palm_r' if p['ro'] > .5 else 'fist_r', 'hand_r')
        hand_l = ('palm_l' if p['lo'] > .5 else 'fist_l', 'hand_l')
        far = [('upper_l', 'upper_l'), ('fore_l', 'fore_l')]
        on_top = p['lz'] > .5
        if not on_top:
            far.append(hand_l)
        self.limbs(canvas, bones, far)
        self.limbs(canvas, bones, [('thigh_l', 'thigh_l'), ('shin_l', 'shin_l')])
        self.limbs(canvas, bones, [('boot_l', 'boot_l')])
        self.limbs(canvas, bones, [('thigh_r', 'thigh_r'), ('shin_r', 'shin_r')])
        self.limbs(canvas, bones, [('boot_r', 'boot_r')])
        self.limbs(canvas, bones, [('hem', 'hem'), ('chest', 'chest')])
        if loadout == 'shield':
            self.held(canvas, 'shield', add(bones['grip_l'], turn(SHIELD_OFFSET, 0.)), p['w2a'], self.offhand)
        elif loadout == 'bow':
            self.held(canvas, 'bow', bones['grip_l'], p['w2a'], self.weapon)
        if on_top:
            self.limbs(canvas, bones, [hand_l])
        main = {'sword': 'sword', 'shield': 'sword', 'dual': 'sword', 'staff': 'staff', 'greatsword': 'greatsword'}.get(loadout)
        at = ray(bones['grip_l'], p['w1a'], s['gap']) if loadout == 'greatsword' else bones['grip_r']
        behind = p['wz'] < .5
        if main and behind:
            self.held(canvas, main, at, p['w1a'], self.weapon)
        neck = s['neck_rest']
        box = (s['head_box'][0] - neck[0], s['head_box'][1] - neck[1])
        blit(canvas, Image.open(self.folder / 'head.png').convert('RGBA'), bones['head'], box)
        helm = self.worn('head')
        if helm:
            blit(canvas, helm, bones['head'], box)
        self.limbs(canvas, bones, [('upper_r', 'upper_r'), ('fore_r', 'fore_r')])
        if main and not behind:
            self.held(canvas, main, at, p['w1a'], self.weapon)
        self.limbs(canvas, bones, [hand_r])
        return canvas


def option(name):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return None


def main():
    values = {option('--weapon'), option('--offhand')}
    args = [a for a in sys.argv[1:] if not a.startswith('--') and a not in values]
    output = Path(args[0]) if args else None
    gear = {}
    for look in (args[1].split(',') if len(args) > 1 else []):
        for slot in ('head', 'armor', 'hands', 'legs', 'feet'):
            if '_%s_' % slot in look:
                gear[slot] = look
    weapon, offhand = option('--weapon'), option('--offhand')
    for sex in ('male', 'female'):
        hero = Hero(sex, output, gear, weapon, offhand)
        wanted = 'staff' if weapon and weapon.startswith('staff') else 'bow' if weapon and weapon.startswith('bow') else 'greatsword' if weapon and weapon.startswith('greatsword') else 'shield'
        poses = [p for p in hero.poses if p['loadout'] == wanted]
        sheet = Image.new('RGB', (CANVAS[0] * len(poses), CANVAS[1]))
        for i, pose in enumerate(poses):
            sheet.paste(hero.draw(pose).convert('RGB'), (i * CANVAS[0], 0))
        sheet.save('preview_%s.png' % sex)
        print('preview_%s.png: %d poses' % (sex, len(poses)))


if __name__ == '__main__':
    main()
