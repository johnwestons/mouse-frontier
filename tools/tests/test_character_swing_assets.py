"""Reviewed swing coverage, gripping hands, and mobile cell geometry."""
import hashlib
import json
import sys
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.build_mobile_package import image_bounds
from tools.character_action_contract import action_contract


class SwingAssetTests(unittest.TestCase):
    def test_complete_roster_has_unique_reviewed_frames_and_solid_grips(self):
        accepted = json.loads((ROOT / 'character-motion/swings/acceptance.json').read_text())['characters']
        assets = ROOT / 'assets/sprites/character-animations'
        self.assertEqual(set(accepted), {p.name for p in assets.iterdir() if p.is_dir()})
        self.assertEqual(len(accepted), 55)
        for slug, record in accepted.items():
            with self.subTest(character=slug):
                path = assets / slug / 'swing.png'
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), record['sha256'])
                self.assertEqual(record['audit']['errors'], 0)
                self.assertEqual(len(record['hands']), 6)
                with Image.open(path) as image:
                    self.assertEqual(image.size, (3072, 256))
                    self.assertEqual(image.mode, 'RGBA')
                    frames = [image.crop((i * 512, 0, (i + 1) * 512, 256)) for i in range(6)]
                self.assertEqual(len({hashlib.sha256(f.tobytes()).digest() for f in frames}), 6)
                for frame, hand in zip(frames, record['hands']):
                    self.assertGreater(frame.getpixel((round(hand['x'] * 512), round(hand['y'] * 256)))[3], 200)
                    box = frame.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
                    self.assertTrue(box[0] >= 2 and box[1] >= 2 and box[2] <= 510 and box[3] <= 254)
                old = json.loads((ROOT / 'character-motion/actions/acceptance.json').read_text())['characters'][slug]
                self.assertEqual(hashlib.sha256((assets / slug / 'melee.png').read_bytes()).hexdigest(), old['actions']['melee']['sha256'])

    def test_mobile_keeps_six_wide_cells_and_normalized_grips(self):
        accepted = json.loads((ROOT / 'character-motion/swings/acceptance.json').read_text())['characters']
        for slug in accepted:
            contract = action_contract(ROOT, slug, 'swing')
            self.assertEqual(contract['frame_count'], 6)
            self.assertEqual(len(contract['hands']), 6)
            for size in (128, 192):
                self.assertEqual(image_bounds(f'assets/sprites/character-animations/{slug}/swing.png',
                    {'characterAnimationFrameSize': size}, (3072, 256)), (12 * size, size))


if __name__ == '__main__':
    unittest.main()
