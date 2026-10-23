"""Generates the layered hero ("paper doll") sprites.

    python3 tools/gen_doll.py

Writes assets/units/doll_<layer>.png, all in the same 34x42 frame as the other
unit sprites, facing right. The game draws doll_body first and then one layer
per equipped item (Roster.look). Item layers are drawn in light greys so the
game can tint them by rarity; weapon layers keep their own colours.
Replace any PNG with real art of the same size and name.
"""
from pathlib import Path
from PIL import Image

from gen_sprites import Canvas, hexc, shade, SKIN, GOLD, WOOD

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "units"

W1, W2, W3 = (250, 250, 250), (205, 205, 210), (155, 155, 165)   # tintable greys
BLADE = (220, 226, 236)
BLADE_D = (170, 178, 190)


def layer(draw):
    c = Canvas(32, 40)
    draw(c)
    img = c.image()
    out = Image.new("RGBA", (34, 42), (0, 0, 0, 0))
    out.paste(img, (1, 1))
    return out


def body(c):
    tunic = hexc("#3f7fd6")
    pants = hexc("#3a3550")
    cape = hexc("#c23b3b")
    hair = hexc("#7a4a22")
    c.rect(8, 20, 2, 15, cape)                       # cape behind
    c.rect(9, 21, 2, 8, shade(tunic, 0.7))           # back arm
    c.rect(9, 29, 2, 2, shade(SKIN, 0.85))
    c.rect(12, 31, 3, 7, pants)                      # legs
    c.rect(17, 31, 3, 7, shade(pants, 0.85))
    c.rect(12, 37, 4, 3, (60, 44, 36))               # plain shoes
    c.rect(17, 37, 4, 3, (52, 38, 30))
    c.rect(11, 20, 10, 11, tunic)                    # torso
    c.rect(11, 26, 10, 5, shade(tunic, 0.85))
    c.rect(11, 28, 10, 1, (70, 50, 34))
    c.rect(12, 10, 8, 10, SKIN)                      # head
    c.rect(12, 18, 8, 2, shade(SKIN, 0.9))
    c.dot(18, 13, (30, 24, 30))
    c.dot(18, 14, (30, 24, 30))
    c.rect(11, 8, 9, 3, hair)
    c.rect(11, 11, 2, 5, hair)
    c.rect(21, 21, 2, 7, shade(tunic, 1.05))         # front arm
    c.rect(21, 28, 2, 2, SKIN)


def legs(c):
    c.rect(11, 29, 10, 2, W2)                        # waist
    c.rect(12, 31, 3, 6, W1)
    c.rect(17, 31, 3, 6, W2)
    c.rect(12, 33, 3, 1, W3)                         # knee plates
    c.rect(17, 33, 3, 1, W3)


def feet(c):
    c.rect(12, 35, 4, 5, W1)
    c.rect(17, 35, 4, 5, W2)
    c.rect(12, 35, 4, 1, W3)
    c.rect(17, 35, 4, 1, W3)
    c.rect(15, 39, 1, 1, W3)
    c.rect(20, 39, 1, 1, W3)


def armor(c):
    c.rect(11, 20, 10, 9, W1)                        # breastplate
    c.rect(11, 25, 10, 4, W2)
    c.rect(15, 21, 2, 6, W3)                         # centre ridge
    c.rect(10, 19, 3, 3, W2)                         # shoulder pads
    c.rect(19, 19, 4, 3, W2)
    c.rect(9, 22, 2, 5, W3)                          # sleeves
    c.rect(21, 22, 2, 4, W1)


def trinket(c):
    c.dot(13, 20, W2)
    c.dot(14, 21, W2)
    c.dot(18, 20, W2)
    c.dot(17, 21, W2)
    c.rect(15, 22, 2, 2, W1)


def head(c):
    c.rect(11, 7, 10, 6, W1)                         # helmet
    c.rect(11, 7, 10, 1, W2)
    c.rect(11, 12, 2, 6, W2)                         # cheek guard
    c.rect(19, 12, 2, 2, W2)
    c.rect(15, 5, 2, 2, W3)                          # crest


def hands(c):
    c.rect(9, 28, 2, 3, W2)
    c.rect(21, 27, 2, 3, W1)
    c.rect(21, 27, 2, 1, W3)


def w_sword(c):
    x = 23
    c.rect(x, 13, 2, 15, BLADE)
    c.rect(x + 1, 13, 1, 15, BLADE_D)
    c.rect(x - 1, 27, 4, 1, GOLD)
    c.rect(x, 28, 2, 3, WOOD)


def w_greatsword(c):
    x = 23
    c.rect(x, 3, 3, 24, BLADE)
    c.rect(x + 2, 3, 1, 24, BLADE_D)
    c.dot(x + 1, 2, BLADE)
    c.rect(x - 2, 27, 7, 1, GOLD)
    c.rect(x, 28, 3, 4, WOOD)
    c.dot(x + 1, 32, GOLD)


def w_staff(c):
    x = 23
    c.rect(x, 6, 2, 33, WOOD)
    c.rect(x - 1, 2, 4, 4, (127, 208, 255))
    c.dot(x, 3, (255, 255, 255))
    c.rect(x - 1, 6, 4, 1, GOLD)


def w_bow(c):
    x = 23
    for i, y in enumerate(range(13, 37)):
        off = 3 - abs(i - 12) // 4
        c.dot(x + off, y, WOOD)
    c.line_v(x - 1, 14, 35, (230, 230, 230))
    c.rect(x + 2, 24, 2, 3, (90, 60, 40))


def shield(c):
    c.rect(19, 20, 7, 11, W1)
    c.rect(19, 20, 7, 1, W3)
    c.rect(19, 30, 7, 1, W3)
    c.rect(21, 23, 3, 5, W2)
    c.dot(22, 25, W3)


def offhand_sword(c):
    x = 7
    c.rect(x, 15, 2, 14, BLADE_D)
    c.rect(x - 1, 28, 4, 1, GOLD)
    c.rect(x, 29, 2, 2, WOOD)


LAYERS = {
    "body": body, "legs": legs, "feet": feet, "armor": armor, "trinket": trinket, "head": head,
    "hands": hands, "w_sword": w_sword, "w_greatsword": w_greatsword, "w_staff": w_staff,
    "w_bow": w_bow, "shield": shield, "offhand_sword": offhand_sword,
}

# Same tints as Roster.LOOK_TINTS (by rarity), used only for the preview sheet.
TINTS = ["#8f96a3", "#5b9be8", "#b06ef0", "#f0aa40"]


def tinted(img, hex_col):
    r, g, b = hexc(hex_col)
    px = img.load()
    out = img.copy()
    op = out.load()
    for y in range(img.height):
        for x in range(img.width):
            pr, pg, pb, pa = px[x, y]
            if pa:
                op[x, y] = (pr * r // 255, pg * g // 255, pb * b // 255, pa)
    return out


def compose(layers):
    img = Image.new("RGBA", (34, 42), (0, 0, 0, 0))
    for name, col in layers:
        part = Image.open(OUT / f"doll_{name}.png")
        img.alpha_composite(tinted(part, col) if col else part)
    return img


def glow_mask(img):
    """White silhouette of a layer grown by 1 px: tinted by the game for the glow cosmetic."""
    a = img.split()[3]
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    src = a.load()
    op = out.load()
    for y in range(img.height):
        for x in range(img.width):
            hit = False
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < img.width and 0 <= yy < img.height and src[xx, yy] > 0:
                        hit = True
            if hit:
                op[x, y] = (255, 255, 255, 255 if src[x, y] == 0 else 140)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in LAYERS.items():
        img = layer(fn)
        img.save(OUT / f"doll_{name}.png")
        if name != "body":
            glow_mask(img).save(OUT / f"doll_{name}_glow.png")
    looks = [
        [("body", "")],
        [("body", ""), ("w_sword", "")],
        [("offhand_sword", ""), ("body", ""), ("legs", TINTS[0]), ("feet", TINTS[0]), ("armor", TINTS[0]), ("w_sword", "")],
        [("body", ""), ("legs", TINTS[1]), ("feet", TINTS[1]), ("armor", TINTS[1]), ("head", TINTS[1]), ("hands", TINTS[1]),
         ("w_sword", ""), ("shield", TINTS[1])],
        [("body", ""), ("legs", TINTS[2]), ("armor", TINTS[2]), ("trinket", TINTS[3]), ("head", TINTS[2]), ("w_greatsword", "")],
        [("body", ""), ("feet", TINTS[3]), ("armor", TINTS[3]), ("head", TINTS[3]), ("hands", TINTS[3]), ("w_staff", "")],
        [("body", ""), ("legs", TINTS[0]), ("armor", TINTS[1]), ("feet", TINTS[2]), ("w_bow", "")],
    ]
    sheet = Image.new("RGBA", (len(looks) * 116, 140), (40, 44, 54, 255))
    for i, lk in enumerate(looks):
        im = compose(lk).resize((102, 126), Image.NEAREST)
        sheet.alpha_composite(im, (i * 116 + 7, 7))
    sheet.save(ROOT / "tools" / "doll_preview.png")
    print("generated", len(LAYERS), "doll layers")


if __name__ == "__main__":
    main()
