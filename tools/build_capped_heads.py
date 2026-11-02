"""Heads worn under headwear: hair cut at the brim line and no ponytail.

    python tools/build_capped_heads.py

Reads assets/characters/rig/head_<sex>.png and writes head_<sex>_capped.png.
Everything above the brim line is removed (the headwear covers it), so hair no
longer sticks out around hats and hoods; the short hair below the brim stays as
the hair under the hat. The female ponytail is cut off and its cut edge gets a
fresh outline. Looks in CharacterRig.FULL_HAIR (circlets) keep the full head.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RIG = Path(__file__).resolve().parent.parent / 'assets' / 'characters' / 'rig'
INK = (24, 22, 30)
OUTLINE = 7
# Brim line: the lowest edge every cap, hat and hood reaches at the back of the head.
BRIM = {'male': 90, 'female': 115}
# Ponytail cut: polygon removed below the back of the skull.
PONYTAIL = {'female': [(0, 150), (128, 150), (148, 162), (149, 288), (0, 288)]}


def capped(sex):
    head = Image.open(RIG / f'head_{sex}.png').convert('RGBA')
    a = np.array(head)
    h, w = a.shape[:2]
    cut = np.zeros((h, w), bool)
    cut[:BRIM[sex], :] = True
    pony = np.zeros((h, w), bool)
    if sex in PONYTAIL:
        img = Image.new('L', (w, h), 0)
        ImageDraw.Draw(img).polygon(PONYTAIL[sex], fill=255)
        pony = np.array(img) > 0
    a[cut | pony] = 0
    if pony.any():
        kept = a[..., 3] > 0
        near = np.array(Image.fromarray(pony.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(OUTLINE * 2 + 1))) > 0
        edge = kept & near & ~cut
        a[edge, :3] = INK
        a[edge, 3] = 255
    Image.fromarray(a).save(RIG / f'head_{sex}_capped.png', optimize=True)


if __name__ == '__main__':
    for sex in ('male', 'female'):
        capped(sex)
