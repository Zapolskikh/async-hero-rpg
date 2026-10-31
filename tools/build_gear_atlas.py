#!/usr/bin/env python3
"""Packs drawn gear into the game: one texture per look and body, plus an index.

    python tools/build_gear_atlas.py async_hero_gear_pilot_v2.zip [more.zip ...]

The zips hold output/<look>/<male|female>/<part>.png and output/<look>/weapon.png, see
tools/art_brief/PROMPT.md. Looks from several zips add up. Writes assets/gear/*.png
with mipmaps set on import, like the rig atlas, and assets/gear/gear_index.json:
look -> body ("any" for weapons) -> {file, parts: {part: [x, y, w, h]}}.
"""
import io
import json
import re
import sys
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/gear'
ROW = 512      # Width of a texture; parts wrap to the next row.
PAD = 2        # Keeps neighbouring parts from bleeding at small scales.


def pack(parts):
    placed, x, y, row = {}, PAD, PAD, 0
    for name, im in sorted(parts.items(), key=lambda kv: -kv[1].height):
        if x + im.width + PAD > max(ROW, im.width + 2 * PAD):
            x, y, row = PAD, y + row + PAD, 0
        placed[name] = [x, y, im.width, im.height]
        x += im.width + PAD
        row = max(row, im.height)
    width = max(p[0] + p[2] for p in placed.values()) + PAD
    sheet = Image.new('RGBA', (width, y + row + PAD), (0, 0, 0, 0))
    for name, box in placed.items():
        sheet.paste(parts[name], (box[0], box[1]))
    return sheet, placed


def main():
    index_path = OUT / 'gear_index.json'
    index = json.loads(index_path.read_text(encoding='utf8')) if index_path.exists() else {}
    OUT.mkdir(parents=True, exist_ok=True)
    groups = {}
    for name in sys.argv[1:]:
        z = zipfile.ZipFile(name)
        for path in z.namelist():
            m = re.search(r'output/([^/]+)/(?:(male|female)/)?([a-z_]+)\.png$', path)
            if m:
                im = Image.open(io.BytesIO(z.read(path))).convert('RGBA')
                groups.setdefault((m.group(1), m.group(2) or 'any'), {})[m.group(3)] = im
    for (look, body), parts in sorted(groups.items()):
        sheet, placed = pack(parts)
        file = look if body == 'any' else '%s_%s' % (look, body)
        sheet.save(OUT / (file + '.png'), optimize=True)
        index.setdefault(look, {})[body] = dict(file=file, parts=placed)
        settings = OUT / (file + '.png.import')
        if not settings.exists():
            settings.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\nmipmaps/generate=true\n', encoding='utf8')
    index_path.write_text(json.dumps(index, separators=(',', ':'), sort_keys=True) + '\n', encoding='utf8')
    print('packed %d textures, %d looks in the index' % (len(groups), len(index)))


if __name__ == '__main__':
    main()
