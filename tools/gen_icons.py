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
