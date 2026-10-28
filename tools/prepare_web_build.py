"""Prepare a Godot Web export for Pages without reusing previous asset URLs."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil


def prepare(output: Path, entry: str, commit: str) -> dict:
    if not re.fullmatch(r'[0-9a-f]{7,40}', commit):
        raise ValueError('Expected a Git commit SHA.')
    if Path(entry).name != entry or not entry.endswith('.html'):
        raise ValueError('The HTML entry must be a filename within the export directory.')
    html_path = output / entry
    stem = html_path.stem
    for suffix in ('.html', '.js', '.pck', '.wasm', '.service.worker.js', '.manifest.json'):
        if not (output / (stem + suffix)).is_file():
            raise ValueError(f'Missing exported resource: {stem + suffix}')

    html = html_path.read_text(encoding='utf-8')
    html = html.replace(stem + '.service.worker.js', 'index.service.worker.js')
    marker = f'<meta name="game-build" content="{commit}">'
    html = html.replace('</head>', f'{marker}\n<script defer src="update.js?v={commit}"></script>\n</head>', 1)
    (output / 'index.html').write_text(html, encoding='utf-8')

    worker_path = output / (stem + '.service.worker.js')
    worker = worker_path.read_text(encoding='utf-8')
    worker, count = re.subn(r"const CACHE_VERSION = '[^']+';", f"const CACHE_VERSION = '{commit}';", worker, count=1)
    if count != 1:
        raise ValueError('Unexpected Godot service worker template.')
    # Cache the public entry point, retaining Godot's offline fallback behavior.
    worker = worker.replace(json.dumps(entry), '"index.html"')
    # Replace an old worker promptly; never clear IndexedDB/local game saves.
    worker += "\nself.addEventListener('install', (event) => event.waitUntil(self.skipWaiting()));\n"
    worker += "self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));\n"
    (output / 'index.service.worker.js').write_text(worker, encoding='utf-8')
    worker_path.unlink()

    manifest_path = output / (stem + '.manifest.json')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest['start_url'] = './index.html'
    manifest['scope'] = './'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False), encoding='utf-8')
    # Keep the versioned HTML as well, in case a browser bookmarked that URL.
    html_path.write_text(html, encoding='utf-8')
    shutil.copyfile(Path(__file__).resolve().parents[1] / 'web' / 'update.js', output / 'update.js')
    (output / '.nojekyll').touch()
    metadata = {'commit': commit, 'short_commit': commit[:12], 'built_at': datetime.now(timezone.utc).isoformat(), 'entry': entry}
    (output / 'version.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--entry', required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.output, args.entry, args.commit)))
