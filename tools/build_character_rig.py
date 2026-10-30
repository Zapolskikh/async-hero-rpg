"""Build the hero cut-out rig: V2-proportioned parts, key-posed clips and baked FK frames.

Usage: python tools/build_character_rig.py [--v2 DIR] [--preview DIR] [clip ...]
--v2 points at the extracted async_hero_characters_v2 pack and refreshes the heads.
Everything else is generated from this file. Dependencies: Pillow, NumPy.
"""
from pathlib import Path
import argparse
import gzip
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/characters/rig'
RES = 2      # Atlas pixels per sprite unit.
SS = 4       # Supersampling used while rasterising the polygons.
INK_R = 3.4  # Outline radius in sprite units, matching the V2 line weight.
FPS = 60
PIVOT = (206, 400)
GRIP = 14.   # Hand origin (wrist) to the centre of the fist.
WRIST = 46.  # Largest bend of the wrist away from the forearm axis, degrees.
TWO_HAND_GAP = 25.  # Greatsword: right hand at the guard, left hand towards the pommel.
INK = '#17141d'
PAL = dict(blue='#2479e4', blue_d='#1a5cc0', blue_l='#3b8bee', gold='#fbd56d', gold_d='#e0ad4e',
           skin='#fdc78a', skin_d='#e7a668', glove='#7b4c24', glove_d='#5f3617', glove_l='#96602f',
           pants='#3b3750', pants_d='#2b2839', boot='#7c4c24', boot_d='#5f3617', boot_l='#955c2d',
           belt='#6e431f', belt_d='#4f2d13', steel='#dfe4ec', steel_m='#b9c2d0', steel_d='#7f8a9c',
           guard='#8d97a8', wood='#8a5a2c', wood_d='#5f3a18', wood_l='#a97238', leather='#5f3617',
           purple='#8b45e6', purple_l='#c79bff', purple_d='#5a21a8', shaft='#b99f77', feather='#f2efe6',
           string='#d9dbe2')
FAR_SHADE = 0.86  # The far limbs sit a little deeper in the scene.


SEX = {
    'male': dict(L1=35., L2=33., LT=50., LS=48., hipx=(-17., 17.), waist=(0., -27.), neck=(1., -71.), srest=((-32., -49.), (34., -49.)),
                 arm=13., thigh=19., shin=15., chest=[(-16, -70), (-34, -65), (-46, -54), (-45, -40), (-34, -26), (-29, -2), (-29, 6), (30, 6), (31, -2), (36, -26), (46, -40), (46, -54), (36, -65), (19, -70)],
                 hem=[(-30, -33), (-35, 5), (36, 5), (31, -33)], belt=(-30.5, -9, 31.5, 3), collar=[(-10, -71), (-5, -60), (11, -60), (15, -71)], neckw=(-20, 17)),
    'female': dict(L1=33., L2=32., LT=49., LS=47., hipx=(-14., 16.), waist=(0., -29.), neck=(1., -68.), srest=((-29., -46.), (31., -46.)),
                   arm=12., thigh=17., shin=14., chest=[(-15, -67), (-30, -63), (-41, -52), (-40, -39), (-27, -24), (-21, -4), (-21, 7), (22, 7), (23, -4), (30, -24), (43, -39), (42, -52), (32, -63), (17, -67)],
                   hem=[(-22, -33), (-31, 8), (32, 8), (23, -33)], belt=(-22.5, -6, 23.5, 5), collar=[(-11, -68), (-3, -57), (13, -57), (16, -68)], neckw=(-17, 15)),
}
HIP = (206., 272.)


def d(a):
    return math.radians(a)


def col(name, shade=1.):
    value = PAL.get(name, name)
    rgb = [int(value[i:i + 2], 16) for i in (1, 3, 5)]
    return tuple(round(c * shade) for c in rgb) + (255,)


class Part:
    """Polygons in sprite units around the bone origin; ink is derived from the silhouette."""

    def __init__(self, shade=1.):
        self.items = []
        self.shade = shade
        self.open = []

    def poly(self, points, color):
        self.items.append(('poly', [tuple(map(float, p)) for p in points], color))
        return self

    def circle(self, x, y, r, color):
        self.items.append(('circle', (x, y, r), color))
        return self

    def stroke(self, points, width, color):
        self.items.append(('stroke', [tuple(map(float, p)) for p in points], width, color))
        return self

    def hole(self, x, y, r):
        """Remove the outline around a joint so the limb flows out of its parent."""
        self.open.append((x, y, r))
        return self

    def bounds(self):
        pts = []
        for item in self.items:
            if item[0] == 'circle':
                x, y, r = item[1]
                pts += [(x - r, y - r), (x + r, y + r)]
            elif item[0] == 'stroke':
                w = item[2] / 2
                pts += [(x - w, y - w) for x, y in item[1]] + [(x + w, y + w) for x, y in item[1]]
            else:
                pts += item[1]
        xs, ys = zip(*pts)
        return min(xs), min(ys), max(xs), max(ys)

    def render(self):
        x0, y0, x1, y1 = self.bounds()
        pad = INK_R + 2.
        ox, oy = math.floor(x0 - pad), math.floor(y0 - pad)
        w, h = math.ceil(x1 + pad) - ox, math.ceil(y1 + pad) - oy
        k = RES * SS
        fill = Image.new('RGBA', (w * k, h * k), (0, 0, 0, 0))
        mask = Image.new('L', fill.size, 0)
        pen, ink = ImageDraw.Draw(fill), ImageDraw.Draw(mask)

        def at(p):
            return (p[0] - ox) * k, (p[1] - oy) * k

        rad = INK_R * k
        for item in self.items:
            kind = item[0]
            if kind == 'poly':
                pts = [at(p) for p in item[1]]
                pen.polygon(pts, fill=col(item[2], self.shade))
                ink.polygon(pts, fill=255)
                ink.line(pts + pts[:2], fill=255, width=round(rad * 2))
                for x, y in pts:
                    ink.ellipse((x - rad, y - rad, x + rad, y + rad), fill=255)
            elif kind == 'circle':
                x, y = at(item[1][:2])
                r = item[1][2] * k
                pen.ellipse((x - r, y - r, x + r, y + r), fill=col(item[2], self.shade))
                ink.ellipse((x - r - rad, y - r - rad, x + r + rad, y + r + rad), fill=255)
            else:
                pts = [at(p) for p in item[1]]
                width = item[2] * k
                pen.line(pts, fill=col(item[3], self.shade), width=round(width), joint='curve')
                ink.line(pts, fill=255, width=round(width + rad * 2), joint='curve')
                for x, y in pts:
                    pen.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=col(item[3], self.shade))
                    r = width / 2 + rad
                    ink.ellipse((x - r, y - r, x + r, y + r), fill=255)
        for hx, hy, r in self.open:
            x, y = at((hx, hy))
            ink.ellipse((x - r * k, y - r * k, x + r * k, y + r * k), fill=0)
        size = (w * RES, h * RES)
        fill = premultiplied_resize(fill, size)
        solid = Image.new('RGBA', mask.size, col(INK))
        solid.putalpha(mask)
        return fill, premultiplied_resize(solid, size), (ox, oy)


def premultiplied_resize(image, size):
    array = np.asarray(image, dtype=np.float32) / 255.
    array[..., :3] *= array[..., 3:]
    channels = [np.asarray(Image.fromarray(array[..., i], 'F').resize(size, Image.Resampling.BOX)) for i in range(4)]
    out = np.stack(channels, -1)
    alpha = np.maximum(out[..., 3:], 1e-5)
    out[..., :3] = np.clip(out[..., :3] / alpha, 0., 1.)
    return Image.fromarray((np.clip(out, 0., 1.) * 255. + .5).astype(np.uint8), 'RGBA')


def limb(length, w0, w1, c, dark, shade):
    """Tapered tube along +x with round ends; the dark strip reads as the back of the limb."""
    part = Part(shade)
    part.poly([(0, -w0), (length, -w1), (length, w1), (0, w0)], c)
    part.circle(0, 0, w0, c).circle(length, 0, w1, c)
    part.poly([(0, w0 * .45), (length, w1 * .45), (length, w1), (0, w0)], dark)
    return part


def make_parts(sex):
    s = SEX[sex]
    parts = {}
    a, t, sh = s['arm'], s['thigh'], s['shin']
    for side, shade in (('r', 1.), ('l', FAR_SHADE)):
        upper = limb(s['L1'], a, a - 1, 'blue', 'blue_d', shade)
        if side == 'r':
            upper.hole(0, 0, a + INK_R + 1.5)
        parts['upper_' + side] = upper
        L = s['L2']
        fore = limb(L * .46, a - 1, a - 2, 'blue', 'blue_d', shade)
        fore.poly([(L * .44, -a - .5), (L * .88, -a), (L * .88, a), (L * .44, a + .5)], 'gold')
        fore.poly([(L * .44, a * .45), (L * .88, a * .45), (L * .88, a), (L * .44, a + .5)], 'gold_d')
        fore.poly([(L * .86, -a + 3), (L + 5, -a + 3), (L + 5, a - 3), (L * .86, a - 3)], 'skin_d')
        parts['fore_' + side] = fore
        fist = Part(shade)
        fist.poly([(-3, -13), (16, -15), (26, -13), (30, -6), (30, 8), (25, 14), (-3, 14)], 'skin')
        fist.poly([(-3, -13), (16, -15), (19, -9), (19, 14), (-3, 14)], 'glove')
        fist.poly([(-3, 6), (19, 6), (19, 14), (-3, 14)], 'glove_d')
        fist.poly([(14, -6), (24, -6), (24, 2), (14, 2)], 'skin')
        fist.poly([(22, -13), (26, -13), (26, 12), (22, 12)], 'skin_d')
        parts['fist_' + side] = fist.hole(-4, 0, 7.5)
        palm = Part(shade)
        palm.poly([(-3, -12), (12, -13), (32, -11), (40, -6), (40, 2), (32, 8), (20, 12), (-3, 13)], 'skin')
        palm.poly([(-3, -12), (12, -13), (14, 13), (-3, 13)], 'glove')
        palm.poly([(-3, 6), (14, 6), (14, 13), (-3, 13)], 'glove_d')
        palm.poly([(12, -13), (22, -22), (29, -19), (25, -9)], 'skin')
        palm.poly([(20, 2), (40, 0), (32, 8), (20, 12)], 'skin_d')
        parts['palm_' + side] = palm.hole(-4, 0, 7.5)
        thigh = limb(s['LT'], t, sh + 1, 'pants', 'pants_d', shade)
        parts['thigh_' + side] = thigh
        parts['shin_' + side] = limb(s['LS'], sh + 1, sh, 'pants', 'pants_d', shade)
        boot = Part(shade)
        boot.poly([(-21, -25), (15, -25), (17, -3), (37, 8), (40, 16), (40, 25), (-23, 25)], 'boot')
        boot.poly([(-21, -25), (-11, -25), (-11, 25), (-23, 25)], 'boot_d')
        boot.poly([(-11, 2), (17, -3), (37, 8), (40, 16), (40, 18), (-11, 18)], 'boot_l')
        boot.poly([(-23, 18), (40, 18), (40, 25), (-23, 25)], 'boot_d')
        parts['boot_' + side] = boot

    # Torso coordinates are relative to the waist (hem: to the hip); shoulders stay rounded under the sleeves.
    chest = Part()
    chest.poly(s['chest'], 'blue')
    chest.poly([(s['chest'][3][0] + 12, -40), (s['chest'][6][0] + 8, 6), (s['chest'][6][0], 6), (s['chest'][4][0], -26), (s['chest'][3][0] + 2, -40)], 'blue_d')
    chest.poly([(s['chest'][-3][0] - 16, -60), (s['chest'][-3][0] - 13, -60), (s['chest'][-4][0] - 8, -26), (s['chest'][-5][0] - 4, 4), (s['chest'][-5][0] - 8, 4), (s['chest'][-4][0] - 13, -26)], 'blue_d')
    bx0, by0, bx1, by1 = s['belt']
    chest.poly([(bx0, by0), (bx1, by0), (bx1, by1), (bx0, by1)], 'belt')
    chest.poly([(bx0, by1 - 3), (bx1, by1 - 3), (bx1, by1), (bx0, by1)], 'belt_d')
    n0, n1 = s['neckw']
    chest.poly([(n0, -86), (n1, -86), (n1, -70), (n0, -70)], 'skin')
    chest.poly(s['collar'], 'skin')
    chest.poly([(n0, -80), (n1, -72), (n1, -68), (n0, -71)], 'skin_d')
    parts['chest'] = chest
    hem = Part()
    hem.poly(s['hem'], 'blue')
    hem.poly([s['hem'][0], (s['hem'][0][0] + 7, s['hem'][0][1]), (s['hem'][1][0] + 11, s['hem'][1][1]), s['hem'][1]], 'blue_d')
    parts['hem'] = hem

    def sword(blade, half, guard, grip_back):
        part = Part()
        part.poly([(-grip_back - 6, -7), (-grip_back, -8), (-grip_back + 2, 8), (-grip_back - 6, 7)], 'guard')
        part.poly([(-grip_back, -4.5), (10, -4.5), (10, 4.5), (-grip_back, 4.5)], 'leather')
        part.poly([(16, -half), (blade - 16, -half), (blade, 0), (blade - 16, half), (16, half)], 'steel')
        part.poly([(16, 0), (blade, 0), (blade - 16, half), (16, half)], 'steel_m')
        part.poly([(16, half - 2), (blade - 16, half - 2), (blade - 16, half), (16, half)], 'steel_d')
        part.poly([(8, -guard), (16, -guard), (17, guard), (9, guard)], 'guard')
        part.poly([(8, guard * .2), (17, guard * .2), (17, guard), (9, guard)], 'steel_d')
        return part

    parts['sword'] = sword(138., 7., 20., 26.)
    parts['greatsword'] = sword(182., 9.5, 27., 44.)
    staff = Part()
    staff.poly([(-168, -4), (112, -4), (112, 4), (-168, 4)], 'wood')
    staff.poly([(-168, 1), (112, 1), (112, 4), (-168, 4)], 'wood_d')
    staff.poly([(102, -6), (122, -6), (122, 6), (102, 6)], 'wood_d')
    staff.poly([(116, -6), (124, -15), (146, -18), (140, -11), (128, -6), (128, 6), (140, 11), (146, 18), (124, 15), (116, 6)], 'wood')
    staff.poly([(125, 0), (138, -9), (160, -9), (176, 0), (160, 9), (138, 9)], 'purple')
    staff.poly([(125, 0), (138, -9), (160, -9), (176, 0)], 'purple_l')
    staff.poly([(125, 0), (176, 0), (160, 9), (138, 9)], 'purple_d')
    parts['staff'] = staff
    shield = Part()
    outline = [(-30, -48), (0, -54), (30, -48), (33, 8), (22, 34), (0, 52), (-22, 34), (-33, 8)]
    shield.poly(outline, 'steel_m')
    inner = [(x * .84, y * .84) for x, y in outline]
    shield.poly(inner, 'blue')
    shield.poly([(0, -45), (25, -40), (28, 7), (18, 28), (0, 43)], 'blue_d')
    parts['shield'] = shield
    bow = Part()
    curve = [(-14 + 26 * math.cos(a / 16 * math.pi / 2) ** .8 + (4 if abs(a) < 2 else 0), 112 * a / 16) for a in range(-16, 17)]
    bow.stroke(curve, 7., 'wood')
    bow.stroke([(10, -13), (12, 0), (10, 13)], 9., 'leather')
    parts['bow'] = bow
    arrow = Part()
    arrow.poly([(0, -1.6), (118, -1.6), (118, 1.6), (0, 1.6)], 'shaft')
    arrow.poly([(116, -5), (134, 0), (116, 5)], 'steel_m')
    arrow.poly([(0, -1), (16, -1), (10, -7), (-4, -7)], 'feather')
    arrow.poly([(0, 1), (16, 1), (10, 7), (-4, 7)], 'feather')
    parts['arrow'] = arrow
    return parts


def build_atlas(sex):
    rendered = {}
    for name, part in make_parts(sex).items():
        fill, ink, origin = part.render()
        rendered[name] = (fill, ink, origin)
    width = 1536
    x = y = row = 2
    placed = {}
    cells = []
    for name, (fill, ink, origin) in sorted(rendered.items(), key=lambda kv: -kv[1][0].height):
        for tile, key in ((ink, 'ink'), (fill, 'fill')):
            if x + tile.width + 2 > width:
                x, y, row = 2, y + row + 2, 2
            cells.append((tile, x, y))
            placed.setdefault(name, {'origin': list(origin)})[key] = [x, y, tile.width, tile.height]
            x += tile.width + 3
            row = max(row, tile.height)
    atlas = Image.new('RGBA', (width, y + row + 3), (0, 0, 0, 0))
    for tile, cx, cy in cells:
        atlas.paste(tile, (cx, cy))
    return atlas, placed


def head_assets(v2):
    """Crop the approved V2 head from its high resolution source; neck continues under it."""
    masks = {'male': [(125, 85), (252, 85), (252, 172), (223, 174), (223, 182), (186, 182), (186, 172), (134, 168)],
             'female': [(130, 86), (250, 86), (252, 174), (221, 175), (221, 181), (190, 181), (188, 174), (174, 178), (160, 219), (136, 213)]}
    manifest = json.loads((v2 / 'manifest.json').read_text(encoding='utf-8'))
    box = (120, 80, 260, 224)
    for sex, points in masks.items():
        align = next(v for v in manifest['variants'] if v['sex'] == sex and v['id'] == 'base')['alignment']
        source = Image.open(v2 / 'source_art' / f'{sex}_base.png').convert('RGBA')
        scale, (ox, oy) = align['scale'], align['offset']
        k = RES * SS
        full = source.transform((512 * k, 512 * k), Image.Transform.AFFINE, (1 / (scale * k), 0, -ox / scale, 0, 1 / (scale * k), -oy / scale), Image.Resampling.BICUBIC)
        mask = Image.new('L', full.size, 0)
        ImageDraw.Draw(mask).polygon([(x * k, y * k) for x, y in points], fill=255)
        pixels = np.array(full)
        pixels[..., 3] = np.minimum(pixels[..., 3], np.asarray(mask))
        crop = Image.fromarray(pixels).crop(tuple(v * k for v in box))
        crop = premultiplied_resize(crop, ((box[2] - box[0]) * RES, (box[3] - box[1]) * RES))
        crop.save(DEST / f'head_{sex}.png', optimize=True)


# ---------------------------------------------------------------------------- pose authoring

REST = dict(hx=0., hy=0., ha=0., ca=0., na=0., tw=0., lift=0., R=(160., 262.), L=(256., 262.), ra=0., la=0.,
            rw=0., lw=0., fR=(176., 372., 0.), fL=(238., 372., 0.), rf=1., lf=1., rb=1., lb=1.,
            grip=1., draw=0., nock=0., ro=0., lo=0., wz=1., lz=0.)
CHOICE = {'wz', 'lz', 'ro', 'lo', 'nock'}  # Stepped: layer/hand-shape switches never interpolate.


def P(base=None, **kw):
    pose = dict(REST if base is None else base)
    pose.update(kw)
    return pose


def shift(pose, dx=0., dy=0.):
    """Move the upper body with both hands, feet stay where they are."""
    return P(pose, hx=pose['hx'] + dx, hy=pose['hy'] + dy, R=(pose['R'][0] + dx, pose['R'][1] + dy), L=(pose['L'][0] + dx, pose['L'][1] + dy))


IDLE = {
    'unarmed': P(hy=2., ca=3., tw=2., R=(166., 272.), L=(264., 270.), rw=6., lw=6.),
    'sword': P(hy=3., ca=4., tw=9., R=(224., 252.), ra=-56., L=(268., 250.), lw=10.),
    'dual': P(hy=3., ca=4., tw=6., R=(206., 262.), ra=-14., L=(280., 248.), la=-48., fL=(240., 372., 0.)),
    'shield': P(hy=3., ca=4., tw=7., R=(190., 266.), ra=-38., L=(284., 226.), la=4., wz=1., fL=(240., 372., 0.)),
    'greatsword': P(hy=4., ca=5., tw=10., R=(240., 240.), ra=-54., fR=(170., 372., 0.), fL=(242., 372., 0.), lz=1.),
    'bow': P(hy=3., ca=3., tw=2., R=(166., 270.), rw=6., L=(290., 240.), la=9., lz=1.),
    'staff': P(hy=2., ca=3., tw=12., R=(258., 232.), ra=-81., L=(252., 266.), lw=6.),
}
CAST_BACK = dict(hx=-6., hy=6., ha=-2., ca=-7., tw=-9., na=3., R=(134., 262.), ro=1., rw=-10.)


def cast_back(load):
    pose = P(IDLE[load], **CAST_BACK, grip=0.)
    if load in ('sword', 'dual', 'shield'):
        pose.update(ro=0., ra=118., rw=0.)
    if load == 'staff':
        pose.update(R=(250., 240.), ra=-80., ro=0., tw=6., ca=-5.)
    if load == 'greatsword':
        pose.update(R=(134., 258.))
    return pose


def cast_forward(load):
    pose = P(IDLE[load], hx=9., hy=5., ha=2., ca=11., tw=15., R=(276., 209.), ro=1., rw=-16., grip=0., fR=(176., 372., 12.))
    if load in ('sword', 'dual', 'shield'):
        pose.update(R=(274., 212.), ro=0., ra=-40., rw=0.)
    if load == 'staff':
        pose.update(R=(276., 206.), ra=-76., ro=0.)
    if load == 'greatsword':
        pose.update(L=IDLE[load]['L'])
    return pose


CLIPS = []


def add(id, load, kind, duration, loop=False, events=None):
    CLIPS.append(dict(id=id, loadout=load, kind=kind, duration=duration, loop=loop, events=events or []))


LOADOUTS = ['unarmed', 'sword', 'dual', 'shield', 'greatsword', 'bow', 'staff']
for load in LOADOUTS:
    add('idle_' + load, load, 'idle', 1.8, True)
    add('cast_instant_' + load, load, 'instant', .64, False, [dict(time=.22, name='spell_release', socket='cast_right')])
    add('cast_begin_' + load, load, 'cast_begin', .5)
    add('cast_hold_' + load, load, 'cast_hold', 1.2, True)
    add('cast_release_' + load, load, 'cast_release', .5, False, [dict(time=.12, name='spell_release', socket='cast_right')])
    add('death_' + load, load, 'death', 1.1)
for id, load in (('sword_right_slash', 'sword'), ('sword_right_slash_dual', 'dual'), ('sword_right_slash_shield', 'shield')):
    add(id, load, 'right_slash', .86, events=[dict(time=.36, name='melee_impact', socket='right_weapon_tip')])
add('sword_left_slash', 'dual', 'left_slash', .88, events=[dict(time=.38, name='offhand_impact', socket='left_weapon_tip')])
add('dual_combo', 'dual', 'dual_combo', 1.42, events=[dict(time=.32, name='melee_impact', socket='right_weapon_tip'), dict(time=.69, name='offhand_impact', socket='left_weapon_tip'), dict(time=1.05, name='dual_impact', socket='right_weapon_tip')])
add('greatsword_slash', 'greatsword', 'great_slash', 1.18, events=[dict(time=.52, name='melee_impact', socket='right_weapon_tip')])
add('bow_draw', 'bow', 'bow_draw', .82)
add('bow_hold', 'bow', 'bow_hold', 1.2, True)
add('bow_release', 'bow', 'bow_release', .68, events=[dict(time=.08, name='arrow_release', socket='arrow_muzzle')])
add('staff_cast_begin', 'staff', 'staff_begin', .7)
add('staff_cast_hold', 'staff', 'staff_hold', 1.2, True)
add('staff_cast_release', 'staff', 'staff_release', .75, events=[dict(time=.24, name='spell_release', socket='staff_tip')])
add('staff_thrust', 'staff', 'staff_thrust', .98, events=[dict(time=.44, name='melee_impact', socket='staff_tip')])
add('shield_bash', 'shield', 'shield_bash', .84, events=[dict(time=.36, name='shield_impact', socket='shield_front')])


def key_poses(clip):
    """Key poses as (seconds, pose). Follows anticipation, contact, follow-through, settle."""
    load, kind = clip['loadout'], clip['kind']
    idle = IDLE[load]
    if kind == 'instant':
        wind = P(cast_back(load), hx=-4., hy=4., ca=-5., tw=-5.)
        hit = cast_forward(load)
        over = shift(P(hit, ca=13., tw=17.), 3., 0.)
        return [(0, idle), (.1, wind), (.22, hit), (.3, over), (.47, P(hit, hx=3., ca=7., tw=12., hy=4.)), (.64, idle)]
    if kind == 'cast_begin':
        back = cast_back(load)
        return [(0, idle), (.18, P(back, R=(back['R'][0] + 24, back['R'][1] - 3), hx=-3., ca=-3.)), (.5, back)]
    if kind == 'cast_release':
        back = cast_back(load)
        hit = cast_forward(load)
        return [(0, back), (.06, P(back, hx=-8., hy=7., ca=-9.)), (.12, hit), (.2, shift(P(hit, ca=13.), 3., 0.)), (.34, P(hit, hx=3., ca=6.)), (.5, idle)]
    if kind == 'death':
        fall_a = P(idle, hx=-8., hy=26., ha=-8., ca=16., na=16., tw=-4., R=(idle['R'][0] - 12, idle['R'][1] + 20), L=(idle['L'][0] - 30, idle['L'][1] + 22), fR=(176., 372., 0.), fL=(232., 372., 0.), wz=1.)
        fall_b = P(fall_a, hx=-14., hy=70., ha=-12., ca=36., na=30., R=(200., 362.), L=(236., 352.), fL=(222., 372., 0.))
        fall_c = P(fall_b, hx=-34., hy=96., ha=-84., ca=-88., na=-90., R=(146., 376.), L=(176., 330.), ra=idle['ra'] - 104., la=idle['la'] - 96., fR=(214., 372., 0.), fL=(232., 372., 0.), wz=0.)
        return [(0, idle), (.16, fall_a), (.42, fall_b), (.74, fall_c), (.88, shift(fall_c, -1., 3.)), (1.1, shift(fall_c, -2., 3.))]
    if kind == 'right_slash':
        return [(0, idle),
                (.12, shift(P(idle, ha=-3., ca=-6., tw=-6., R=(166., 236.), ra=-118., L=(262., 238.), wz=0.), -7., 5.)),
                (.24, shift(P(idle, ha=-4., ca=-11., tw=-13., na=4., R=(112., 190.), ra=-158., L=(284., 214.), wz=0.), -9., 3.)),
                (.32, shift(P(idle, ca=-1., tw=-2., R=(204., 226.), ra=-104., L=(270., 232.), wz=0.), 2., 1.)),
                (.36, shift(P(idle, ha=2., ca=11., tw=15., R=(264., 205.), ra=-24., L=(250., 254.), fR=(178., 372., 14.)), 9., 2.)),
                (.43, shift(P(idle, ha=3., ca=16., tw=17., R=(262., 244.), ra=28., L=(236., 262.), fR=(178., 372., 20.)), 11., 7.)),
                (.58, shift(P(idle, ha=2., ca=12., tw=12., R=(244., 264.), ra=52., L=(240., 258.), fR=(178., 372., 10.)), 7., 7.)),
                (.74, shift(P(idle, ca=6., tw=9., R=(222., 262.), ra=-8.), 2., 3.)),
                (.86, idle)]
    if kind == 'left_slash':
        guard = dict(R=(198., 262.), ra=-18.)
        return [(0, idle),
                (.14, shift(P(idle, **guard, ca=-4., tw=7., L=(248., 214.), la=-110.), -5., 5.)),
                (.26, shift(P(idle, **guard, ca=-8., tw=11., ha=-3., L=(238., 170.), la=-142.), -7., 3.)),
                (.34, shift(P(idle, **guard, ca=3., tw=2., L=(290., 182.), la=-70.), 4., 1.)),
                (.38, shift(P(idle, **guard, ca=11., tw=-9., ha=2., L=(312., 224.), la=-12.), 10., 3.)),
                (.46, shift(P(idle, **guard, ca=15., tw=-12., L=(310., 256.), la=34.), 12., 7.)),
                (.62, shift(P(idle, R=(200., 260.), ra=-22., ca=10., tw=-5., L=(290., 262.), la=46.), 6., 6.)),
                (.76, shift(P(idle, ca=6., L=(280., 250.), la=-24.), 2., 3.)),
                (.88, idle)]
    if kind == 'dual_combo':
        return [(0, idle),
                (.12, shift(P(idle, ca=-9., tw=-11., ha=-3., R=(112., 196.), ra=-156., L=(262., 240.), la=-46., wz=0.), -8., 4.)),
                (.24, shift(P(idle, ca=-1., tw=-1., R=(204., 226.), ra=-100., L=(258., 244.), la=-40., wz=0.), 2., 1.)),
                (.32, shift(P(idle, ca=12., tw=15., ha=2., R=(258., 212.), ra=-18., L=(248., 248.), la=-30.), 10., 3.)),
                (.40, shift(P(idle, ca=12., tw=13., R=(248., 254.), ra=44., L=(244., 214.), la=-108.), 9., 6.)),
                (.54, shift(P(idle, ca=-6., tw=9., R=(190., 262.), ra=78., L=(238., 170.), la=-142.), -5., 3.)),
                (.64, shift(P(idle, ca=4., tw=1., R=(192., 258.), ra=-30., L=(292., 184.), la=-68.), 4., 2.)),
                (.69, shift(P(idle, ca=12., tw=-10., R=(200., 262.), ra=-16., L=(314., 228.), la=-8.), 11., 4.)),
                (.78, shift(P(idle, ca=2., tw=-3., R=(176., 250.), ra=-120., L=(296., 258.), la=42., wz=0.), 4., 6.)),
                (.92, shift(P(idle, ca=-10., tw=-5., ha=-3., R=(122., 186.), ra=-150., L=(246., 176.), la=-138., wz=0.), -9., 4.)),
                (1.0, shift(P(idle, ca=2., tw=3., R=(214., 228.), ra=-90., L=(278., 182.), la=-82., wz=0.), 3., 2.)),
                (1.05, shift(P(idle, ca=15., tw=9., ha=3., R=(262., 216.), ra=-12., L=(312., 224.), la=-8., fR=(178., 372., 14.)), 13., 5.)),
                (1.14, shift(P(idle, ca=17., tw=9., R=(258., 252.), ra=34., L=(306., 258.), la=38., fR=(178., 372., 20.)), 13., 9.)),
                (1.3, shift(P(idle, ca=8., tw=7., R=(226., 260.), ra=8., L=(288., 252.), la=-22.), 4., 5.)),
                (1.42, idle)]
    if kind == 'great_slash':
        step = (262., 372., 0.)
        return [(0, idle),
                (.14, shift(P(idle, ca=-3., tw=-1., R=(214., 248.), ra=-96., wz=0.), -4., 5.)),
                (.3, shift(P(idle, ha=-4., ca=-11., tw=-12., na=5., R=(132., 214.), ra=-168., wz=0., fL=(250., 366., 4.)), -11., 2.)),
                (.4, shift(P(idle, ha=-5., ca=-13., tw=-15., na=6., R=(120., 206.), ra=-186., wz=0., fL=(258., 362., 6.)), -12., 0.)),
                (.435, shift(P(idle, ha=-2., ca=-7., tw=-9., na=3., R=(156., 250.), ra=-146., wz=0., fL=(260., 364., 4.)), -4., 1.)),
                (.47, shift(P(idle, ha=0., ca=-2., tw=-2., R=(204., 230.), ra=-112., wz=0., fL=(262., 366., 2.)), 4., 2.)),
                (.52, shift(P(idle, ha=4., ca=15., tw=15., R=(258., 224.), ra=-10., fL=step, fR=(170., 372., 18.)), 20., 10.)),
                (.6, shift(P(idle, ha=5., ca=21., tw=17., R=(260., 262.), ra=30., fL=step, fR=(170., 372., 26.)), 24., 17.)),
                (.78, shift(P(idle, ha=4., ca=17., tw=14., R=(246., 276.), ra=42., fL=step, fR=(170., 372., 18.)), 20., 17.)),
                (.96, shift(P(idle, ca=9., tw=11., R=(244., 256.), ra=-20., fL=(250., 366., 2.)), 7., 7.)),
                (1.18, idle)]
    if kind in ('bow_draw', 'bow_hold', 'bow_release'):
        aim = P(idle, hx=-2., hy=5., ha=-1., ca=-3., na=2., tw=-13., L=(316., 186.), la=0., R=(196., 183.), ra=0., rf=.72, rb=-1., draw=1., nock=1., rw=-4.)
        if kind == 'bow_hold':
            return None
        if kind == 'bow_draw':
            lifted = P(idle, hy=4., L=(304., 192.), la=-2., tw=1., R=(236., 226.), rw=-30., nock=0.)
            nocked = P(lifted, L=(314., 188.), la=0., tw=-2., R=(268., 193.), rw=-90., nock=1., draw=.04)
            half = P(aim, draw=.55, R=(232., 188.), rf=1., rb=1., tw=-7., rw=-40.)
            return [(0, idle), (.2, lifted), (.34, nocked), (.56, half), (.74, aim), (.82, aim)]
        snap = P(aim, nock=0., draw=0., R=(176., 174.), rw=-20., tw=-15., L=(320., 188.))
        return [(0, aim), (.08, aim), (.11, P(snap, draw=-.14)), (.17, P(snap, draw=.06)), (.25, P(snap, draw=-.02, R=(170., 182.))), (.4, P(snap, draw=0., R=(160., 214.), rf=.9, L=(312., 200.), tw=-8.)), (.68, idle)]
    if kind == 'staff_begin':
        return [(0, idle), (.24, P(idle, hy=4., ca=-3., R=(258., 214.), ra=-88.)), (.7, staff_up())]
    if kind == 'staff_release':
        up = staff_up()
        hit = P(up, hx=12., hy=7., ha=2., ca=13., tw=15., R=(284., 214.), ra=-26., L=(244., 248.), fR=(178., 372., 14.))
        return [(0, up), (.14, shift(P(up, ca=-9., ra=-98., R=(256., 202.)), -5., 1.)), (.24, hit), (.34, shift(P(hit, ra=-20.), 2., 1.)), (.5, P(hit, hx=6., ra=-50., ca=7., R=(270., 222.))), (.75, idle)]
    if kind == 'staff_thrust':
        wind = shift(P(idle, ha=-3., ca=-9., tw=-14., R=(176., 236.), ra=-8., L=(246., 256.), lw=-20.), -9., 5.)
        jab = shift(P(idle, ha=3., ca=15., tw=18., R=(278., 222.), ra=-5., fL=(262., 372., 0.), fR=(172., 372., 18.), L=(250., 254.)), 20., 8.)
        return [(0, idle), (.24, wind), (.36, P(wind, fL=(254., 364., 4.), R=(200., 232.))), (.44, jab), (.56, jab), (.76, shift(P(idle, ca=6., R=(262., 228.), ra=-60., fL=(250., 366., 2.)), 6., 4.)), (.98, idle)]
    if kind == 'shield_bash':
        coil = shift(P(idle, ha=-3., ca=-8., tw=9., R=(170., 262.), ra=-20., L=(250., 222.), la=-12.), -9., 5.)
        slam = shift(P(idle, ha=4., ca=16., tw=-12., R=(176., 256.), ra=-14., L=(330., 214.), la=8., fL=(266., 372., 0.), fR=(172., 372., 18.)), 26., 7.)
        return [(0, idle), (.2, coil), (.3, P(coil, fL=(258., 362., 5.))), (.36, slam), (.48, slam), (.68, shift(P(idle, ca=7., L=(300., 220.), fL=(252., 366., 2.)), 8., 4.)), (.84, idle)]
    return None


def staff_up():
    return P(IDLE['staff'], hy=4., hx=-3., ca=-6., tw=10., na=-2., R=(262., 198.), ra=-84., L=(238., 256.))


def monotone(ts, vs, t):
    n = len(ts)
    if t <= ts[0]:
        return vs[0]
    if t >= ts[-1]:
        return vs[-1]
    i = max(j for j in range(n - 1) if ts[j] <= t)
    h = ts[i + 1] - ts[i]
    u = (t - ts[i]) / h

    def slope(j):
        if j <= 0 or j >= n - 1:
            return 0.
        a = (vs[j] - vs[j - 1]) / (ts[j] - ts[j - 1])
        b = (vs[j + 1] - vs[j]) / (ts[j + 1] - ts[j])
        return 0. if a * b <= 0 else 2 * a * b / (a + b)

    m0, m1 = slope(i) * h, slope(i + 1) * h
    a, b = vs[i], vs[i + 1]
    return (2 * u ** 3 - 3 * u ** 2 + 1) * a + (u ** 3 - 2 * u ** 2 + u) * m0 + (-2 * u ** 3 + 3 * u ** 2) * b + (u ** 3 - u ** 2) * m1


def sample(keys, t):
    ts = [k[0] for k in keys]
    out = {}
    for name in REST:
        values = [k[1][name] for k in keys]
        if name in CHOICE:
            i = max(j for j in range(len(ts)) if ts[j] <= t + 1e-9)
            # A blade leaves the front layer while it is still clear of the head.
            out[name] = min(values[i], values[i + 1]) if name == 'wz' and i + 1 < len(ts) else values[i]
        elif isinstance(values[0], tuple):
            out[name] = tuple(monotone(ts, [v[c] for v in values], t) for c in range(len(values[0])))
        else:
            out[name] = monotone(ts, values, t)
    return out


def pose_at(clip, t):
    load, kind = clip['loadout'], clip['kind']
    u = t / clip['duration']
    wave = math.sin(u * math.tau)
    if kind == 'idle':
        return shift(P(IDLE[load], ca=IDLE[load]['ca'] + wave * .7, na=-wave * .5), 0., .5 - math.cos(u * math.tau) * 1.2)
    if kind == 'cast_hold':
        base = cast_back(load)
        return shift(P(base, R=(base['R'][0] + wave * 1.6, base['R'][1] + math.cos(u * math.tau) * 1.2), ca=base['ca'] + wave * .6), 0., wave * .9)
    if kind == 'bow_hold':
        base = key_poses(next(c for c in CLIPS if c['id'] == 'bow_draw'))[-1][1]
        return P(base, R=(base['R'][0], base['R'][1] + wave * .4), L=(base['L'][0], base['L'][1] + wave * .5), hy=base['hy'] + wave * .4)
    if kind == 'staff_hold':
        base = staff_up()
        return shift(P(base, ra=base['ra'] + wave * 1.2), 0., wave * .9)
    keys = key_poses(clip)
    if kind == 'right_slash' and load != 'sword':  # The left hand keeps its own weapon in guard.
        base = IDLE[load]['L']
        keys = [(at, P(pose, L=(base[0] + pose['hx'] - IDLE[load]['hx'], base[1] + pose['hy'] - IDLE[load]['hy']), la=IDLE[load]['la'])) for at, pose in keys]
    return sample(keys, t)


# ---------------------------------------------------------------------------- solving

def vec(angle):
    return np.array([math.cos(d(angle)), math.sin(d(angle))])


def rot(p, angle):
    c, s = math.cos(d(angle)), math.sin(d(angle))
    return np.array([p[0] * c - p[1] * s, p[0] * s + p[1] * c])


def ang(v):
    return math.degrees(math.atan2(v[1], v[0]))


def near(angle, ref):
    while angle - ref > 180:
        angle -= 360
    while angle - ref < -180:
        angle += 360
    return angle


def two_bone(start, target, l1, l2, bend):
    delta = np.array(target, dtype=float) - start
    dist = float(np.linalg.norm(delta))
    u = delta / max(dist, 1e-6)
    dist = min(max(dist, abs(l1 - l2) + .5), l1 + l2 - .05)
    along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    perp = np.array([-u[1], u[0]])
    elbow = start + u * along + perp * math.sqrt(max(0., l1 * l1 - along * along)) * bend
    return elbow, start + u * dist


def wrist_limit(flex):
    """Clamp to the wrist range; continuous across +-180 so the solver never flips sides."""
    if abs(flex) <= WRIST:
        return flex
    return math.copysign(WRIST * (180. - abs(flex)) / (180. - WRIST), flex)


def solve_arm(shoulder, grip, weapon, free, follow, l1, l2, foreshort, bend):
    """Weapon axis crosses the fist: hand angle stays within a real wrist range of the forearm."""
    l1, l2 = l1 * foreshort, l2
    hand = ang(np.array(grip) - shoulder)
    for _ in range(24):
        wrist = np.array(grip) - vec(hand) * GRIP
        elbow, reached = two_bone(shoulder, wrist, l1, l2, bend)
        fore = ang(reached - elbow)
        wanted = fore + follow if free else fore + wrist_limit(near(weapon + 90. - fore, 0.))
        hand += near(wanted - hand, 0.) * .5
    return elbow, reached, ang(elbow - shoulder), fore, hand


def within(point, origin, reach):
    offset = point - origin
    dist = float(np.linalg.norm(offset))
    return point if dist <= reach else origin + offset / dist * reach


def planted(foot):
    """A heel lift rolls over the ball of the foot, a toe lift over the heel; nothing sinks."""
    x, y, angle = foot
    contact = np.array((31. if angle > 0 else -20., 25.))
    return np.array((x, y)) + contact - rot(contact, angle)


FIELDS = ['hx', 'hy', 'ha', 'ca', 'na', 'rsx', 'rsy', 'rua', 'ruf', 'rfa', 'rha', 'lsx', 'lsy', 'lua', 'luf', 'lfa', 'lha',
          'rta', 'rca', 'rba', 'lta', 'lca', 'lba', 'w1a', 'w2a', 'grip', 'draw', 'nock', 'ro', 'lo', 'wz', 'lz']


def solve(pose, load, sex):
    s = SEX[sex]
    hip = np.array(HIP) + [pose['hx'], pose['hy']]
    waist = hip + rot(s['waist'], pose['ha'])
    chest_a = pose['ca']
    (srx, sry), (slx, sly) = s['srest']
    sr = (srx + pose['tw'], sry + pose['lift'])
    sl = (slx + pose['tw'] * .55, sly)
    shoulder_r, shoulder_l = waist + rot(sr, chest_a), waist + rot(sl, chest_a)
    grip = pose['grip'] if load == 'greatsword' else 1.
    R, L = np.array(pose['R']), np.array(pose['L'])
    w1a, w2a = pose['ra'], pose['la']
    if load == 'greatsword':
        free_at = np.array(pose['R'])
        reach = s['L1'] + s['L2'] + GRIP * .6  # The bent wrist costs part of the fist length.
        for _ in range(8):  # Both hands stay on the hilt: the sword comes back into reach.
            R = within(R, shoulder_r, reach)
            L = within(R - vec(w1a) * TWO_HAND_GAP, shoulder_l, reach)
            R = L + vec(w1a) * TWO_HAND_GAP
        if grip < 1.:  # The right hand leaves the hilt; the sword stays in the left hand.
            base = IDLE[load]
            L = np.array(base['R']) - vec(base['ra']) * TWO_HAND_GAP
            w1a = base['ra']
            weapon_point = L + vec(w1a) * TWO_HAND_GAP
            R = weapon_point + (free_at - weapon_point) * (1. - grip)
    right_free = load in ('unarmed', 'bow') or (load == 'greatsword' and grip < .5)
    left_free = load in ('unarmed', 'sword', 'staff', 'greatsword')  # The pommel hand follows its forearm.
    re, rw, rua, rfa, rha = solve_arm(shoulder_r, R, w1a, right_free, pose['rw'], s['L1'], s['L2'], pose['rf'], pose['rb'])
    le, lw, lua, lfa, lha = solve_arm(shoulder_l, L, w2a if load != 'greatsword' else w1a, left_free, pose['lw'], s['L1'], s['L2'], pose['lf'], pose['lb'])
    legs = []
    for i, foot in enumerate((pose['fR'], pose['fL'])):
        joint = hip + rot((s['hipx'][i], 0.), pose['ha'])
        knee, ankle = two_bone(joint, planted(foot), s['LT'], s['LS'], -1.)
        legs += [ang(knee - joint), ang(ankle - knee), foot[2]]
    frame = dict(hx=hip[0], hy=hip[1], ha=pose['ha'], ca=chest_a, na=chest_a * .35 + pose['na'], rsx=sr[0], rsy=sr[1], rua=rua, ruf=pose['rf'],
                 rfa=rfa, rha=rha, lsx=sl[0], lsy=sl[1], lua=lua, luf=pose['lf'], lfa=lfa, lha=lha, rta=legs[0], rca=legs[1], rba=legs[2],
                 lta=legs[3], lca=legs[4], lba=legs[5], w1a=w1a, w2a=w2a, grip=grip, draw=pose['draw'], nock=pose['nock'], ro=pose['ro'],
                 lo=pose['lo'], wz=pose['wz'], lz=pose['lz'])
    return [round(float(frame[k]), 3) for k in FIELDS]


def unwrap(frames):
    """Continuous angles keep interpolation between neighbouring samples on the short way."""
    angular = [i for i, k in enumerate(FIELDS) if k in ('rua', 'rfa', 'rha', 'lua', 'lfa', 'lha', 'rta', 'rca', 'lta', 'lca', 'w1a', 'w2a')]
    for a, b in zip(frames, frames[1:]):
        for i in angular:
            b[i] = round(near(b[i], a[i]), 3)
    return frames


def bake(sex):
    clips = {}
    for clip in CLIPS:
        count = round(clip['duration'] * FPS) + 1
        frames = unwrap([solve(pose_at(clip, min(i / FPS, clip['duration'])), clip['loadout'], sex) for i in range(count)])
        clips[clip['id']] = {'meta': {**clip, 'fps': FPS, 'frames': count}, 'frames': frames}
    return clips


# ---------------------------------------------------------------------------- CPU preview, mirrors CharacterRig._draw

class Preview:
    def __init__(self, sex, atlas, placed, head):
        self.sex, self.atlas, self.placed, self.head = sex, atlas, placed, head
        self.s = SEX[sex]

    def world(self, f):
        v = dict(zip(FIELDS, f))
        s = self.s
        hip = np.array([v['hx'], v['hy']])
        waist = hip + rot(s['waist'], v['ha'])
        neck = waist + rot(s['neck'], v['ca'])
        b = {'hem': (hip, v['ha'], 1.), 'chest': (waist, v['ca'], 1.), 'head': (neck, v['na'], 1.)}
        for side, l in (('r', 0), ('l', 1)):
            sh = waist + rot((v[side + 'sx'], v[side + 'sy']), v['ca'])
            el = sh + vec(v[side + 'ua']) * s['L1'] * v[side + 'uf']
            wr = el + vec(v[side + 'fa']) * s['L2']
            joint = hip + rot((s['hipx'][l], 0.), v['ha'])
            kn = joint + vec(v[side + 'ta']) * s['LT']
            an = kn + vec(v[side + 'ca']) * s['LS']
            b['upper_' + side] = (sh, v[side + 'ua'], v[side + 'uf'])
            b['fore_' + side] = (el, v[side + 'fa'], 1.)
            b['hand_' + side] = (wr, v[side + 'ha'], 1.)
            b['thigh_' + side] = (joint, v[side + 'ta'], 1.)
            b['shin_' + side] = (kn, v[side + 'ca'], 1.)
            b['boot_' + side] = (an, v[side + 'ba'], 1.)
        return v, b

    def weapons(self, load, v, b):
        out = []
        gr = b['hand_r'][0] + vec(b['hand_r'][1]) * GRIP
        gl = b['hand_l'][0] + vec(b['hand_l'][1]) * GRIP
        if load in ('sword', 'dual', 'shield'):
            out.append(('sword', gr, v['w1a'], 'main'))
        if load == 'staff':
            out.append(('staff', gr, v['w1a'], 'main'))
        if load == 'greatsword':
            out.append(('greatsword', gl + vec(v['w1a']) * TWO_HAND_GAP, v['w1a'], 'main'))
        if load == 'dual':
            out.append(('sword', gl, v['w2a'], 'off'))
        if load == 'shield':
            out.append(('shield', gl + np.array([6., 0.]), v['w2a'], 'off'))
        if load == 'bow':
            out.append(('bow', gl, v['w2a'], 'off'))
        return out

    def blit(self, canvas, name, key, pos, angle, sx, k):
        info = self.placed[name]
        x, y, w, h = info[key]
        tile = self.atlas.crop((x, y, x + w, y + h))
        self.put(canvas, tile, info['origin'], pos, angle, sx, k)

    def put(self, canvas, tile, origin, pos, angle, sx, k):
        # Inverse mapping from canvas to tile: T = translate(pos)*rotate(angle)*scale(sx,1)*translate(origin)*scale(1/RES)
        c, s = math.cos(d(angle)), math.sin(d(angle))
        a, b_, cc = c / k * RES / sx, s / k * RES / sx, (-pos[0] * c - pos[1] * s) * RES / sx - origin[0] * RES
        dd, e, f = -s / k * RES, c / k * RES, (pos[0] * s - pos[1] * c) * RES - origin[1] * RES
        layer = tile.transform(canvas.size, Image.Transform.AFFINE, (a, b_, cc, dd, e, f), Image.Resampling.BILINEAR)
        canvas.alpha_composite(layer)

    def draw(self, f, load, k=2):
        v, b = self.world(f)
        canvas = Image.new('RGBA', (560 * k, 460 * k), (0, 0, 0, 0))

        def group(names):
            for key in ('ink', 'fill'):
                for name, bone in names:
                    self.blit(canvas, name, key, b[bone][0], b[bone][1], b[bone][2], k)

        def single(name, pos, angle, sx=1.):
            for key in ('ink', 'fill'):
                self.blit(canvas, name, key, pos, angle, sx, k)

        hand_r = ('palm_r' if v['ro'] > .5 else 'fist_r', 'hand_r')
        hand_l = ('palm_l' if v['lo'] > .5 else 'fist_l', 'hand_l')
        far = [('upper_l', 'upper_l'), ('fore_l', 'fore_l')]
        weapons = self.weapons(load, v, b)
        group(far + ([] if v['lz'] > .5 else [hand_l]))
        for name, pos, angle, slot in weapons:
            if slot == 'off' and name == 'sword':
                single(name, pos, angle)
        group([('thigh_l', 'thigh_l'), ('shin_l', 'shin_l')])
        group([('boot_l', 'boot_l')])
        group([('thigh_r', 'thigh_r'), ('shin_r', 'shin_r')])
        group([('boot_r', 'boot_r')])
        group([('hem', 'hem'), ('chest', 'chest')])
        for name, pos, angle, slot in weapons:
            if slot == 'off' and name != 'sword':
                self.offhand(canvas, name, pos, angle, v, b, single, k)
        if v['lz'] > .5:
            group([hand_l])

        def main():
            for name, pos, angle, slot in weapons:
                if slot == 'main':
                    single(name, pos, angle)

        if v['wz'] < .5:
            main()
        pos, angle, _ = b['head']
        self.put(canvas, self.head, self.head_origin(), pos, angle, 1., k)
        group([('upper_r', 'upper_r'), ('fore_r', 'fore_r')])
        if v['wz'] >= .5:
            main()
        group([hand_r])
        return canvas

    def head_origin(self):
        return (120. - self.neck0()[0], 80. - self.neck0()[1])

    def neck0(self):
        s = self.s
        rest = np.array(HIP) + s['waist'] + s['neck']
        return rest

    def offhand(self, canvas, name, pos, angle, v, b, single, k):
        if name == 'shield':
            single(name, pos, angle)
            return
        grip_r = b['hand_r'][0] + vec(b['hand_r'][1]) * GRIP
        draw = v['draw']
        info_scale = 1. + .22 * max(0., draw)
        top = pos + rot((-14. * info_scale, -112. * (1. - .05 * draw)), angle)
        bottom = pos + rot((-14. * info_scale, 112. * (1. - .05 * draw)), angle)
        nock = grip_r if v['nock'] > .5 else pos + rot((-14. * info_scale + min(draw, 0.) * -30., 0.), angle)
        pen = ImageDraw.Draw(canvas)
        line = [tuple(top * k), tuple(nock * k), tuple(bottom * k)]
        pen.line(line, fill=col('string'), width=max(1, round(1.6 * k)))
        info = self.placed['bow']
        for key in ('ink', 'fill'):
            x, y, w, h = info[key]
            self.put(canvas, self.atlas.crop((x, y, x + w, y + h)), info['origin'], pos, angle, info_scale, k)
        if v['nock'] > .5:
            direction = ang(pos - nock)
            single('arrow', nock, direction)


def preview(sex, atlas, placed, head, clips, out, only):
    view = Preview(sex, atlas, placed, head)
    for id, clip in clips.items():
        if only and id not in only:
            continue
        frames = clip['frames']
        count = 8
        k = 1
        sheet = Image.new('RGB', (count * 240, 340), (112, 146, 96))
        pen = ImageDraw.Draw(sheet)
        pen.rectangle((0, 316, count * 240, 340), fill=(150, 112, 70))
        for i in range(count):
            f = frames[round(i / (count - 1) * (len(frames) - 1))]
            layer = view.draw(f, clip['meta']['loadout'], k)
            sheet.paste(layer.crop((100, 70, 340, 410)), (i * 240, 0), layer.crop((100, 70, 340, 410)))
            pen.text((i * 240 + 4, 4), f"{i / (count - 1) * clip['meta']['duration']:.2f}", fill='white')
        pen.text((4, 322), f'{sex} {id}', fill='white')
        sheet.save(out / f'{sex}_{id}.png')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--v2', type=Path)
    parser.add_argument('--preview', type=Path)
    parser.add_argument('clips', nargs='*')
    args = parser.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    if args.v2:
        head_assets(args.v2)
    for sex in SEX:
        atlas, placed = build_atlas(sex)
        atlas.save(DEST / f'atlas_{sex}.png', optimize=True)
        clips = bake(sex)
        s = SEX[sex]
        skeleton = dict(res=RES, grip=GRIP, gap=TWO_HAND_GAP, l1=s['L1'], l2=s['L2'], lt=s['LT'], ls=s['LS'], hipx=s['hipx'], waist=s['waist'], neck=s['neck'],
                        neck_rest=[HIP[0] + s['waist'][0] + s['neck'][0], HIP[1] + s['waist'][1] + s['neck'][1]], head_box=[120, 80], fields=FIELDS, parts=placed)
        payload = json.dumps(dict(skeleton=skeleton, clips=clips), separators=(',', ':')).encode()
        (DEST / f'clips_{sex}.json.gz').write_bytes(gzip.compress(payload, 9, mtime=0))
        print(sex, 'clips', len(clips), 'raw', len(payload), 'atlas', atlas.size)
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            preview(sex, atlas, placed, Image.open(DEST / f'head_{sex}.png').convert('RGBA'), clips, args.preview, set(args.clips))


if __name__ == '__main__':
    main()
