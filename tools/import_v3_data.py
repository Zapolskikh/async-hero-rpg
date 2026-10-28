"""Copy the supplied V3 poses verbatim; gzip only changes transport size, never geometry."""
from pathlib import Path
from zipfile import ZipFile
import argparse
import gzip
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', nargs='?', default=str(ROOT / 'async_hero_animation_v3.zip'))
    args = parser.parse_args()
    dest = ROOT / 'assets/characters/v3'
    dest.mkdir(parents=True, exist_ok=True)
    manifest = {'source': 'async_hero_animation_v3.zip', 'profiles': {}}
    with ZipFile(args.archive) as archive:
        for sex in ('male', 'female'):
            data = archive.read(f'async_hero_animation_v3/godot/assets/animations_{sex}.json')
            assert len(json.loads(data)) == 47
            packed = gzip.compress(data, compresslevel=9, mtime=0)
            (dest / f'animations_{sex}.json.gz').write_bytes(packed)
            (dest / f'head_{sex}.png').write_bytes(archive.read(f'async_hero_animation_v3/godot/assets/head_{sex}.png'))
            manifest['profiles'][sex] = {'clips': 47, 'sha256_uncompressed': hashlib.sha256(data).hexdigest(),
                                        'source_bytes': len(data), 'gzip_bytes': len(packed)}
    (dest / 'source_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
