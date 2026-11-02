#!/usr/bin/env python3
"""Draws worn gear skins by armour type and rarity onto the rig part templates.

    python tools/gen_gear_skins.py <brief folder> <out folder> [plate ...]

<brief folder> is an unpacked `tools/build_art_brief.py` zip (templates/ and spec/).
Writes <out>/output/<atype>_<slot>_q<rarity>/<sex>/<part>.png, the layout that
tools/build_gear_atlas.py packs into the game. One look per armour type (plate is
strength, leather agility, cloth spell power) and rarity 0-5: poor, common,
uncommon, rare, epic, legendary. The game picks it in Roster.look.

Every part is the template silhouette: an ink outline and a shaded fill, then the
theme's details (seams, trims, rivets, cloth, emblems, glow) clipped to the fill.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

INK = (23, 20, 29)
SLOT_PARTS = {
    'head': ['head'], 'armor': ['chest', 'hem', 'upper_r', 'upper_l'],
    'hands': ['fore_r', 'fore_l', 'fist_r', 'fist_l', 'palm_r', 'palm_l'],
    'legs': ['thigh_r', 'thigh_l', 'shin_r', 'shin_l'], 'feet': ['boot_r', 'boot_l'],
}


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c)


# ---------------------------------------------------------------- themes
# Each rarity is its own set with a story, not a recolour: the details change too.
PLATE = {
    0: dict(name='Ржавые латы', metal='#7d6a5a', dark='#4e4038', light='#a08870', trim=None, rivet='#5a4a3e',
            rust='#8a4a22', scratches=True, seams=2, helm='kettle'),
    1: dict(name='Железные латы', metal='#8e98a6', dark='#5c6470', light='#bcc4ce', trim='#6e7682', rivet='#3e4450',
            seams=3, helm='nasal'),
    2: dict(name='Латы стража', metal='#9aa6b2', dark='#606c78', light='#cfd8e0', trim='#b07a3a', rivet='#d8a860',
            cloth='#3f7a3a', cloth_trim='#d8c070', seams=3, helm='plume', plume='#4f9a3a'),
    3: dict(name='Латы защитника', metal='#c4ccd8', dark='#7c8698', light='#eef2f8', trim='#2f6ad0', trim2='#e8c050',
            rivet='#e8c050', cloth='#2a4f9a', cloth_trim='#e8c050', gem='#5ab0ff', seams=3, helm='winged', wing='#e8ecf4'),
    4: dict(name='Латы гнева', metal='#4a2e36', dark='#26161c', light='#7a4c56', trim='#d8a038', trim2='#ff4a5a',
            rivet='#ffd070', glow='#ff3a5a', gem='#ff4a6a', spikes=True, seams=3, helm='horned', outline='#7a1a3a'),
    5: dict(name='Латы рассвета', metal='#f0d890', dark='#b08838', light='#fff6d8', trim='#ffffff', trim2='#ff9a2a',
            rivet='#fff2c0', glow='#ffb02a', gem='#ffe27a', rays=True, seams=3, helm='sun', outline='#c86a10',
            cloth='#e8e4f0', cloth_trim='#ffb02a'),
}
THEMES = {'plate': PLATE}


# ---------------------------------------------------------------- masks
def load_mask(path):
    return np.array(Image.open(path).convert('RGBA'))[..., 3] > 40


def erode(mask, r):
    if r <= 0:
        return mask
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(2 * r + 1))
    return np.array(im) > 127


def dilate(mask, r):
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * r + 1))
    return np.array(im) > 127


class Part:
    """A canvas the size of the template; draws are clipped to the fill."""

    def __init__(self, ink_mask, fill_mask, far):
        self.h, self.w = ink_mask.shape
        self.ink = ink_mask
        self.fill = fill_mask & ink_mask
        self.far = far
        self.px = np.zeros((self.h, self.w, 4), np.uint8)
        ys, xs = np.nonzero(self.fill)
        self.box = (xs.min(), ys.min(), xs.max(), ys.max()) if len(xs) else (0, 0, self.w - 1, self.h - 1)

    def k(self, c):
        return shade(c, 0.86) if self.far else c

    def put(self, mask, color, alpha=255):
        c = self.k(color)
        m = mask & self.fill
        if alpha >= 255:
            self.px[m] = (*c, 255)
        else:
            a = alpha / 255.
            base = self.px[m][:, :3].astype(float)
            self.px[m, :3] = (base * (1 - a) + np.array(c) * a).astype(np.uint8)
            self.px[m, 3] = 255

    def layer(self, draw_fn):
        """Mask drawn by draw_fn(ImageDraw) on a blank canvas."""
        im = Image.new('L', (self.w, self.h), 0)
        draw_fn(ImageDraw.Draw(im))
        return np.array(im) > 127

    def frac_x(self, t):
        x0, _, x1, _ = self.box
        return x0 + (x1 - x0) * t

    def frac_y(self, t):
        _, y0, _, y1 = self.box
        return y0 + (y1 - y0) * t

    def finish(self, outline=None):
        out = self.px.copy()
        edge = self.ink & ~self.fill
        out[edge] = (*INK, 255)
        if outline:
            ring = self.fill & ~erode(self.fill, 2)
            out[ring] = (*self.k(hexc(outline)), 255)
        return Image.fromarray(out, 'RGBA')


def base_metal(p, t, vertical=True):
    """Three-band shading lit from above."""
    metal, dark, light = hexc(t['metal']), hexc(t['dark']), hexc(t['light'])
    yy = np.arange(p.h)[:, None] * np.ones((1, p.w))
    _, y0, _, y1 = p.box
    f = (yy - y0) / max(1, y1 - y0)
    p.put(p.fill, metal)
    p.put(p.fill & (f < 0.28), light)
    p.put(p.fill & (f > 0.72), dark)


def seams_across(p, t, n, axis='x', start=0.2, end=0.9):
    """Plate segments: dark seam with a light lip, across the long axis."""
    dark, light = hexc(t['dark']), hexc(t['light'])
    for i in range(n):
        f = start + (end - start) * (i + 1) / (n + 1)
        if axis == 'x':
            x = int(p.frac_x(f))
            p.put(p.layer(lambda d: d.rectangle([x, 0, x + 2, p.h], fill=255)), shade(dark, 0.8))
            p.put(p.layer(lambda d: d.rectangle([x + 3, 0, x + 4, p.h], fill=255)), light)
        else:
            y = int(p.frac_y(f))
            p.put(p.layer(lambda d: d.rectangle([0, y, p.w, y + 2], fill=255)), shade(dark, 0.8))
            p.put(p.layer(lambda d: d.rectangle([0, y + 3, p.w, y + 4], fill=255)), light)


def trim_band(p, color, width=5, inner=1):
    """A band along the inside of the edge (gold edging, enamel)."""
    if color is None:
        return
    band = p.fill & ~erode(p.fill, width)
    p.put(band, hexc(color))
    p.put(band & ~erode(p.fill, inner), shade(hexc(color), 0.7))


def end_band(p, color, side, width=12):
    """A cuff across one end of a limb part (left = joint, right = far end)."""
    if color is None:
        return
    x0, y0, x1, y1 = p.box
    if side == 'right':
        m = p.layer(lambda d: d.rectangle([x1 - width, 0, x1, p.h], fill=255))
    else:
        m = p.layer(lambda d: d.rectangle([x0, 0, x0 + width, p.h], fill=255))
    p.put(m, hexc(color))
    edge = m & ~erode(m, 1)
    p.put(edge, shade(hexc(color), 0.65))


def rivets(p, t, y_frac, n, x_from=0.15, x_to=0.85, r=3):
    if not t.get('rivet'):
        return
    c = hexc(t['rivet'])
    for i in range(n):
        x = p.frac_x(x_from + (x_to - x_from) * i / max(1, n - 1))
        y = p.frac_y(y_frac)
        p.put(p.layer(lambda d: d.ellipse([x - r, y - r, x + r, y + r], fill=255)), c)
        p.put(p.layer(lambda d: d.ellipse([x - r + 1, y - r + 1, x, y], fill=255)), mix(c, (255, 255, 255), .5))


def glow_line(p, t, mask):
    if not t.get('glow'):
        return
    g = hexc(t['glow'])
    p.put(dilate(mask, 2), g, 110)
    p.put(mask, mix(g, (255, 255, 255), .45))


def scratches(p, t, rng):
    if not t.get('scratches'):
        return
    rust = hexc(t['rust'])
    for _ in range(5):
        cx, cy = rng.uniform(*p.box[0::2]), rng.uniform(*p.box[1::2])
        rr = rng.uniform(5, 12)
        p.put(p.layer(lambda d: d.ellipse([cx - rr, cy - rr * .6, cx + rr, cy + rr * .6], fill=255)), rust, 170)
    for _ in range(4):
        x, y = rng.uniform(*p.box[0::2]), rng.uniform(*p.box[1::2])
        p.put(p.layer(lambda d: d.line([x, y, x + rng.uniform(8, 18), y + rng.uniform(-4, 4)], fill=255, width=2)), shade(hexc(t['dark']), .7))


def gem(p, t, cx, cy, r):
    if not t.get('gem'):
        return
    c = hexc(t['gem'])
    p.put(p.layer(lambda d: d.polygon([(cx, cy - r - 2), (cx + r, cy), (cx, cy + r + 2), (cx - r, cy)], fill=255)), INK)
    p.put(p.layer(lambda d: d.polygon([(cx, cy - r), (cx + r - 2, cy), (cx, cy + r), (cx - r + 2, cy)], fill=255)), c)
    p.put(p.layer(lambda d: d.polygon([(cx, cy - r + 2), (cx + 3, cy - 1), (cx, cy)], fill=255)), mix(c, (255, 255, 255), .6))


def emblem(p, t, cx, cy, size):
    """Chest crest: a shield for rare, a burning eye for epic, a sun for legendary, a plain disc otherwise."""
    trim2 = hexc(t.get('trim2') or t.get('trim') or t['light'])
    if t.get('rays'):
        for i in range(12):
            a = i * np.pi / 6
            x2, y2 = cx + np.cos(a) * size * 1.25, cy + np.sin(a) * size * 1.25
            p.put(p.layer(lambda d: d.line([cx, cy, x2, y2], fill=255, width=4)), trim2)
        p.put(p.layer(lambda d: d.ellipse([cx - size * .62, cy - size * .62, cx + size * .62, cy + size * .62], fill=255)), INK)
        p.put(p.layer(lambda d: d.ellipse([cx - size * .5, cy - size * .5, cx + size * .5, cy + size * .5], fill=255)), hexc(t['gem']))
        p.put(p.layer(lambda d: d.ellipse([cx - size * .22, cy - size * .3, cx + size * .05, cy - size * .05], fill=255)), (255, 255, 240))
    elif t.get('spikes'):
        p.put(p.layer(lambda d: d.polygon([(cx - size, cy), (cx, cy - size * .7), (cx + size, cy), (cx, cy + size * .7)], fill=255)), INK)
        p.put(p.layer(lambda d: d.polygon([(cx - size + 3, cy), (cx, cy - size * .7 + 3), (cx + size - 3, cy), (cx, cy + size * .7 - 3)], fill=255)), hexc(t['trim']))
        p.put(p.layer(lambda d: d.ellipse([cx - size * .32, cy - size * .32, cx + size * .32, cy + size * .32], fill=255)), hexc(t['glow']))
        p.put(p.layer(lambda d: d.ellipse([cx - size * .12, cy - size * .3, cx + size * .12, cy + size * .3], fill=255)), INK)
    elif t.get('gem'):
        p.put(p.layer(lambda d: d.polygon([(cx - size, cy - size), (cx + size, cy - size), (cx + size, cy + size * .2), (cx, cy + size * 1.2), (cx - size, cy + size * .2)], fill=255)), INK)
        p.put(p.layer(lambda d: d.polygon([(cx - size + 3, cy - size + 3), (cx + size - 3, cy - size + 3), (cx + size - 3, cy + size * .2), (cx, cy + size * 1.2 - 4), (cx - size + 3, cy + size * .2)], fill=255)), hexc(t['trim']))
        p.put(p.layer(lambda d: d.rectangle([cx - 2, cy - size + 6, cx + 2, cy + size * .8], fill=255)), trim2)
        p.put(p.layer(lambda d: d.rectangle([cx - size + 6, cy - size * .35, cx + size - 6, cy - size * .35 + 4], fill=255)), trim2)
    elif t.get('cloth'):
        pass
    else:
        p.put(p.layer(lambda d: d.ellipse([cx - size * .45, cy - size * .45, cx + size * .45, cy + size * .45], fill=255)), shade(hexc(t['metal']), .8))
        p.put(p.layer(lambda d: d.ellipse([cx - size * .3, cy - size * .3, cx + size * .3, cy + size * .3], fill=255)), hexc(t['light']))


# ---------------------------------------------------------------- plate parts
def plate_part(part, p, t, rng):
    base_metal(p, t)
    trim = t.get('trim')
    if part == 'chest':
        x0, y0, x1, y1 = p.box
        if t.get('cloth'):
            # tabard over the breastplate, falling to the hem
            cx = p.frac_x(.6)
            tab = p.layer(lambda d: d.polygon([(cx - 20, p.frac_y(.12)), (cx + 20, p.frac_y(.12)), (cx + 30, y1 + 2), (cx - 30, y1 + 2)], fill=255))
            p.put(tab, hexc(t['cloth']))
            p.put(tab & ~erode(tab, 3), hexc(t['cloth_trim']))
        seams_across(p, t, 2, 'y', .55, .95)
        trim_band(p, trim, 5)
        if t.get('trim2'):
            p.put(p.fill & ~erode(p.fill, 2), hexc(t['trim2']))
        rivets(p, t, .2, 4, .18, .82)
        emblem(p, t, p.frac_x(.58), p.frac_y(.42), 22)
        if t.get('glow'):
            glow_line(p, t, p.layer(lambda d: d.line([p.frac_x(.25), p.frac_y(.7), p.frac_x(.9), p.frac_y(.7)], fill=255, width=2)))
    elif part == 'hem':
        # tassets: vertical plates with gaps and a trimmed bottom
        seams_across(p, t, 4 if t['seams'] >= 3 else 2, 'x', .0, 1.)
        if t.get('cloth'):
            cx = p.frac_x(.6)
            tab = p.layer(lambda d: d.rectangle([cx - 28, 0, cx + 28, p.h], fill=255))
            p.put(tab, hexc(t['cloth']))
            p.put(p.layer(lambda d: d.rectangle([cx - 28, p.frac_y(.8), cx + 28, p.h], fill=255)), hexc(t['cloth_trim']))
        p.put(p.layer(lambda d: d.rectangle([0, p.frac_y(.82), p.w, p.h], fill=255)), hexc(trim) if trim else hexc(t['dark']))
        p.put(p.layer(lambda d: d.rectangle([0, 0, p.w, p.frac_y(.16)], fill=255)), hexc(t.get('trim2') or t['dark']))
        rivets(p, t, .08, 5, .1, .9, 2)
    elif part.startswith('upper'):
        # pauldron over the shoulder (joint at the left), layered lames
        x0, y0, x1, y1 = p.box
        cap = p.layer(lambda d: d.ellipse([x0 - 6, y0 - 4, x0 + (x1 - x0) * .62, y1 + 4], fill=255))
        p.put(cap, hexc(t['light']))
        p.put(cap & ~erode(cap, 3), hexc(trim) if trim else hexc(t['dark']))
        seams_across(p, t, 2, 'x', .55, 1.)
        if t.get('spikes'):
            for i in range(2):
                sx = x0 + (x1 - x0) * (.18 + .2 * i)
                p.put(p.layer(lambda d: d.polygon([(sx - 6, y0 + 6), (sx + 6, y0 + 6), (sx, y0 - 2)], fill=255)), hexc(t['trim']))
        if t.get('rays'):
            glow_line(p, t, cap & ~erode(cap, 1))
        rivets(p, t, .5, 2, .12, .32, 3)
    elif part.startswith('fore'):
        # vambrace: cuffs at the elbow (left) and the wrist (right)
        seams_across(p, t, 1, 'x', .3, .7)
        end_band(p, trim or t['dark'], 'left', 10)
        end_band(p, trim or t['dark'], 'right', 14)
        if t.get('glow'):
            glow_line(p, t, p.layer(lambda d: d.line([p.frac_x(.25), p.frac_y(.5), p.frac_x(.75), p.frac_y(.5)], fill=255, width=2)))
        rivets(p, t, .5, 2, .25, .7, 2)
    elif part.startswith('fist') or part.startswith('palm'):
        # gauntlet: knuckle plate and finger lames
        x0, y0, x1, y1 = p.box
        p.put(p.layer(lambda d: d.rectangle([x0, y0, x0 + (x1 - x0) * .35, y1], fill=255)), hexc(trim) if trim else hexc(t['dark']))
        for i in range(3):
            y = p.frac_y(.3 + .2 * i)
            p.put(p.layer(lambda d: d.line([p.frac_x(.45), y, x1, y], fill=255, width=2)), shade(hexc(t['dark']), .75))
        if t.get('spikes'):
            p.put(p.layer(lambda d: d.polygon([(p.frac_x(.55), y0 + 2), (p.frac_x(.75), y0 + 2), (p.frac_x(.65), y0 - 2)], fill=255)), hexc(t['trim']))
    elif part.startswith('thigh'):
        seams_across(p, t, 2, 'x', .25, .9)
        end_band(p, trim, 'left', 8)
        if t.get('cloth'):
            p.put(p.layer(lambda d: d.rectangle([p.frac_x(.0), p.frac_y(.0), p.frac_x(.35), p.frac_y(1.)], fill=255)), hexc(t['cloth']))
        rivets(p, t, .3, 3, .3, .85, 2)
    elif part.startswith('shin'):
        # greave with a knee cop at the joint (left)
        x0, y0, x1, y1 = p.box
        seams_across(p, t, 2, 'x', .4, .9)
        kr = (y1 - y0) * .36
        kx, ky = x0 + kr + 6, (y0 + y1) / 2
        knee = p.layer(lambda d: d.ellipse([kx - kr, ky - kr, kx + kr, ky + kr], fill=255))
        p.put(knee, hexc(t['metal']))
        p.put(knee & (np.arange(p.h)[:, None] < ky), hexc(t['light']))
        p.put(knee & ~erode(knee, 3), hexc(trim) if trim else hexc(t['dark']))
        if t.get('spikes'):
            p.put(p.layer(lambda d: d.polygon([(kx - 6, ky - kr + 4), (kx + 6, ky - kr + 4), (kx, ky - kr - 6)], fill=255)), hexc(t['trim']))
        gem(p, t, kx, ky, 5)
        end_band(p, trim, 'right', 8)
    elif part.startswith('boot'):
        # sabaton: toe lames, ankle cuff, heel
        x0, y0, x1, y1 = p.box
        for i in range(3):
            y = p.frac_y(.6 + .1 * i)
            p.put(p.layer(lambda d: d.line([p.frac_x(.45), y, x1, y], fill=255, width=3)), shade(hexc(t['dark']), .8))
        p.put(p.layer(lambda d: d.rectangle([x0, y0, x1, p.frac_y(.22)], fill=255)), hexc(trim) if trim else hexc(t['dark']))
        p.put(p.layer(lambda d: d.rectangle([x0, p.frac_y(.9), x1, y1], fill=255)), shade(hexc(t['dark']), .7))
        if t.get('glow'):
            glow_line(p, t, p.layer(lambda d: d.line([p.frac_x(.5), p.frac_y(.5), x1 - 4, p.frac_y(.5)], fill=255, width=2)))
    scratches(p, t, rng)


# ---------------------------------------------------------------- helmets
def head_box(head_path):
    a = np.array(Image.open(head_path).convert('RGBA'))[..., 3] > 40
    ys, xs = np.nonzero(a)
    # the eye: the darkest compact blob in the right half of the head
    rgb = np.array(Image.open(head_path).convert('RGB')).astype(int)
    lum = rgb.sum(axis=2)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    sub = (lum < 120) & a
    sub[:, : x0 + int((x1 - x0) * .55)] = False
    sub[:, x1 - 8:] = False
    sub[: y0 + int((y1 - y0) * .3)] = False
    sub[y0 + int((y1 - y0) * .7):] = False
    ey, ex = np.nonzero(sub)
    eye = (int(ex.mean()), int(ey.mean())) if len(ex) else (x0 + int((x1 - x0) * .82), y0 + int((y1 - y0) * .5))
    return a.shape, (x0, y0, x1, y1), eye


def helmet(shape, box, eye, t):
    h, w = shape
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    ex, ey = eye
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    metal, dark, light = hexc(t['metal']), hexc(t['dark']), hexc(t['light'])
    trim = hexc(t['trim']) if t.get('trim') else dark
    style = t['helm']
    brow = ey - H * .1
    top = y0 - 8
    back = x0 - 6
    front = x1 + 6

    def shape_fill(points, fill, outline=INK, width=6):
        d.polygon(points, fill=(*outline, 255))
        inner = Image.new('L', (w, h), 0)
        ImageDraw.Draw(inner).polygon(points, fill=255)
        inner = inner.filter(ImageFilter.MinFilter(width + 1))
        col = Image.new('RGBA', (w, h), (*fill, 255))
        img.paste(col, (0, 0), inner)
        return inner

    # skull cap that also covers the back of the head; the face stays open unless closed
    cap = [(back, brow + H * .55), (back, top + H * .2), (x0 + W * .18, top), (x1 - W * .16, top), (front, top + H * .22), (front, brow), (ex - W * .22, brow), (ex - W * .3, brow + H * .5), (back, brow + H * .55)]
    closed = style in ('horned',)
    if closed:
        cap = [(back, y1 - H * .05), (back, top + H * .2), (x0 + W * .18, top), (x1 - W * .16, top), (front, top + H * .22), (front, y1 - H * .12), (back, y1 - H * .05)]
    if style == 'kettle':
        d.polygon([(back - 14, brow + 4), (front + 14, brow + 4), (front + 8, brow + 16), (back - 8, brow + 16)], fill=(*INK, 255))
        d.polygon([(back - 9, brow + 7), (front + 9, brow + 7), (front + 4, brow + 12), (back - 4, brow + 12)], fill=(*dark, 255))
    shape_fill(cap, metal)
    # light on the dome, dark on the lower back
    d.polygon([(x0 + W * .22, top + 8), (x1 - W * .2, top + 8), (x1 - W * .12, top + H * .16), (x0 + W * .16, top + H * .16)], fill=(*light, 255))
    # neck guard: darker lower rim on the back of the helmet
    d.rectangle([back + 7, brow + H * .4, ex - W * .34, brow + H * .5], fill=(*dark, 255))
    # brow band
    d.rectangle([back + 6, brow - 8, front - 6, brow - 1], fill=(*trim, 255))
    if style == 'nasal':
        d.rectangle([ex + W * .06, brow - 4, ex + W * .13, ey + H * .16], fill=(*INK, 255))
        d.rectangle([ex + W * .075, brow - 2, ex + W * .115, ey + H * .14], fill=(*metal, 255))
    if style == 'plume':
        pc = hexc(t['plume'])
        d.polygon([(x0 + W * .5, top + 6), (x0 + W * .3, top - 20), (x0 - W * .12, top + 2), (x0 - W * .2, top + 46), (x0 + W * .1, top + 16), (x0 + W * .6, top + 6)], fill=(*INK, 255))
        d.polygon([(x0 + W * .5, top + 2), (x0 + W * .3, top - 14), (x0 - W * .08, top + 4), (x0 - W * .14, top + 38), (x0 + W * .1, top + 10), (x0 + W * .56, top + 2)], fill=(*pc, 255))
        d.line([(x0 + W * .45, top - 2), (x0 - W * .08, top + 28)], fill=(*shade(pc, .7), 255), width=3)
        d.rectangle([ex - W * .28, brow, ex - W * .2, brow + H * .45], fill=(*trim, 255))
    if style == 'winged':
        wc = hexc(t['wing'])
        bx, by = x0 + W * .3, top + H * .22
        feathers = [(-.55, -.32), (-.62, -.12), (-.6, .06), (-.5, .2)]
        for i, (fx, fy) in enumerate(feathers):
            tip = (bx + W * fx, by + H * fy)
            d.polygon([(bx, by - 8 + i * 6), tip, (bx + 4, by + 8 + i * 6)], fill=(*INK, 255))
        for i, (fx, fy) in enumerate(feathers):
            tip = (bx + W * fx * .94, by + H * fy * .94)
            d.polygon([(bx + 2, by - 5 + i * 6), tip, (bx + 4, by + 5 + i * 6)], fill=(*shade(wc, 1 - .06 * i), 255))
        d.rectangle([back + 6, brow - 8, front - 6, brow - 1], fill=(*hexc(t['trim2']), 255))
        cx, cy = x1 - W * .25, brow - 4
        d.polygon([(cx, cy - 9), (cx + 7, cy), (cx, cy + 9), (cx - 7, cy)], fill=(*hexc(t['gem']), 255), outline=(*INK, 255))
    if style == 'horned':
        for k, (bx, sgn) in enumerate([(x0 + W * .22, -1), (x1 - W * .28, 1)]):
            d.polygon([(bx - 15, top + 14), (bx + 15, top + 14), (bx + sgn * 34, top - 52), (bx + sgn * 8, top - 10)], fill=(*INK, 255))
            d.polygon([(bx - 10, top + 11), (bx + 10, top + 11), (bx + sgn * 30, top - 45), (bx + sgn * 6, top - 10)], fill=(*hexc(t['trim']), 255))
        g = hexc(t['glow'])
        d.rectangle([ex - W * .3, ey - 6, front - 4, ey + 4], fill=(*INK, 255))
        d.rectangle([ex - W * .25, ey - 3, front - 8, ey + 1], fill=(*g, 255))
        d.rectangle([back + 6, brow - 30, front - 6, brow - 24], fill=(*trim, 255))
        d.line([(front - 8, ey + 12), (ex - W * .2, y1 - H * .12)], fill=(*hexc(t['trim2']), 255), width=3)
    if style == 'sun':
        rc = hexc(t['trim2'])
        cx, cy = x0 + W * .48, top + 6
        for i in range(7):
            a = np.pi + (i + .5) * np.pi / 7
            ln = 92 if i % 2 == 0 else 70
            d.polygon([(cx + np.cos(a) * 30 - 9, cy + np.sin(a) * 14), (cx + np.cos(a) * ln, cy + np.sin(a) * ln * .8), (cx + np.cos(a) * 30 + 9, cy + np.sin(a) * 14)], fill=(*INK, 255))
            d.polygon([(cx + np.cos(a) * 32 - 5, cy + np.sin(a) * 16), (cx + np.cos(a) * (ln - 7), cy + np.sin(a) * (ln - 7) * .8), (cx + np.cos(a) * 32 + 5, cy + np.sin(a) * 16)], fill=(*rc, 255))
        shape_fill(cap, metal)
        d.polygon([(x0 + W * .22, top + 8), (x1 - W * .2, top + 8), (x1 - W * .12, top + H * .16), (x0 + W * .16, top + H * .16)], fill=(*light, 255))
        d.rectangle([back + 6, brow - 8, front - 6, brow - 1], fill=(*rc, 255))
        gx, gy = x1 - W * .28, brow - 4
        d.ellipse([gx - 9, gy - 9, gx + 9, gy + 9], fill=(*INK, 255))
        d.ellipse([gx - 6, gy - 6, gx + 6, gy + 6], fill=(*hexc(t['gem']), 255))
    if t.get('scratches'):
        rng = np.random.default_rng(3)
        for _ in range(4):
            cx, cy = rng.uniform(x0 + 10, x1 - 30), rng.uniform(top + 15, brow - 10)
            d.ellipse([cx - 8, cy - 5, cx + 8, cy + 5], fill=(*hexc(t['rust']), 200))
    if t.get('outline'):
        a = np.array(img)[..., 3] > 0
        ring = a & ~erode(a, 3) & erode(a, 0)
        px = np.array(img)
        inner_ring = erode(a, 2) & ~erode(a, 4)
        px[inner_ring] = (*hexc(t['outline']), 255)
        img = Image.fromarray(px, 'RGBA')
    return img


# ---------------------------------------------------------------- main
def main():
    brief, out = Path(sys.argv[1]), Path(sys.argv[2])
    atypes = sys.argv[3:] or list(THEMES)
    n = 0
    for atype in atypes:
        for q, t in THEMES[atype].items():
            for slot, parts in SLOT_PARTS.items():
                look = '%s_%s_q%d' % (atype, slot, q)
                for sex in ('male', 'female'):
                    folder = out / 'output' / look / sex
                    folder.mkdir(parents=True, exist_ok=True)
                    rng = np.random.default_rng(hash((atype, q, slot, sex)) & 0xffff)
                    for part in parts:
                        if part == 'head':
                            shape, box, eye = head_box(brief / 'templates' / sex / 'head.png')
                            helmet(shape, box, eye, t).save(folder / 'head.png')
                        else:
                            ink = load_mask(brief / 'templates' / sex / ('%s_ink.png' % part))
                            fill = load_mask(brief / 'templates' / sex / ('%s_fill.png' % part))
                            p = Part(ink, fill, part.endswith('_l'))
                            plate_part(part, p, t, rng)
                            p.finish(t.get('outline')).save(folder / ('%s.png' % part))
                        n += 1
    print('drew %d parts' % n)


if __name__ == '__main__':
    main()
