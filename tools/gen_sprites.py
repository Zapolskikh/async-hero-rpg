"""Generates the placeholder pixel-art used by the prototype.

    python3 tools/gen_sprites.py

Writes assets/units/<id>.png (characters facing right) and assets/bg/*.png.
Every sprite is built from simple parts (legs, body, head, headgear, weapon),
so new archetypes are a few lines in UNITS. Replace the PNGs with real art
later: the game only cares about the file names.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
UNIT_DIR = ROOT / "assets" / "units"
BG_DIR = ROOT / "assets" / "bg"

OUTLINE = (24, 20, 28, 255)
SKIN = (238, 196, 150)
SKIN_GREEN = (120, 168, 84)
SKIN_GREY = (178, 182, 170)
BONE = (226, 222, 200)
STEEL = (168, 178, 190)
STEEL_DARK = (110, 120, 134)
WOOD = (122, 84, 52)
GOLD = (232, 186, 64)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if 0 <= xx < self.w and 0 <= yy < self.h:
                    self.px[yy][xx] = c[:3]

    def dot(self, x, y, c):
        self.rect(x, y, 1, 1, c)

    def line_v(self, x, y0, y1, c):
        self.rect(x, y0, 1, y1 - y0 + 1, c)

    def image(self, outline=True):
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y][x]
                if c is not None:
                    img.putpixel((x, y), c + (255,))
                elif outline and self._near(x, y):
                    img.putpixel((x, y), OUTLINE)
        return img

    def _near(self, x, y):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, yy = x + dx, y + dy
            if 0 <= xx < self.w and 0 <= yy < self.h and self.px[yy][xx] is not None:
                return True
        return False


def humanoid(c, ox, oy, p):
    """Draws a 32x40 figure facing right with its top-left at (ox, oy)."""
    tunic = hexc(p["tunic"])
    pants = hexc(p.get("pants", "#4a3b32"))
    skin = p.get("skin", SKIN)
    bulky = p.get("bulky", False)
    robe = p.get("robe", False)
    bx0, bx1 = (9, 22) if bulky else (11, 20)

    # back arm (darker, behind the body)
    c.rect(ox + bx0 - 2, oy + 21, 2, 8, shade(tunic, 0.7))
    c.rect(ox + bx0 - 2, oy + 29, 2, 2, shade(skin, 0.85))
    # legs / robe
    if robe:
        for i, y in enumerate(range(28, 38)):
            grow = i // 3
            c.rect(ox + bx0 - grow, oy + y, (bx1 - bx0 + 1) + grow * 2, 1, shade(tunic, 0.9 if y % 4 else 0.8))
        c.rect(ox + 12, oy + 38, 3, 2, (60, 44, 36))
        c.rect(ox + 17, oy + 38, 3, 2, (60, 44, 36))
    else:
        c.rect(ox + 12, oy + 31, 3, 7, pants)
        c.rect(ox + 17, oy + 31, 3, 7, shade(pants, 0.85))
        c.rect(ox + 12, oy + 37, 4, 3, (60, 44, 36))
        c.rect(ox + 17, oy + 37, 4, 3, (52, 38, 30))
    # body
    c.rect(ox + bx0, oy + 20, bx1 - bx0 + 1, 11, tunic)
    c.rect(ox + bx0, oy + 26, bx1 - bx0 + 1, 5, shade(tunic, 0.85))
    if p.get("belt", True) and not robe:
        c.rect(ox + bx0, oy + 28, bx1 - bx0 + 1, 1, (70, 50, 34))
        c.dot(ox + 16, oy + 28, GOLD)
    if p.get("armor"):
        c.rect(ox + bx0, oy + 20, bx1 - bx0 + 1, 7, STEEL)
        c.rect(ox + bx0, oy + 24, bx1 - bx0 + 1, 1, STEEL_DARK)
        c.rect(ox + bx0 - 1, oy + 20, 3, 3, STEEL_DARK)
        c.rect(ox + bx1 - 1, oy + 20, 3, 3, STEEL_DARK)
    # head
    c.rect(ox + 12, oy + 10, 8, 10, skin)
    c.rect(ox + 12, oy + 18, 8, 2, shade(skin, 0.9))
    c.dot(ox + 18, oy + 14, (30, 24, 30))
    c.dot(ox + 18, oy + 13, (30, 24, 30))
    if p.get("eyes_glow"):
        c.dot(ox + 18, oy + 14, hexc(p["eyes_glow"]))
        c.dot(ox + 18, oy + 13, hexc(p["eyes_glow"]))
    if p.get("tusk"):
        c.dot(ox + 19, oy + 18, BONE)
    head = p.get("head", "hair")
    hair = hexc(p.get("hair", "#5a3a22"))
    if head == "hair":
        c.rect(ox + 11, oy + 8, 9, 3, hair)
        c.rect(ox + 11, oy + 11, 2, 5, hair)
    elif head == "helmet":
        c.rect(ox + 11, oy + 7, 10, 6, STEEL)
        c.rect(ox + 11, oy + 12, 2, 6, STEEL_DARK)
        c.rect(ox + 19, oy + 12, 2, 2, STEEL_DARK)
        if p.get("plume"):
            c.rect(ox + 13, oy + 4, 5, 3, hexc(p["plume"]))
    elif head == "hood":
        hood = hexc(p.get("hood", p["tunic"]))
        c.rect(ox + 10, oy + 7, 10, 4, hood)
        c.rect(ox + 10, oy + 11, 3, 9, hood)
        c.rect(ox + 19, oy + 9, 2, 3, shade(hood, 0.85))
        c.rect(ox + 13, oy + 11, 6, 2, shade(skin, 0.6))
    elif head == "wizard":
        hat = hexc(p.get("hat", p["tunic"]))
        c.rect(ox + 9, oy + 9, 14, 2, hat)
        c.rect(ox + 12, oy + 5, 8, 4, hat)
        c.rect(ox + 14, oy + 2, 5, 3, hat)
        c.rect(ox + 16, oy + 0, 3, 2, hat)
        c.rect(ox + 12, oy + 8, 8, 1, GOLD)
        c.rect(ox + 11, oy + 11, 2, 4, hexc(p.get("hair", "#d8d8d8")))
    elif head == "horns":
        c.rect(ox + 11, oy + 8, 9, 2, hair)
        c.rect(ox + 10, oy + 5, 2, 4, BONE)
        c.rect(ox + 19, oy + 5, 2, 4, BONE)
    elif head == "crown":
        c.rect(ox + 11, oy + 7, 10, 3, GOLD)
        c.dot(ox + 12, oy + 6, GOLD)
        c.dot(ox + 15, oy + 6, GOLD)
        c.dot(ox + 19, oy + 6, GOLD)
        c.dot(ox + 15, oy + 8, (220, 60, 60))
    elif head == "feathers":
        c.rect(ox + 11, oy + 8, 9, 2, hair)
        c.rect(ox + 11, oy + 4, 2, 5, (220, 80, 60))
        c.rect(ox + 13, oy + 3, 2, 6, (240, 200, 70))
        c.rect(ox + 15, oy + 5, 2, 4, (80, 170, 220))
    if p.get("beard"):
        c.rect(ox + 15, oy + 17, 5, 4, hexc(p["beard"]))
    # front arm
    c.rect(ox + bx1 + 1, oy + 21, 2, 7, shade(tunic, 1.05))
    c.rect(ox + bx1 + 1, oy + 28, 2, 2, skin)
    if p.get("armor"):
        c.rect(ox + bx1 + 1, oy + 21, 2, 3, STEEL)
    weapon(c, ox + bx1 + 3, oy, p)
    if p.get("shield"):
        sc = hexc(p["shield"])
        c.rect(ox + bx1 - 1, oy + 20, 7, 11, sc)
        c.rect(ox + bx1 - 1, oy + 20, 7, 1, STEEL)
        c.rect(ox + bx1 + 1, oy + 23, 3, 5, GOLD)
    if p.get("cape"):
        cape = hexc(p["cape"])
        c.rect(ox + bx0 - 3, oy + 20, 2, 15, cape)


def weapon(c, x, oy, p):
    w = p.get("weapon")
    if w == "sword":
        c.rect(x, oy + 13, 2, 15, (220, 226, 236))
        c.rect(x - 1, oy + 27, 4, 1, GOLD)
        c.rect(x, oy + 28, 2, 3, WOOD)
    elif w == "staff":
        c.rect(x, oy + 6, 2, 33, WOOD)
        orb = hexc(p.get("orb", "#7fd0ff"))
        c.rect(x - 1, oy + 2, 4, 4, orb)
        c.dot(x, oy + 3, (255, 255, 255))
    elif w == "bow":
        for i, y in enumerate(range(15, 35)):
            off = 2 - abs(i - 10) // 4
            c.dot(x + off, oy + y, WOOD)
        c.line_v(x - 1, oy + 16, oy + 33, (230, 230, 230))
    elif w == "dagger":
        c.rect(x, oy + 22, 2, 7, (220, 226, 236))
        c.rect(x, oy + 29, 2, 2, WOOD)
    elif w == "axe":
        c.rect(x, oy + 12, 2, 20, WOOD)
        c.rect(x + 2, oy + 12, 4, 6, STEEL)
        c.rect(x - 2, oy + 13, 2, 4, STEEL_DARK)
    elif w == "mace":
        c.rect(x, oy + 17, 2, 13, WOOD)
        c.rect(x - 1, oy + 13, 4, 5, STEEL)
    elif w == "club":
        c.rect(x, oy + 12, 3, 18, WOOD)
        c.rect(x - 1, oy + 9, 5, 7, shade(WOOD, 0.85))
        c.dot(x + 3, oy + 11, BONE)
    elif w == "flask":
        c.rect(x, oy + 22, 3, 5, (120, 220, 90))
        c.rect(x + 1, oy + 20, 1, 2, (200, 200, 200))
    elif w == "scythe":
        c.rect(x, oy + 4, 2, 35, (70, 60, 70))
        c.rect(x - 8, oy + 3, 10, 2, (200, 210, 220))
        c.rect(x - 8, oy + 5, 3, 2, (200, 210, 220))


# Allies: hero and guild mercenary roles. Enemies: archetypes and bosses.
UNITS = {
    "hero":      {"tunic": "#3f7fd6", "pants": "#3a3550", "weapon": "sword", "cape": "#c23b3b", "hair": "#7a4a22"},
    "tank":      {"tunic": "#6d7a8a", "armor": True, "head": "helmet", "plume": "#c23b3b", "weapon": "sword", "shield": "#3a64a8"},
    "healer":    {"tunic": "#e8e4d4", "robe": True, "head": "hair", "hair": "#e0c070", "weapon": "staff", "orb": "#7dff9a"},
    "pyromancer": {"tunic": "#b8342a", "robe": True, "head": "wizard", "hat": "#8a2620", "weapon": "staff", "orb": "#ffa53a"},
    "poisoner_ally": {"tunic": "#3f7a3a", "head": "hood", "hood": "#2f5a2c", "weapon": "dagger"},
    "fighter":   {"tunic": "#8a5a34", "head": "hair", "hair": "#2e2420", "weapon": "axe", "bulky": True, "beard": "#2e2420"},
    "guard":     {"tunic": "#7a7f88", "armor": True, "head": "helmet", "weapon": "mace"},
    "paladin":   {"tunic": "#f0e6c8", "armor": True, "head": "helmet", "plume": "#e8ba40", "weapon": "mace", "shield": "#d8b040", "cape": "#e8e0c8"},
    "hunter":    {"tunic": "#4f7a3a", "head": "hood", "hood": "#3e5f2c", "weapon": "bow"},

    "brute":     {"tunic": "#7a5a3a", "skin": SKIN_GREEN, "head": "horns", "hair": "#3a2a1a", "weapon": "club", "bulky": True, "tusk": True, "belt": True},
    "caster":    {"tunic": "#6a3fb0", "robe": True, "head": "hood", "hood": "#4a2a80", "weapon": "staff", "orb": "#c87bff", "skin": SKIN_GREY, "eyes_glow": "#ff5af0"},
    "e_healer":  {"tunic": "#3f8a5a", "robe": True, "head": "feathers", "hair": "#2a2a2a", "weapon": "staff", "orb": "#9dff7a", "skin": SKIN_GREEN},
    "e_tank":    {"tunic": "#4a4f58", "armor": True, "head": "helmet", "weapon": "mace", "shield": "#5a2a2a", "bulky": True, "skin": SKIN_GREEN},
    "ranged":    {"tunic": "#8a7a3a", "head": "hood", "hood": "#6a5a2a", "weapon": "bow", "skin": SKIN_GREEN},
    "assassin":  {"tunic": "#2c2f3a", "head": "hood", "hood": "#1c1e26", "weapon": "dagger", "eyes_glow": "#ff4040", "cape": "#4a1a24"},
    "poisoner":  {"tunic": "#5a7a2a", "robe": True, "head": "hood", "hood": "#3a5a1a", "weapon": "flask", "skin": SKIN_GREEN},
}

BOSSES = {
    "boss_ogre": ({"tunic": "#8a3a2a", "skin": (150, 140, 90), "head": "crown", "weapon": "club", "bulky": True, "tusk": True, "beard": "#4a2a1a"}, 2),
    "boss_lich": ({"tunic": "#3a2a5a", "robe": True, "skin": BONE, "head": "crown", "weapon": "scythe", "eyes_glow": "#6af0ff", "cape": "#2a1a40"}, 2),
}

MERC_ROLE_SPRITE = {
    "Танк": "tank", "Лекарь": "healer", "Пиромант": "pyromancer", "Ядовик": "poisoner_ally",
    "Боец": "fighter", "Страж": "guard", "Паладин": "paladin", "Охотник": "hunter",
}


def make_unit(params, scale=1):
    c = Canvas(32, 40)
    humanoid(c, 0, 0, params)
    img = c.image()
    # 1px transparent margin so the outline never touches the border
    out = Image.new("RGBA", (34, 42), (0, 0, 0, 0))
    out.paste(img, (1, 1))
    if scale > 1:
        out = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    return out


def make_backgrounds():
    w, h = 320, 180
    sky = Image.new("RGBA", (w, h))
    top, bottom = (126, 182, 226), (214, 232, 240)
    for y in range(h):
        t = y / (h - 1)
        col = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(w):
            sky.putpixel((x, y), col)
    px = sky.load()
    import math
    # distant mountains
    for x in range(w):
        m = int(70 + 18 * math.sin(x * 0.045) + 10 * math.sin(x * 0.11 + 1.3))
        for y in range(m, h):
            px[x, y] = (150, 170, 190, 255)
    # hills
    for x in range(w):
        m = int(100 + 8 * math.sin(x * 0.03 + 2.0) + 4 * math.sin(x * 0.09))
        for y in range(m, h):
            px[x, y] = (110, 160, 96, 255)
    # trees on the hills
    for i, tx in enumerate(range(6, w, 23)):
        base = int(100 + 8 * math.sin(tx * 0.03 + 2.0) + 4 * math.sin(tx * 0.09)) + 2
        size = 7 + (i * 5) % 5
        for y in range(base - size * 2, base):
            half = (y - (base - size * 2)) // 2
            for x in range(tx - half, tx + half + 1):
                if 0 <= x < w:
                    px[x, y] = (62, 112, 70, 255)
        for y in range(base, base + 3):
            px[tx, y] = (90, 64, 44, 255)
    # clouds
    for cx, cy, cw in ((40, 22, 30), (150, 14, 40), (250, 30, 26)):
        for x in range(cx, cx + cw):
            for y in range(cy, cy + 6):
                if (x - cx) > 3 and (cx + cw - x) > 3 or 1 < y - cy < 5:
                    px[x % w, y] = (245, 248, 252, 255)
    sky.save(BG_DIR / "sky.png")

    ground = Image.new("RGBA", (64, 32))
    gp = ground.load()
    for y in range(32):
        for x in range(64):
            if y < 4:
                col = (96, 156, 74) if (x + y) % 5 else (120, 178, 84)
            elif y < 6:
                col = (122, 98, 62)
            else:
                col = (176, 146, 96) if (x * 7 + y * 13) % 11 else (150, 122, 80)
            gp[x, y] = col + (255,)
    ground.save(BG_DIR / "ground.png")


def main():
    UNIT_DIR.mkdir(parents=True, exist_ok=True)
    BG_DIR.mkdir(parents=True, exist_ok=True)
    for uid, params in UNITS.items():
        make_unit(params).save(UNIT_DIR / f"{uid}.png")
    for uid, (params, scale) in BOSSES.items():
        make_unit(params, scale).save(UNIT_DIR / f"{uid}.png")
    make_backgrounds()
    # contact sheet for review
    names = list(UNITS) + list(BOSSES)
    sheet = Image.new("RGBA", (len(names) * 72, 90), (40, 44, 54, 255))
    for i, n in enumerate(names):
        im = Image.open(UNIT_DIR / f"{n}.png")
        if im.height < 60:
            im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        else:
            im = im.resize((im.width, im.height), Image.NEAREST)
        sheet.alpha_composite(im, (i * 72 + (72 - im.width) // 2, 90 - im.height))
    sheet.save(ROOT / "tools" / "sprite_sheet_preview.png")
    print("generated", len(names), "sprites")


if __name__ == "__main__":
    main()
