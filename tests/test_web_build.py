import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('prepare_web_build', Path(__file__).resolve().parents[1] / 'tools/prepare_web_build.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
SHA = '1234567890abcdef1234567890abcdef12345678'


class WebBuildTest(unittest.TestCase):
    def fixture(self, root):
        stem = 'game-1234567890ab'
        (root / (stem + '.html')).write_text('<html><head></head><script>"serviceWorker":"' + stem + '.service.worker.js"</script></html>')
        for suffix in ('.js', '.pck', '.wasm'):
            (root / (stem + suffix)).write_bytes(b'resource')
        (root / (stem + '.manifest.json')).write_text(json.dumps({'start_url': stem + '.html'}))
        (root / (stem + '.service.worker.js')).write_text("const CACHE_VERSION = 'old';\nconst CACHED_FILES = [\"" + stem + '.html"];')
        return stem

    def test_versioned_export(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stem = self.fixture(root)
            MODULE.prepare(root, stem + '.html', SHA)
            html = (root / 'index.html').read_text()
            self.assertIn(SHA, html)
            self.assertIn('index.service.worker.js', html)
            self.assertIn('update.js?v=' + SHA, html)
            worker = (root / 'index.service.worker.js').read_text()
            self.assertIn("const CACHE_VERSION = '" + SHA, worker)
            self.assertIn('"index.html"', worker)
            self.assertIn('self.skipWaiting()', worker)
            self.assertIn('self.clients.claim()', worker)
            self.assertEqual(json.loads((root / 'version.json').read_text())['commit'], SHA)
            self.assertEqual(json.loads((root / (stem + '.manifest.json')).read_text())['start_url'], './index.html')
            self.assertTrue((root / (stem + '.pck')).exists())
            self.assertTrue((root / 'update.js').exists())
            self.assertTrue((root / '.nojekyll').exists())
            self.assertFalse((root / (stem + '.service.worker.js')).exists())
            self.assertNotIn('indexedDB.deleteDatabase', (root / 'update.js').read_text())

    def test_incomplete_export_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                MODULE.prepare(Path(directory), 'game.html', SHA)

    def test_invalid_revision_or_entry_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                MODULE.prepare(Path(directory), 'game.html', '<script>')
            with self.assertRaises(ValueError):
                MODULE.prepare(Path(directory), '../game.html', SHA)


if __name__ == '__main__':
    unittest.main()
