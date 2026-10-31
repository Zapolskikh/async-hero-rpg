#!/usr/bin/env python3
"""Checks drawn gear against spec/looks.json.

    python tools/check_gear.py output [--pilot]
"""
import json
import sys
from pathlib import Path

from PIL import Image

BRIEF = Path(__file__).resolve().parents[1]
COVERAGE = .9   # Share of the body template a part has to cover.


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    output = Path(args[0] if args else 'output')
    pilot = '--pilot' in sys.argv
    looks = json.loads((BRIEF / 'spec/looks.json').read_text(encoding='utf8'))['looks']
    errors, checked = [], 0
    for look in looks:
        if pilot and not look.get('pilot'):
            continue
        for entry in look['files']:
            checked += 1
            path = output / entry['path']
            if not path.exists():
                errors.append('missing: %s' % entry['path'])
                continue
            im = Image.open(path)
            if im.mode != 'RGBA':
                errors.append('not RGBA: %s' % entry['path'])
                im = im.convert('RGBA')
            if list(im.size) != entry['size']:
                errors.append('size %s, must be %s: %s' % (im.size, entry['size'], entry['path']))
                continue
            alpha = im.getchannel('A')
            if alpha.getbbox() is None:
                errors.append('empty: %s' % entry['path'])
                continue
            if alpha.getextrema()[0] != 0:
                errors.append('no transparent background: %s' % entry['path'])
            template = entry.get('template')
            if template:
                shape = Image.open(BRIEF / template).convert('RGBA').getchannel('A')
                need = sum(1 for v in shape.tobytes() if v > 128)
                got = sum(1 for a, b in zip(shape.tobytes(), alpha.tobytes()) if a > 128 and b > 128)
                if need and got / need < COVERAGE:
                    errors.append('covers %d%% of the body part: %s' % (100 * got / need, entry['path']))
    for line in errors[:200]:
        print(line)
    print('%d files checked, %d problems' % (checked, len(errors)))
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
