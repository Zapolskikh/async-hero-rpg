"""Weapon and shield skins by rarity, in the style of the character rig.

    python tools/gen_weapon_skins.py <out folder>

Writes <out>/output/<type>_q<0-5>/weapon.png for sword, greatsword, shield, staff and bow,
in the exact canvas of templates/weapons (grip, guard and bow tips stay where the rig holds
them). Pack with tools/build_gear_atlas.py together with the armour skins.

Rarity reads from colour and shape: rusty and plain (poor, common), bronze and green
leather (uncommon), silver and blue runes (rare), dark steel and violet void (epic),
gold and fire (legendary).
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 3                      # supersampling
INK = (24, 22, 30, 255)
OUTLINE = 6                 # px at 1x, like the templates

SIZES = {'sword': (364, 104), 'greatsword': (488, 132), 'staff': (712, 96), 'shield': (156, 236), 'bow': (96, 484)}

# palette per quality: blade light/dark, guard light/dark, grip, accent (gem / rune), glow
PAL = [
    dict(bl=(158, 140, 124), bd=(122, 104, 92), gl=(118, 112, 106), gd=(88, 82, 78), grip=(96, 66, 40), acc=(150, 82, 40), glow=None, wood=(110, 76, 44), wood_d=(84, 56, 32)),
    dict(bl=(226, 230, 238), bd=(172, 180, 194), gl=(150, 160, 176), gd=(110, 118, 134), grip=(98, 62, 36), acc=(150, 160, 176), glow=None, wood=(140, 92, 50), wood_d=(104, 66, 34)),
    dict(bl=(230, 234, 240), bd=(174, 182, 196), gl=(206, 154, 70), gd=(160, 110, 44), grip=(62, 112, 64), acc=(84, 214, 120), glow=None, wood=(126, 86, 50), wood_d=(92, 62, 36)),
    dict(bl=(238, 244, 252), bd=(176, 192, 214), gl=(206, 216, 232), gd=(146, 160, 186), grip=(40, 70, 130), acc=(80, 168, 255), glow=(80, 160, 255), wood=(60, 82, 128), wood_d=(40, 56, 96)),
    dict(bl=(96, 92, 124), bd=(62, 58, 86), gl=(70, 56, 96), gd=(44, 34, 64), grip=(40, 30, 54), acc=(196, 112, 255), glow=(170, 90, 255), wood=(58, 44, 80), wood_d=(38, 28, 56)),
    dict(bl=(255, 244, 208), bd=(236, 198, 126), gl=(246, 196, 70), gd=(196, 136, 30), grip=(130, 40, 30), acc=(255, 110, 40), glow=(255, 150, 50), wood=(176, 96, 40), wood_d=(132, 66, 26)),
]


class Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.fill = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.fill)
        self.glow = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
        self.gd = ImageDraw.Draw(self.glow)
        self.lines = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
        self.ld = ImageDraw.Draw(self.lines)

    @staticmethod
    def _p(pts):
        return [(x * SS, y * SS) for x, y in pts]

    def poly(self, pts, color):
        self.d.polygon(self._p(pts), fill=tuple(color) + (255,) if len(color) == 3 else color)

    def ellipse(self, box, color):
        x0, y0, x1, y1 = box
        self.d.ellipse([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=tuple(color) + (255,))

    def rect(self, box, color):
        self.poly([(box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])], color)

    def line(self, pts, color, width):
        """Inner detail drawn over the fill (not part of the silhouette)."""
        self.ld.line(self._p(pts), fill=tuple(color) + (255,), width=int(width * SS), joint='curve')

    def dot(self, x, y, r, color):
        self.ld.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=tuple(color) + (255,))

    def detail_poly(self, pts, color):
        self.ld.polygon(self._p(pts), fill=tuple(color) + (255,))

    def halo(self, pts, color, width):
        self.gd.line(self._p(pts), fill=tuple(color) + (200,), width=int(width * SS), joint='curve')

    def halo_dot(self, x, y, r, color):
        self.gd.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=tuple(color) + (170,))

    def finish(self) -> Image.Image:
        body = Image.alpha_composite(self.fill, self.lines)
        alpha = self.fill.getchannel('A').point(lambda a: 255 if a > 40 else 0)
        size = OUTLINE * SS * 2 + 1
        grown = alpha.filter(ImageFilter.MaxFilter(min(size, 31)))
        while size > 31:
            grown = grown.filter(ImageFilter.MaxFilter(min(size - 30, 31)))
            size -= 30
        ink = Image.new('RGBA', body.size, INK)
        ink.putalpha(grown)
        out = Image.new('RGBA', body.size, (0, 0, 0, 0))
        if self.glow.getbbox():
            g = self.glow.filter(ImageFilter.GaussianBlur(5 * SS))
            out = Image.alpha_composite(out, g)
        out = Image.alpha_composite(out, ink)
        out = Image.alpha_composite(out, body)
        return out.resize((self.w, self.h), Image.LANCZOS)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ------------------------------------------------------------------ blades

def blade(c: Canvas, q: int, x0: float, x1: float, cy: float, half: float, tip: float):
    """Straight blade from x0 to x1 with a point to x1+tip; shape by rarity."""
    p = PAL[q]
    if q == 0:   # chipped, short point
        top = [(x0, cy - half), (x1 * 0.55 + x0 * 0.45, cy - half), (x1 * 0.55 + x0 * 0.45 + 6, cy - half + 4),
               (x1 * 0.55 + x0 * 0.45 + 14, cy - half), (x1, cy - half), (x1 + tip * 0.8, cy)]
        bot = [(x1 + tip * 0.8, cy), (x1 - 10, cy + half), (x1 * 0.4 + x0 * 0.6 + 8, cy + half), (x1 * 0.4 + x0 * 0.6, cy + half - 5),
               (x1 * 0.4 + x0 * 0.6 - 8, cy + half), (x0, cy + half)]
    elif q == 4:  # serrated back edge
        top = [(x0, cy - half)]
        n = 7
        for i in range(n):
            xa = x0 + (x1 - x0) * i / n
            xb = x0 + (x1 - x0) * (i + 0.5) / n
            top += [(xa, cy - half), (xb, cy - half - 6)]
        top += [(x1, cy - half), (x1 + tip, cy)]
        bot = [(x1 + tip, cy), (x1, cy + half), (x0, cy + half)]
    elif q == 5:  # flame-waved blade
        top = []
        n = 5
        for i in range(n * 4 + 1):
            t = i / (n * 4)
            x = x0 + (x1 - x0) * t
            top.append((x, cy - half - 3 * math.sin(t * n * 2 * math.pi)))
        top.append((x1 + tip, cy))
        bot = []
        for i in range(n * 4, -1, -1):
            t = i / (n * 4)
            x = x0 + (x1 - x0) * t
            bot.append((x, cy + half + 3 * math.sin(t * n * 2 * math.pi + 1.2)))
    else:
        w = half + (2 if q == 3 else 0)
        top = [(x0, cy - w), (x1, cy - w), (x1 + tip, cy)]
        bot = [(x1 + tip, cy), (x1, cy + w), (x0, cy + w)]
    c.poly(top + bot, p['bl'])
    # darker lower half
    lower = [(x0, cy)] + [pt for pt in bot] + [(x0, cy)]
    lower = [(x0, cy), (x1 + (tip if q != 0 else tip * 0.8), cy)] + bot[1:] if len(bot) > 1 else lower
    c.poly(lower, p['bd'])
    # fuller / runes / edge glow
    if q in (1, 2):
        c.line([(x0 + 8, cy - 2), (x1 - 18, cy - 2)], mix(p['bd'], (90, 96, 110), 0.5), 3)
    if q == 0:
        for fx, fy, r in ((0.3, -0.3, 5), (0.55, 0.35, 4), (0.75, -0.1, 6), (0.42, 0.1, 3)):
            c.dot(x0 + (x1 - x0) * fx, cy + half * fy, r, p['acc'])
    if q == 3:
        c.line([(x0 + 10, cy), (x1 - 20, cy)], (70, 110, 170), 4)
        for i in range(6):
            x = x0 + 20 + (x1 - x0 - 50) * i / 5
            c.line([(x - 4, cy - 4), (x + 4, cy + 4)], p['acc'], 3)
            c.line([(x + 4, cy - 4), (x - 4, cy + 4)], p['acc'], 3)
        c.halo([(x0 + 10, cy), (x1 - 20, cy)], p['glow'], 6)
    if q == 4:
        c.line([(x0 + 4, cy + half - 3), (x1, cy + half - 3), (x1 + tip - 4, cy)], p['acc'], 3)
        c.halo([(x0, cy + half), (x1, cy + half), (x1 + tip, cy)], p['glow'], 8)
        c.line([(x0 + 14, cy - 1), (x1 - 30, cy - 1)], (40, 36, 60), 3)
    if q == 5:
        c.line([(x0 + 10, cy), (x1 - 10, cy)], (255, 170, 60), 4)
        c.halo([(x0, cy), (x1 + tip, cy)], p['glow'], 14)


def hilt(c: Canvas, q: int, gx: float, cy: float, guard_h: float, grip_x0: float, pommel_x: float):
    """Guard centred at gx, grip from grip_x0 to gx, pommel left of grip_x0."""
    p = PAL[q]
    gh = guard_h
    # grip
    c.rect((grip_x0, cy - 9, gx - 4, cy + 9), p['grip'])
    if q in (2, 3, 5):
        step = 10
        x = grip_x0 + 4
        while x < gx - 8:
            c.line([(x, cy - 9), (x + 6, cy + 9)], mix(p['grip'], (0, 0, 0), 0.35), 2)
            x += step
    # guard by rarity
    if q == 0:
        c.rect((gx - 8, cy - gh * 0.62, gx + 8, cy + gh * 0.62), p['gl'])
    elif q == 1:
        c.rect((gx - 10, cy - gh, gx + 10, cy + gh), p['gl'])
        c.rect((gx - 10, cy, gx + 10, cy + gh), p['gd'])
    elif q == 2:   # curved bronze crossguard
        c.poly([(gx - 10, cy - 8), (gx - 2, cy - gh), (gx + 12, cy - gh - 6), (gx + 8, cy - gh + 8), (gx + 10, cy - 8),
                (gx + 10, cy + 8), (gx + 8, cy + gh - 8), (gx + 12, cy + gh + 6), (gx - 2, cy + gh), (gx - 10, cy + 8)], p['gl'])
        c.poly([(gx - 10, cy), (gx + 10, cy), (gx + 10, cy + 8), (gx + 8, cy + gh - 8), (gx + 12, cy + gh + 6), (gx - 2, cy + gh), (gx - 10, cy + 8)], p['gd'])
        c.dot(gx, cy, 6, p['acc'])
    elif q == 3:   # winged silver guard with sapphire
        c.poly([(gx - 12, cy - 10), (gx - 16, cy - gh - 4), (gx + 2, cy - gh + 6), (gx + 14, cy - gh - 10), (gx + 12, cy - 10),
                (gx + 12, cy + 10), (gx + 14, cy + gh + 10), (gx + 2, cy + gh - 6), (gx - 16, cy + gh + 4), (gx - 12, cy + 10)], p['gl'])
        c.poly([(gx - 12, cy), (gx + 12, cy), (gx + 12, cy + 10), (gx + 14, cy + gh + 10), (gx + 2, cy + gh - 6), (gx - 16, cy + gh + 4), (gx - 12, cy + 10)], p['gd'])
        c.dot(gx, cy, 8, p['acc'])
        c.dot(gx - 2, cy - 3, 3, (220, 240, 255))
        c.halo_dot(gx, cy, 10, p['glow'])
    elif q == 4:   # spiked dark guard
        c.poly([(gx - 10, cy - 10), (gx - 18, cy - gh - 8), (gx - 2, cy - gh + 4), (gx + 6, cy - gh - 12), (gx + 10, cy - gh + 6),
                (gx + 22, cy - gh + 2), (gx + 12, cy - 10), (gx + 12, cy + 10), (gx + 22, cy + gh - 2), (gx + 10, cy + gh - 6),
                (gx + 6, cy + gh + 12), (gx - 2, cy + gh - 4), (gx - 18, cy + gh + 8), (gx - 10, cy + 10)], p['gl'])
        c.dot(gx, cy, 8, p['acc'])
        c.halo_dot(gx, cy, 12, p['glow'])
    else:          # golden sun guard with wings
        c.poly([(gx - 12, cy - 10), (gx - 26, cy - gh - 2), (gx - 6, cy - gh + 4), (gx + 2, cy - gh - 10), (gx + 10, cy - gh + 2),
                (gx + 26, cy - gh - 4), (gx + 14, cy - 10), (gx + 14, cy + 10), (gx + 26, cy + gh + 4), (gx + 10, cy + gh - 2),
                (gx + 2, cy + gh + 10), (gx - 6, cy + gh - 4), (gx - 26, cy + gh + 2), (gx - 12, cy + 10)], p['gl'])
        c.poly([(gx - 12, cy), (gx + 14, cy), (gx + 14, cy + 10), (gx + 26, cy + gh + 4), (gx + 10, cy + gh - 2),
                (gx + 2, cy + gh + 10), (gx - 6, cy + gh - 4), (gx - 26, cy + gh + 2), (gx - 12, cy + 10)], p['gd'])
        c.dot(gx, cy, 10, p['acc'])
        c.dot(gx - 3, cy - 3, 4, (255, 220, 160))
        c.halo_dot(gx, cy, 16, p['glow'])
    # pommel
    pr = 11 if q < 3 else 13
    if q == 0:
        c.rect((pommel_x, cy - 10, grip_x0 + 2, cy + 10), p['gd'])
    elif q in (1, 2):
        c.rect((pommel_x, cy - pr, grip_x0 + 4, cy + pr), p['gl'])
        c.rect((pommel_x, cy, grip_x0 + 4, cy + pr), p['gd'])
    else:
        c.poly([(pommel_x - 2, cy), (grip_x0 - 6, cy - pr - 2), (grip_x0 + 4, cy), (grip_x0 - 6, cy + pr + 2)], p['gl'])
        c.dot(grip_x0 - 6, cy, 5, p['acc'])


def sword(q: int, big: bool = False) -> Image.Image:
    w, h = SIZES['greatsword' if big else 'sword']
    c = Canvas(w, h)
    cy = h / 2
    if big:
        blade(c, q, 140, 440, cy, 19, 38)
        hilt(c, q, 136, cy, 54, 30, 10)
    else:
        blade(c, q, 106, 318, cy, 15, 34)
        hilt(c, q, 100, cy, 40, 28, 10)
    return c.finish()


# ------------------------------------------------------------------ staff

def staff(q: int) -> Image.Image:
    w, h = SIZES['staff']
    c = Canvas(w, h)
    cy = h / 2
    p = PAL[q]
    end = 560
    # shaft
    if q == 0:   # knotty branch
        pts = [(10, cy - 6), (180, cy - 7), (200, cy - 11), (214, cy - 6), (380, cy - 6), (396, cy - 10), (410, cy - 6), (end, cy - 7),
               (end, cy + 7), (300, cy + 7), (288, cy + 11), (276, cy + 7), (10, cy + 6)]
        c.poly(pts, p['wood'])
        c.poly([(10, cy + 1), (end, cy + 1), (end, cy + 7), (10, cy + 6)], p['wood_d'])
    else:
        c.rect((10, cy - 7, end, cy + 7), p['wood'])
        c.rect((10, cy + 1, end, cy + 7), p['wood_d'])
        bands = {1: [], 2: [200, 380], 3: [150, 300, 450], 4: [120, 260, 400], 5: [100, 220, 340, 460]}[q]
        for x in bands:
            c.rect((x, cy - 9, x + 12, cy + 9), p['gl'])
        if q >= 2:
            c.rect((4, cy - 9, 22, cy + 9), p['gl'])
    # head
    hx = end
    if q == 0:   # split end with a dull stone tied on
        c.poly([(hx - 6, cy - 8), (hx + 40, cy - 22), (hx + 30, cy - 4), (hx + 30, cy + 4), (hx + 40, cy + 22), (hx - 6, cy + 8)], p['wood'])
        c.ellipse((hx + 22, cy - 13, hx + 50, cy + 13), (120, 116, 110))
        c.line([(hx + 8, cy - 10), (hx + 14, cy + 10)], (150, 120, 80), 3)
    elif q == 1:  # iron cap and a plain quartz
        c.rect((hx - 4, cy - 10, hx + 24, cy + 10), p['gl'])
        c.poly([(hx + 20, cy), (hx + 40, cy - 14), (hx + 80, cy - 10), (hx + 100, cy), (hx + 80, cy + 10), (hx + 40, cy + 14)], (190, 200, 214))
        c.poly([(hx + 20, cy), (hx + 100, cy), (hx + 80, cy + 10), (hx + 40, cy + 14)], (150, 160, 178))
    elif q == 2:  # bronze leaf claw with emerald
        c.rect((hx - 4, cy - 10, hx + 22, cy + 10), p['gl'])
        c.poly([(hx + 18, cy - 8), (hx + 40, cy - 30), (hx + 76, cy - 34), (hx + 54, cy - 14), (hx + 54, cy + 14), (hx + 76, cy + 34), (hx + 40, cy + 30), (hx + 18, cy + 8)], p['gl'])
        c.poly([(hx + 18, cy), (hx + 54, cy), (hx + 54, cy + 14), (hx + 76, cy + 34), (hx + 40, cy + 30), (hx + 18, cy + 8)], p['gd'])
        c.poly([(hx + 40, cy), (hx + 66, cy - 16), (hx + 120, cy), (hx + 66, cy + 16)], p['acc'])
        c.poly([(hx + 40, cy), (hx + 120, cy), (hx + 66, cy + 16)], (40, 150, 80))
    elif q == 3:  # silver claws holding a blue orb
        c.rect((hx - 4, cy - 11, hx + 22, cy + 11), p['gl'])
        c.poly([(hx + 18, cy - 9), (hx + 50, cy - 38), (hx + 100, cy - 36), (hx + 84, cy - 26), (hx + 56, cy - 22), (hx + 40, cy - 6),
                (hx + 40, cy + 6), (hx + 56, cy + 22), (hx + 84, cy + 26), (hx + 100, cy + 36), (hx + 50, cy + 38), (hx + 18, cy + 9)], p['gl'])
        c.ellipse((hx + 50, cy - 24, hx + 98, cy + 24), p['acc'])
        c.dot(hx + 66, cy - 8, 7, (210, 235, 255))
        c.halo_dot(hx + 74, cy, 30, p['glow'])
    elif q == 4:  # void crystal with floating shards
        c.rect((hx - 4, cy - 11, hx + 22, cy + 11), p['gl'])
        c.poly([(hx + 18, cy - 9), (hx + 36, cy - 30), (hx + 46, cy - 12), (hx + 46, cy + 12), (hx + 36, cy + 30), (hx + 18, cy + 9)], p['gl'])
        c.poly([(hx + 44, cy), (hx + 80, cy - 26), (hx + 140, cy), (hx + 80, cy + 26)], (70, 30, 110))
        c.poly([(hx + 44, cy), (hx + 80, cy - 26), (hx + 140, cy)], p['acc'])
        for sx, sy, s in ((hx + 70, cy - 38, 7), (hx + 110, cy + 34, 6), (hx + 120, cy - 30, 5)):
            c.poly([(sx - s, sy), (sx, sy - s * 1.6), (sx + s, sy), (sx, sy + s * 1.6)], p['acc'])
        c.halo_dot(hx + 92, cy, 34, p['glow'])
    else:         # phoenix: golden wings around a sun orb
        c.rect((hx - 4, cy - 11, hx + 22, cy + 11), p['gl'])
        c.poly([(hx + 16, cy - 8), (hx + 30, cy - 40), (hx + 56, cy - 44), (hx + 50, cy - 32), (hx + 72, cy - 42), (hx + 66, cy - 26),
                (hx + 48, cy - 12), (hx + 48, cy + 12), (hx + 66, cy + 26), (hx + 72, cy + 42), (hx + 50, cy + 32), (hx + 56, cy + 44),
                (hx + 30, cy + 40), (hx + 16, cy + 8)], p['gl'])
        c.poly([(hx + 16, cy), (hx + 48, cy), (hx + 48, cy + 12), (hx + 66, cy + 26), (hx + 72, cy + 42), (hx + 50, cy + 32), (hx + 56, cy + 44),
                (hx + 30, cy + 40), (hx + 16, cy + 8)], p['gd'])
        c.ellipse((hx + 56, cy - 26, hx + 108, cy + 26), p['acc'])
        c.ellipse((hx + 66, cy - 16, hx + 98, cy + 16), (255, 200, 90))
        for i in range(8):
            a = i * math.pi / 4
            c.line([(hx + 82 + 28 * math.cos(a), cy + 28 * math.sin(a)), (hx + 82 + 40 * math.cos(a), cy + 40 * math.sin(a))], (255, 180, 60), 3)
        c.halo_dot(hx + 82, cy, 44, p['glow'])
    return c.finish()


# ------------------------------------------------------------------ shield

def shield(q: int) -> Image.Image:
    w, h = SIZES['shield']
    c = Canvas(w, h)
    p = PAL[q]
    cx = w / 2
    if q == 0:   # wooden round-ish planks
        c.ellipse((10, 40, w - 10, h - 40), p['wood'])
        for x in (44, 78, 112):
            c.line([(x, 46), (x, h - 46)], p['wood_d'], 3)
        c.rect((10, 104, w - 10, 130), p['gd'])
        c.dot(cx, 117, 10, p['gl'])
        return c.finish()
    outline = [(12, 18), (cx, 8), (w - 12, 18), (w - 8, 130), (w - 26, 178), (cx, 226), (26, 178), (8, 130)]
    rim = {1: p['gl'], 2: p['gl'], 3: p['gl'], 4: p['gl'], 5: p['gl']}[q]
    c.poly(outline, rim)
    inner = [(24, 30), (cx, 22), (w - 24, 30), (w - 22, 126), (w - 36, 168), (cx, 208), (36, 168), (22, 126)]
    face = {1: (110, 120, 136), 2: (52, 116, 66), 3: (40, 90, 190), 4: (44, 32, 66), 5: (190, 70, 40)}[q]
    face_d = mix(face, (0, 0, 0), 0.22)
    c.poly(inner, face)
    c.poly([(cx, 22), (w - 24, 30), (w - 22, 126), (w - 36, 168), (cx, 208)], face_d)
    if q == 1:
        c.rect((cx - 5, 30, cx + 5, 200), p['gd'])
        for y in (60, 120, 170):
            c.dot(cx, y, 5, p['gl'])
    elif q == 2:   # bronze tree
        c.line([(cx, 190), (cx, 70)], p['gl'], 8)
        for a, b in (((cx, 120), (cx - 34, 84)), ((cx, 110), (cx + 34, 76)), ((cx, 90), (cx - 22, 60)), ((cx, 84), (cx + 22, 56))):
            c.line([a, b], p['gl'], 6)
        c.dot(cx, 64, 9, p['acc'])
    elif q == 3:   # silver chevron and star
        c.detail_poly([(30, 100), (cx, 70), (w - 30, 100), (w - 30, 118), (cx, 88), (30, 118)], p['gl'])
        star = [(cx + 22 * math.cos(a) * (1 if i % 2 == 0 else 0.45), 140 + 22 * math.sin(a) * (1 if i % 2 == 0 else 0.45))
                for i, a in enumerate([-math.pi / 2 + k * math.pi / 5 for k in range(10)])]
        c.detail_poly(star, (220, 236, 255))
        c.halo_dot(cx, 140, 18, p['glow'])
    elif q == 4:   # spikes on the rim and a void eye
        for (x, y, dx, dy) in ((12, 18, -12, -10), (w - 12, 18, 12, -10), (w - 8, 130, 14, 4), (8, 130, -14, 4), (cx, 226, 0, 14)):
            c.poly([(x - 6, y), (x + dx, y + dy), (x + 6, y + 2)], p['gl'])
        c.detail_poly([(cx - 34, 116), (cx, 92), (cx + 34, 116), (cx, 140)], p['acc'])
        c.dot(cx, 116, 9, (30, 10, 50))
        c.halo_dot(cx, 116, 26, p['glow'])
    else:          # golden sun
        c.dot(cx, 112, 30, (255, 200, 80))
        for i in range(12):
            a = i * math.pi / 6
            c.line([(cx + 34 * math.cos(a), 112 + 34 * math.sin(a)), (cx + 50 * math.cos(a), 112 + 50 * math.sin(a))], (255, 210, 110), 5)
        c.dot(cx, 112, 14, p['acc'])
        c.halo_dot(cx, 112, 46, p['glow'])
    return c.finish()


# ------------------------------------------------------------------ bow

def bow(q: int) -> Image.Image:
    w, h = SIZES['bow']
    c = Canvas(w, h)
    p = PAL[q]
    gy = h / 2
    tip_x, belly = 12, 50

    def x_at(y):
        t = min(1.0, abs(y - gy) / (gy - 12))
        return tip_x + belly * (1 - t ** 1.8)

    def limb(y0, y1, thick0, thick1, color):
        n = 40
        left, right = [], []
        for i in range(n + 1):
            y = y0 + (y1 - y0) * i / n
            th = thick0 + (thick1 - thick0) * i / n
            x = x_at(y)
            left.append((x - th / 2, y))
            right.append((x + th / 2, y))
        c.poly(left + right[::-1], color)

    wood = p['wood'] if q < 3 else {3: (70, 96, 150), 4: (60, 46, 86), 5: (200, 120, 46)}[q]
    wood_d = mix(wood, (0, 0, 0), 0.3)
    limb(12, gy, 7, 14, wood)
    limb(gy, h - 12, 14, 7, wood)
    # darker belly strip
    for y0, y1 in ((20, gy - 20), (gy + 20, h - 20)):
        pts = [(x_at(y) + 1, y) for y in range(int(y0), int(y1), 6)]
        c.line(pts, wood_d, 4)
    # grip
    gx = x_at(gy)
    c.rect((gx - 10, gy - 26, gx + 10, gy + 26), p['grip'])
    if q >= 2:
        for y in range(int(gy - 22), int(gy + 22), 8):
            c.line([(gx - 10, y), (gx + 10, y + 5)], mix(p['grip'], (0, 0, 0), 0.35), 2)
    if q == 0:
        c.line([(x_at(150), 150), (x_at(158) + 4, 158)], (70, 50, 30), 3)
    if q >= 2:   # tip caps
        for y in (14, h - 14):
            c.ellipse((tip_x - 7, y - 7, tip_x + 7, y + 7), p['gl'])
    if q == 3:   # silver plates and a feather
        for y in (gy - 90, gy + 90):
            c.rect((x_at(y) - 9, y - 10, x_at(y) + 9, y + 10), p['gl'])
        c.detail_poly([(gx + 10, gy - 6), (gx + 26, gy + 30), (gx + 14, gy + 34), (gx + 6, gy + 4)], (230, 240, 255))
        c.halo([(x_at(y), y) for y in range(30, h - 30, 20)], p['glow'], 5)
    if q == 4:   # spikes on the back of the limbs
        for y in (gy - 150, gy - 95, gy + 95, gy + 150):
            x = x_at(y)
            c.poly([(x + 4, y - 6), (x + 20, y), (x + 4, y + 6)], p['gl'])
        c.line([(x_at(y) - 2, y) for y in range(30, h - 30, 12)], p['acc'], 2)
        c.halo([(x_at(y), y) for y in range(30, h - 30, 20)], p['glow'], 8)
    if q == 5:   # flame tips and a sun gem
        for y, d in ((40, -1), (h - 40, 1)):
            x = x_at(y)
            c.poly([(x - 6, y), (x + 14, y - 14 * d), (x + 6, y + 4 * d), (x + 20, y + 10 * d), (x + 4, y + 16 * d)], p['acc'])
        c.dot(gx, gy, 8, p['acc'])
        c.halo([(x_at(y), y) for y in range(30, h - 30, 20)], p['glow'], 12)
    return c.finish()


DRAW = {'sword': lambda q: sword(q), 'greatsword': lambda q: sword(q, True), 'staff': staff, 'shield': shield, 'bow': bow}


def main(out: Path) -> None:
    for kind, draw in DRAW.items():
        for q in range(6):
            folder = out / 'output' / f'{kind}_q{q}'
            folder.mkdir(parents=True, exist_ok=True)
            img = draw(q)
            assert img.size == SIZES[kind]
            img.save(folder / 'weapon.png', optimize=True)


if __name__ == '__main__':
    main(Path(sys.argv[1]))
