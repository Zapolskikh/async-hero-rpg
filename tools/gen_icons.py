"""Generates 16x16 placeholder pixel icons into assets/icons/.

    python3 tools/gen_icons.py

Each icon is a few PIL shapes plus an automatic dark outline. The UI scales
them with nearest filtering. Replace any PNG with real art of the same name.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icons"
OUTLINE = (28, 24, 34, 255)


def icon(draw_fn, outline=True):
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_fn(d)
    if outline:
        src = img.copy()
        px = src.load()
        out = img.load()
        for y in range(16):
            for x in range(16):
                if px[x, y][3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < 16 and 0 <= yy < 16 and px[xx, yy][3] > 0:
                            out[x, y] = OUTLINE
                            break
    return img


C = {
    "gold": (246, 196, 60), "gold_d": (200, 140, 30), "white": (250, 250, 250),
    "red": (226, 72, 72), "red_d": (170, 40, 50), "green": (110, 200, 96), "green_d": (60, 140, 70),
    "blue": (90, 160, 240), "blue_d": (50, 100, 190), "cyan": (110, 220, 240), "purple": (170, 110, 240),
    "purple_d": (110, 60, 180), "orange": (255, 150, 50), "yellow": (255, 226, 80), "steel": (200, 210, 222),
    "steel_d": (130, 140, 156), "wood": (150, 100, 60), "brown": (120, 80, 50), "skin": (240, 200, 160),
    "grey": (150, 150, 160), "dark": (60, 60, 72), "bone": (236, 232, 214),
}


def sword(d, col="steel"):
    d.line([(3, 12), (12, 3)], fill=C[col], width=2)
    d.point((13, 2), fill=C["white"])
    d.line([(2, 9), (6, 13)], fill=C["gold"], width=1)
    d.line([(1, 14), (3, 12)], fill=C["wood"], width=2)


ICONS = {
    # resources
    "gold": lambda d: (d.ellipse([2, 2, 13, 13], fill=C["gold"]), d.ellipse([4, 4, 11, 11], outline=C["gold_d"]),
                       d.line([(7, 5), (7, 10)], fill=C["gold_d"])),
    "box": lambda d: (d.rectangle([2, 6, 13, 13], fill=C["purple"]), d.rectangle([1, 4, 14, 7], fill=C["purple_d"]),
                      d.rectangle([7, 4, 8, 13], fill=C["gold"]), d.point((5, 3), fill=C["gold"]), d.point((10, 3), fill=C["gold"]),
                      d.line([(6, 2), (7, 3)], fill=C["gold"]), d.line([(9, 2), (8, 3)], fill=C["gold"])),
    "crystal": lambda d: (d.polygon([(8, 1), (13, 6), (8, 14), (3, 6)], fill=C["cyan"]),
                          d.polygon([(8, 1), (8, 14), (3, 6)], fill=(70, 180, 220)), d.point((6, 5), fill=C["white"])),
    "xp": lambda d: d.polygon([(8, 1), (10, 6), (15, 6), (11, 9), (13, 14), (8, 11), (3, 14), (5, 9), (1, 6), (6, 6)], fill=C["yellow"]),
    # stats
    "hp": lambda d: (d.ellipse([1, 3, 8, 10], fill=C["red"]), d.ellipse([7, 3, 14, 10], fill=C["red"]),
                     d.polygon([(2, 8), (13, 8), (8, 14)], fill=C["red"]), d.point((4, 5), fill=C["white"])),
    "atk": lambda d: sword(d),
    "power": lambda d: (d.ellipse([3, 3, 12, 12], fill=C["blue"]), d.ellipse([5, 5, 9, 9], fill=C["cyan"]),
                        d.point((6, 6), fill=C["white"]), d.point((13, 2), fill=C["yellow"]), d.point((2, 13), fill=C["yellow"])),
    "armor": lambda d: (d.polygon([(2, 2), (13, 2), (13, 8), (8, 14), (2, 8)], fill=C["steel"]),
                        d.polygon([(8, 2), (13, 2), (13, 8), (8, 14)], fill=C["steel_d"])),
    "haste": lambda d: d.polygon([(9, 1), (3, 9), (7, 9), (5, 15), (13, 6), (8, 6), (11, 1)], fill=C["yellow"]),
    "crit": lambda d: (d.ellipse([2, 2, 13, 13], outline=C["red"], width=2), d.ellipse([6, 6, 9, 9], fill=C["red"]),
                       d.line([(8, 0), (8, 3)], fill=C["red"]), d.line([(8, 12), (8, 15)], fill=C["red"]),
                       d.line([(0, 8), (3, 8)], fill=C["red"]), d.line([(12, 8), (15, 8)], fill=C["red"])),
    # navigation
    "nav_map": lambda d: (d.polygon([(1, 3), (5, 1), (10, 3), (14, 1), (14, 12), (10, 14), (5, 12), (1, 14)], fill=(236, 214, 160)),
                          d.line([(5, 1), (5, 12)], fill=(200, 176, 120)), d.line([(10, 3), (10, 14)], fill=(200, 176, 120)),
                          d.line([(3, 10), (7, 7), (9, 9), (12, 5)], fill=C["red"]), d.point((12, 5), fill=C["red_d"])),
    "nav_hero": lambda d: (d.ellipse([3, 2, 12, 12], fill=C["steel"]), d.rectangle([3, 7, 12, 13], fill=C["steel"]),
                           d.rectangle([5, 7, 10, 9], fill=C["dark"]), d.line([(7, 0), (8, 3)], fill=C["red"], width=2)),
    "nav_mercs": lambda d: (d.ellipse([1, 3, 6, 8], fill=C["skin"]), d.rectangle([0, 9, 7, 14], fill=C["blue"]),
                            d.ellipse([9, 2, 14, 7], fill=C["skin"]), d.rectangle([8, 8, 15, 14], fill=C["green"]),
                            d.rectangle([1, 2, 6, 4], fill=C["brown"]), d.rectangle([9, 1, 14, 3], fill=C["dark"])),
    "nav_spells": lambda d: (d.rectangle([2, 2, 13, 14], fill=C["purple_d"]), d.rectangle([4, 2, 13, 13], fill=C["purple"]),
                             d.rectangle([2, 13, 13, 14], fill=C["bone"]), d.polygon([(8, 5), (9, 7), (11, 8), (9, 9), (8, 11), (7, 9), (5, 8), (7, 7)], fill=C["yellow"])),
    "nav_bag": lambda d: (d.rounded_rectangle([2, 5, 13, 14], 2, fill=C["wood"]), d.arc([5, 1, 10, 8], 180, 360, fill=C["brown"], width=2),
                          d.rectangle([2, 8, 13, 9], fill=C["brown"]), d.rectangle([7, 8, 8, 10], fill=C["gold"])),
    # misc
    "lock": lambda d: (d.arc([4, 1, 11, 10], 180, 360, fill=C["steel_d"], width=2), d.rectangle([3, 7, 12, 14], fill=C["gold"]),
                       d.rectangle([7, 9, 8, 12], fill=C["dark"])),
    "boss": lambda d: (d.ellipse([2, 1, 13, 11], fill=C["bone"]), d.rectangle([4, 9, 11, 14], fill=C["bone"]),
                       d.rectangle([4, 5, 6, 7], fill=C["dark"]), d.rectangle([9, 5, 11, 7], fill=C["dark"]),
                       d.line([(5, 12), (10, 12)], fill=C["dark"])),
    "check": lambda d: d.line([(2, 8), (6, 12), (13, 3)], fill=C["green"], width=3),
    "swords": lambda d: (d.line([(2, 2), (13, 13)], fill=C["steel"], width=2), d.line([(13, 2), (2, 13)], fill=C["steel"], width=2),
                         d.line([(1, 12), (4, 15)], fill=C["gold"]), d.line([(14, 12), (11, 15)], fill=C["gold"])),
    "loop": lambda d: (d.arc([2, 2, 13, 13], 30, 330, fill=C["green"], width=2), d.polygon([(11, 1), (15, 4), (11, 6)], fill=C["green"])),
    "watch": lambda d: (d.ellipse([1, 4, 14, 11], fill=C["white"]), d.ellipse([5, 4, 10, 11], fill=C["blue"]), d.ellipse([7, 6, 8, 9], fill=C["dark"])),
    "settings": lambda d: (d.ellipse([3, 3, 12, 12], fill=C["steel"]), d.ellipse([6, 6, 9, 9], fill=C["dark"]),
                           d.rectangle([7, 0, 8, 3], fill=C["steel"]), d.rectangle([7, 12, 8, 15], fill=C["steel"]),
                           d.rectangle([0, 7, 3, 8], fill=C["steel"]), d.rectangle([12, 7, 15, 8], fill=C["steel"]),
                           d.point((2, 2), fill=C["steel"]), d.point((13, 13), fill=C["steel"]),
                           d.point((13, 2), fill=C["steel"]), d.point((2, 13), fill=C["steel"])),
    "online": lambda d: (d.ellipse([1, 1, 14, 14], outline=C["green"], width=2), d.line([(1, 8), (14, 8)], fill=C["green"]),
                         d.arc([4, 1, 11, 14], 90, 270, fill=C["green"]), d.arc([4, 1, 11, 14], 270, 90, fill=C["green"])),
    "trophy": lambda d: (d.rectangle([4, 2, 11, 8], fill=C["gold"]), d.arc([0, 2, 6, 8], 90, 270, fill=C["gold"], width=2),
                         d.arc([9, 2, 15, 8], 270, 90, fill=C["gold"], width=2), d.rectangle([7, 9, 8, 11], fill=C["gold_d"]),
                         d.rectangle([4, 12, 11, 14], fill=C["gold_d"])),
    "star": lambda d: d.polygon([(8, 1), (10, 6), (15, 6), (11, 9), (13, 14), (8, 11), (3, 14), (5, 9), (1, 6), (6, 6)], fill=C["yellow"]),
    # item slots
    "item_weapon": lambda d: sword(d),
    "item_armor": lambda d: (d.polygon([(4, 2), (6, 2), (8, 4), (10, 2), (12, 2), (14, 5), (12, 7), (12, 14), (4, 14), (4, 7), (2, 5)], fill=C["steel"]),
                             d.rectangle([4, 9, 12, 10], fill=C["steel_d"])),
    "item_trinket": lambda d: (d.arc([3, 0, 12, 9], 0, 180, fill=C["gold"]), d.line([(3, 4), (7, 9)], fill=C["gold"]), d.line([(12, 4), (8, 9)], fill=C["gold"]),
                               d.polygon([(8, 8), (12, 11), (8, 15), (4, 11)], fill=C["red"]), d.point((7, 10), fill=C["white"])),
    # spells (glyph only; the UI draws the rarity-coloured tile behind them)
    "sp_strike": lambda d: (sword(d), d.arc([4, 0, 15, 11], 270, 360, fill=C["white"])),
    "sp_fireball": lambda d: (d.ellipse([5, 5, 14, 14], fill=C["orange"]), d.polygon([(1, 2), (8, 6), (6, 9)], fill=C["orange"]),
                              d.polygon([(3, 1), (9, 5), (7, 7)], fill=C["yellow"]), d.ellipse([7, 7, 11, 11], fill=C["yellow"])),
    "sp_cleave": lambda d: (d.arc([1, 1, 15, 15], 200, 340, fill=C["white"], width=2), d.line([(5, 14), (11, 4)], fill=C["wood"], width=2),
                            d.polygon([(10, 2), (15, 4), (12, 8)], fill=C["steel"])),
    "sp_chain_lightning": lambda d: d.line([(2, 1), (9, 5), (4, 8), (12, 11), (7, 15)], fill=C["cyan"], width=2),
    "sp_ignite": lambda d: (d.polygon([(8, 1), (13, 9), (11, 14), (5, 14), (3, 9)], fill=C["orange"]),
                            d.polygon([(8, 6), (10, 11), (8, 14), (6, 11)], fill=C["yellow"])),
    "sp_poison_cloud": lambda d: (d.ellipse([1, 5, 8, 12], fill=C["green"]), d.ellipse([6, 3, 14, 11], fill=C["green"]),
                                  d.ellipse([4, 8, 12, 14], fill=C["green_d"]), d.point((5, 7), fill=C["white"]), d.point((10, 6), fill=C["white"])),
    "sp_execute": lambda d: (d.line([(3, 14), (11, 4)], fill=C["wood"], width=2), d.polygon([(8, 2), (15, 2), (14, 9), (9, 6)], fill=C["red"]),
                             d.point((14, 3), fill=C["white"])),
    "sp_kick": lambda d: (d.rectangle([5, 1, 9, 9], fill=C["brown"]), d.polygon([(5, 9), (14, 9), (14, 13), (5, 13)], fill=C["brown"]),
                          d.line([(1, 4), (3, 4)], fill=C["white"]), d.line([(1, 7), (3, 7)], fill=C["white"])),
    "sp_bash": lambda d: (d.rectangle([2, 3, 11, 9], fill=C["steel"]), d.line([(7, 9), (7, 15)], fill=C["wood"], width=2),
                          d.point((13, 2), fill=C["yellow"]), d.point((14, 6), fill=C["yellow"]), d.point((12, 11), fill=C["yellow"])),
    "sp_drain": lambda d: (d.polygon([(8, 1), (13, 9), (8, 14), (3, 9)], fill=C["red"]), d.ellipse([3, 6, 13, 15], fill=C["red"]),
                           d.point((6, 8), fill=C["white"])),
    "sp_heal": lambda d: (d.rectangle([6, 2, 9, 13], fill=C["green"]), d.rectangle([2, 6, 13, 9], fill=C["green"]),
                          d.point((7, 3), fill=C["white"])),
    "sp_renew": lambda d: (d.polygon([(2, 14), (4, 6), (10, 2), (14, 2), (12, 8), (6, 12)], fill=C["green"]),
                           d.line([(3, 13), (11, 5)], fill=C["green_d"])),
    "sp_barrier": lambda d: (d.ellipse([1, 1, 14, 14], outline=C["blue"], width=2), d.ellipse([4, 4, 11, 11], fill=(150, 210, 255)),
                             d.point((6, 5), fill=C["white"])),
    "sp_taunt": lambda d: (d.polygon([(2, 6), (10, 2), (10, 14), (2, 10)], fill=C["red"]), d.rectangle([10, 5, 12, 11], fill=C["red_d"]),
                           d.line([(13, 3), (15, 1)], fill=C["white"]), d.line([(13, 8), (15, 8)], fill=C["white"]), d.line([(13, 13), (15, 15)], fill=C["white"])),
    "sp_cleanse": lambda d: (d.polygon([(8, 1), (10, 6), (15, 8), (10, 10), (8, 15), (6, 10), (1, 8), (6, 6)], fill=C["white"]),
                             d.ellipse([6, 6, 10, 10], fill=C["cyan"])),
}


# ---------------------------------------------------------------- professions
def ore(col, spark=None):
    c = hexc_(col)
    def f(d):
        d.polygon([(2, 10), (4, 5), (8, 3), (12, 5), (14, 10), (11, 14), (5, 14)], fill=shade_(c, 0.8))
        d.polygon([(4, 9), (6, 5), (9, 4), (11, 7), (9, 11), (5, 11)], fill=c)
        d.point((7, 6), fill=(255, 255, 255))
        if spark:
            for x, y in ((11, 9), (5, 12), (12, 6)):
                d.point((x, y), fill=hexc_(spark))
    return f

def herb(leaf, flower=None):
    l = hexc_(leaf)
    def f(d):
        d.line([(8, 15), (8, 5)], fill=shade_(l, 0.7), width=1)
        d.ellipse([2, 7, 8, 11], fill=l)
        d.ellipse([8, 9, 14, 13], fill=shade_(l, 0.85))
        if flower:
            fc = hexc_(flower)
            d.ellipse([5, 1, 11, 7], fill=fc)
            d.point((8, 4), fill=(255, 240, 160))
        else:
            d.ellipse([6, 2, 11, 7], fill=l)
    return f

def hide(col):
    c = hexc_(col)
    def f(d):
        d.polygon([(3, 2), (6, 4), (10, 4), (13, 2), (12, 7), (14, 13), (10, 12), (6, 12), (2, 13), (4, 7)], fill=c)
        d.polygon([(6, 6), (10, 6), (10, 10), (6, 10)], fill=shade_(c, 0.85))
    return f

def leather(col):
    c = hexc_(col)
    def f(d):
        d.rectangle([2, 4, 13, 12], fill=c)
        d.ellipse([10, 4, 15, 12], fill=shade_(c, 0.8))
        d.line([(3, 6), (11, 6)], fill=shade_(c, 0.7))
        d.line([(3, 10), (11, 10)], fill=shade_(c, 0.7))
    return f

def cloth(col):
    c = hexc_(col)
    def f(d):
        d.polygon([(2, 5), (12, 3), (14, 6), (4, 8)], fill=shade_(c, 1.1))
        d.polygon([(2, 8), (12, 6), (14, 9), (4, 11)], fill=c)
        d.polygon([(2, 11), (12, 9), (14, 12), (4, 14)], fill=shade_(c, 0.85))
    return f

def potion(col):
    c = hexc_(col)
    def f(d):
        d.rectangle([6, 1, 9, 4], fill=(200, 200, 210))
        d.rectangle([6, 0, 9, 1], fill=(140, 100, 60))
        d.ellipse([2, 4, 13, 15], fill=c)
        d.ellipse([4, 6, 7, 9], fill=(255, 255, 255))
    return f

def hexc_(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def shade_(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])

ICONS.update({
    "res_copper_ore": ore("#d9823b"), "res_iron_ore": ore("#9aa3ad"), "res_silver_ore": ore("#e6eef5", "#ffffff"),
    "res_coal": ore("#3a3a42"), "res_mithril_fragment": ore("#6ae0f0", "#ffffff"),
    "res_greenleaf": herb("#5fbf4a"), "res_bitterroot": herb("#8a6a3a"), "res_moonflower": herb("#4a8a6a", "#c0d8ff"),
    "res_redthorn": herb("#4a7a3a", "#e04a4a"), "res_spirit_bloom": herb("#3a8a8a", "#7affe0"),
    "res_light_hide": hide("#d8b07a"), "res_raw_leather": leather("#a86a3a"), "res_thick_hide": hide("#8a5a3a"),
    "res_tough_leather": leather("#6a3a2a"), "res_pristine_hide": hide("#f0e0c0"),
    "res_rough_cloth": cloth("#b8a07a"), "res_linen_cloth": cloth("#e8e0c8"), "res_fine_cloth": cloth("#8a7ae0"),
    "res_boss_core": lambda d: (d.ellipse([1, 1, 14, 14], fill=(120, 20, 30)), d.ellipse([3, 3, 12, 12], fill=(230, 60, 40)),
                                d.ellipse([5, 5, 10, 10], fill=(255, 200, 80)), d.point((6, 6), fill=(255, 255, 255))),
    "res_enchanted_thread": lambda d: (d.rectangle([3, 2, 12, 3], fill=(140, 100, 60)), d.rectangle([3, 12, 12, 13], fill=(140, 100, 60)),
                                       d.rectangle([4, 4, 11, 11], fill=(180, 110, 255)), d.line([(4, 6), (11, 6)], fill=(230, 200, 255)),
                                       d.line([(4, 9), (11, 9)], fill=(230, 200, 255)), d.point((13, 1), fill=(255, 255, 200))),
    "res_minor_strength_potion": potion("#e04a3a"), "res_minor_recovery_potion": potion("#3ac06a"),
    "res_gatherers_tonic": potion("#e0c03a"), "res_greater_strength_potion": potion("#b02a6a"),
    "prof_mining": lambda d: (d.line([(3, 14), (11, 6)], fill=(140, 100, 60), width=2),
                              d.arc([3, 1, 15, 13], 200, 340, fill=(190, 200, 210), width=3)),
    "prof_herbalism": lambda d: (d.arc([2, 2, 14, 14], 180, 360, fill=(200, 210, 220), width=2), d.line([(8, 8), (8, 15)], fill=(140, 100, 60), width=2),
                                 d.ellipse([9, 9, 14, 13], fill=(95, 191, 74))),
    "prof_skinning": lambda d: (d.polygon([(2, 12), (12, 2), (14, 4), (5, 13)], fill=(210, 215, 225)), d.rectangle([1, 12, 4, 15], fill=(140, 100, 60))),
    "prof_blacksmithing": lambda d: (d.polygon([(1, 5), (14, 5), (12, 8), (10, 8), (10, 12), (13, 14), (3, 14), (6, 12), (6, 8), (3, 8)], fill=(110, 115, 130)),
                                     d.rectangle([1, 5, 14, 6], fill=(170, 175, 190))),
    "prof_tailoring": lambda d: (d.line([(2, 14), (13, 2)], fill=(210, 215, 225), width=1), d.ellipse([11, 1, 14, 4], outline=(210, 215, 225)),
                                 d.arc([1, 3, 12, 15], 30, 300, fill=(230, 80, 80), width=1)),
    "prof_alchemy": potion("#4ab0e0"),
    "nav_crafts": lambda d: (d.polygon([(1, 7), (14, 7), (12, 10), (10, 10), (10, 13), (13, 15), (3, 15), (6, 13), (6, 10), (3, 10)], fill=(110, 115, 130)),
                             d.line([(4, 5), (12, 0)], fill=(140, 100, 60), width=2), d.rectangle([9, 0, 14, 3], fill=(190, 200, 210))),
    "hourglass": lambda d: (d.rectangle([3, 1, 12, 2], fill=(140, 100, 60)), d.rectangle([3, 13, 12, 14], fill=(140, 100, 60)),
                            d.polygon([(4, 3), (11, 3), (8, 8)], fill=(230, 230, 240)), d.polygon([(8, 8), (4, 12), (11, 12)], fill=(230, 230, 240)),
                            d.polygon([(6, 10), (9, 10), (10, 12), (5, 12)], fill=(240, 200, 80))),
    "item_head": lambda d: (d.ellipse([3, 2, 12, 11], fill=(190, 200, 210)), d.rectangle([3, 7, 12, 12], fill=(190, 200, 210)),
                            d.rectangle([5, 7, 10, 9], fill=(40, 40, 50)), d.rectangle([7, 9, 8, 12], fill=(150, 160, 170))),
    "item_hands": lambda d: (d.rectangle([4, 7, 11, 14], fill=(170, 130, 90)), d.rectangle([4, 2, 5, 7], fill=(170, 130, 90)),
                             d.rectangle([6, 1, 7, 7], fill=(170, 130, 90)), d.rectangle([8, 1, 9, 7], fill=(170, 130, 90)),
                             d.rectangle([10, 3, 11, 7], fill=(170, 130, 90)), d.rectangle([12, 7, 14, 9], fill=(170, 130, 90)),
                             d.rectangle([4, 12, 11, 14], fill=(130, 95, 60))),
    "item_legs": lambda d: (d.rectangle([4, 1, 11, 4], fill=(110, 120, 150)), d.rectangle([4, 4, 7, 15], fill=(110, 120, 150)),
                            d.rectangle([8, 4, 11, 15], fill=(95, 105, 135))),
    "item_feet": lambda d: (d.rectangle([4, 2, 9, 11], fill=(130, 90, 55)), d.rectangle([4, 10, 14, 14], fill=(130, 90, 55)),
                            d.rectangle([4, 13, 14, 14], fill=(80, 55, 35))),
})


def greatsword(d):
    d.line([(4, 12), (14, 2)], fill=C["steel"], width=3)
    d.point((14, 1), fill=C["white"])
    d.line([(2, 8), (8, 14)], fill=C["gold"], width=2)
    d.line([(0, 15), (3, 12)], fill=C["wood"], width=2)


def shield(d, col="blue"):
    d.polygon([(2, 2), (13, 2), (13, 8), (8, 14), (2, 8)], fill=C[col])
    d.polygon([(4, 4), (11, 4), (11, 8), (8, 11), (4, 8)], fill=C[col + "_d"])
    d.rectangle([7, 3, 8, 12], fill=C["gold"])


def staff(d):
    d.line([(3, 14), (11, 5)], fill=C["wood"], width=2)
    d.ellipse([9, 1, 15, 7], fill=C["purple"])
    d.ellipse([11, 3, 13, 5], fill=C["cyan"])


def bow(d):
    d.arc([1, 1, 15, 15], 225, 405, fill=C["wood"], width=2)
    d.line([(3, 3), (13, 13)], fill=C["white"], width=1)


ICONS.update({
    "str": lambda d: (d.rectangle([2, 7, 13, 12], fill=C["skin"]), d.ellipse([9, 2, 15, 9], fill=C["skin"]),
                      d.rectangle([2, 11, 6, 14], fill=C["red"])),
    "agi": lambda d: (d.polygon([(1, 13), (9, 5), (11, 7)], fill=C["green"]), d.polygon([(9, 1), (15, 1), (15, 7)], fill=C["green"]),
                      d.line([(4, 8), (8, 4)], fill=C["white"])),
    "w_sword": lambda d: sword(d),
    "w_greatsword": greatsword,
    "w_shield": lambda d: shield(d),
    "w_staff": staff,
    "w_bow": bow,
    "item_offhand": lambda d: shield(d, "blue"),
    "sp_twin_strike": lambda d: (d.line([(1, 12), (9, 4)], fill=C["steel"], width=2), d.line([(6, 14), (14, 6)], fill=C["steel"], width=2),
                                 d.point((10, 3), fill=C["white"]), d.point((15, 5), fill=C["white"])),
    "sp_mortal_strike": lambda d: (greatsword(d), d.arc([0, 0, 15, 15], 300, 30, fill=C["red"], width=2)),
    "sp_whirlwind": lambda d: (d.arc([1, 1, 14, 14], 0, 300, fill=C["white"], width=2), d.arc([5, 5, 10, 10], 90, 360, fill=C["steel"], width=1),
                               d.polygon([(13, 2), (15, 6), (11, 5)], fill=C["white"])),
    "sp_shield_slam": lambda d: (shield(d, "blue"), d.polygon([(11, 0), (15, 2), (13, 5)], fill=C["yellow"]),
                                 d.polygon([(0, 11), (3, 15), (1, 15)], fill=C["yellow"])),
    "sp_shield_wall": lambda d: (d.rectangle([1, 3, 6, 13], fill=C["blue"]), d.rectangle([9, 3, 14, 13], fill=C["blue"]),
                                 d.rectangle([5, 2, 10, 14], fill=C["blue_d"]), d.rectangle([7, 4, 8, 12], fill=C["gold"])),
    "sp_aimed_shot": lambda d: (bow(d), d.ellipse([9, 9, 15, 15], outline=C["red"], width=1), d.point((12, 12), fill=C["red"])),
    "sp_arrow_rain": lambda d: tuple(d.line([(x, y), (x - 3, y + 6)], fill=C["steel"], width=1) for x, y in ((5, 1), (10, 2), (15, 1), (8, 7), (13, 8))),
    "sp_arcane_bolt": lambda d: (d.polygon([(1, 14), (10, 4), (12, 6)], fill=C["purple"]), d.ellipse([9, 1, 15, 7], fill=C["cyan"]),
                                 d.point((12, 4), fill=C["white"])),
})


ICONS.update({
    "recipe": lambda d: (d.rectangle([3, 2, 12, 13], fill=(236, 220, 170)), d.rectangle([2, 1, 13, 3], fill=(200, 170, 110)),
                         d.rectangle([2, 12, 13, 14], fill=(200, 170, 110)), d.line([(5, 6), (10, 6)], fill=(120, 90, 60)),
                         d.line([(5, 9), (10, 9)], fill=(120, 90, 60))),
    "mod_armored": lambda d: (d.polygon([(2, 2), (13, 2), (13, 8), (8, 14), (2, 8)], fill=C["steel_d"]), d.rectangle([7, 3, 8, 12], fill=C["steel"])),
    "mod_swift": lambda d: (d.polygon([(1, 4), (8, 8), (1, 12)], fill=C["yellow"]), d.polygon([(7, 4), (14, 8), (7, 12)], fill=C["yellow"])),
    "mod_shielded": lambda d: (d.ellipse([1, 1, 14, 14], outline=C["blue"], width=2), d.ellipse([5, 5, 10, 10], fill=C["blue"])),
    "mod_regen": lambda d: (d.rectangle([6, 2, 9, 13], fill=C["green_d"]), d.rectangle([2, 6, 13, 9], fill=C["green_d"]),
                            d.arc([0, 0, 15, 15], 200, 340, fill=C["green"], width=1)),
    "mod_brutal": lambda d: (d.polygon([(8, 1), (14, 8), (8, 15), (2, 8)], fill=C["red"]), d.polygon([(8, 4), (11, 8), (8, 12), (5, 8)], fill=C["red_d"])),
    "mod_vital": lambda d: (d.ellipse([1, 3, 8, 10], fill=C["red_d"]), d.ellipse([7, 3, 14, 10], fill=C["red_d"]),
                            d.polygon([(1, 7), (14, 7), (8, 14)], fill=C["red_d"]), d.rectangle([7, 4, 8, 10], fill=C["white"])),
})


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in ICONS.items():
        icon(fn).save(OUT / f"{name}.png")
    names = list(ICONS)
    sheet = Image.new("RGBA", (len(names) * 52, 60), (40, 44, 54, 255))
    for i, n in enumerate(names):
        im = Image.open(OUT / f"{n}.png").resize((48, 48), Image.NEAREST)
        sheet.alpha_composite(im, (i * 52 + 2, 6))
    sheet.save(ROOT / "tools" / "icon_sheet_preview.png")
    print("generated", len(names), "icons")


if __name__ == "__main__":
    main()
