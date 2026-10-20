"""Verify the shipped roster has real, reviewed action frames and preserved chores."""
from pathlib import Path
import hashlib
import json
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/sprites/character-animations'
SPECS = ROOT / 'character-motion/actions'
ACTIONS = {'sit', 'lay', 'melee', 'ranged', 'use', 'hit', 'death', 'unconscious'}
STATIC_IDLES = {'cowboy-mouse-no-skull', 'cowboy-mouse-on-skull', 'raccoon-cape',
                'raccoon-heart', 'red-hood-mouse', 'shield-mouse', 'vampire-mouse'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class CharacterActionAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.accepted = json.loads((SPECS / 'acceptance.json').read_text())['characters']

    def test_every_character_has_all_reviewed_actions_and_static_idles_are_animated(self):
        roster = {path.name for path in ASSETS.iterdir() if path.is_dir()}
        self.assertEqual(set(self.accepted), roster)
        self.assertEqual(len(roster), 55)
        for slug, record in self.accepted.items():
            with self.subTest(character=slug):
                self.assertEqual(record['status'], 'reviewed_and_installed')
                self.assertEqual(record['audit']['errors'], 0)
                self.assertEqual(set(record['actions']), ACTIONS | ({'idle'} if slug in STATIC_IDLES else set()))
                self.assertEqual(digest(SPECS / f'{slug}.json'), record['evidence']['spec']['sha256'])

    def test_installed_strips_match_review_and_have_six_distinct_complete_frames(self):
        for slug, record in self.accepted.items():
            for action, definition in record['actions'].items():
                with self.subTest(character=slug, action=action):
                    path = ASSETS / slug / f'{action}.png'
                    self.assertEqual(digest(path), definition['sha256'])
                    with Image.open(path) as image:
                        self.assertEqual(image.mode, 'RGBA')
                        self.assertEqual(image.size, (3072, 256))
                        frames = [image.crop((index * 512, 0, (index + 1) * 512, 256)) for index in range(6)]
                    self.assertEqual(len({hashlib.sha256(frame.tobytes()).digest() for frame in frames}), 6)
                    for frame in frames:
                        alpha = frame.getchannel('A')
                        box = alpha.point(lambda value: 255 if value > 16 else 0).getbbox()
                        self.assertIsNotNone(box)
                        self.assertGreaterEqual(box[0], 2)
                        self.assertGreaterEqual(box[1], 2)
                        self.assertLessEqual(box[2], 510)
                        self.assertLessEqual(box[3], 254)
                    if action in {'melee', 'ranged'}:
                        points = record['hands'][action]
                        self.assertEqual(len(points), 6)
                        for point in points:
                            self.assertTrue(0 < point['x'] < 1 and 0 < point['y'] < 1)

    def test_action_upgrade_preserves_all_reviewed_chore_art(self):
        chores = json.loads((ROOT / 'character-motion/chores/acceptance.json').read_text())['characters']
        for slug, record in chores.items():
            for action, definition in record['actions'].items():
                with self.subTest(character=slug, action=action):
                    self.assertEqual(digest(ROOT / definition['path']), definition['sha256'])


if __name__ == '__main__':
    unittest.main()
