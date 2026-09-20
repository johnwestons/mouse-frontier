import copy
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageDraw
from tools.character_gait_contract import RUN_PHASES, run_ground_clearance, locomotion_sources
from tools.build_directional_character_assets import normalize_strip, visible_bbox
from tools.sprite_motion_audit import audit_animation, validate_gait, CANONICAL_DIRECTIONS
from tools.character_sprite_doctor import SpriteDoctor, RUN_ACTION_SPECS
from tools.character_motion_acceptance_gate import expected_review_artifacts, _validate_clean_reports


class RunContractTests(unittest.TestCase):
    def test_clearance_is_bounded_planted_symmetric_and_integer(self):
        valid = [0, 0, 8, 6, 0, 0, 8, 6]
        self.assertEqual(run_ground_clearance(valid), valid)
        for bad in (None, [], [0] * 8, [0, 0, 80, 6] * 2,
                    [1, 0, 8, 6] * 2, [0, 0, -8, 6] * 2,
                    [0, 0, 8, 6, 0, 0, 9, 6], [False, 0, 8, 6] * 2):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                run_ground_clearance(bad)

    def test_source_groups_cannot_shadow_each_other(self):
        self.assertEqual(locomotion_sources({'walks': {'walk.png': 'w'}, 'runs': {'run.png': 'r'}}),
                         {'walk.png': 'w', 'run.png': 'r'})
        with self.assertRaises(ValueError):
            locomotion_sources({'walks': {'x': 1}, 'runs': {'x': 2}})

    @staticmethod
    def frames():
        frames = []
        for i in range(8):
            frame = Image.new('RGBA', (128, 128))
            draw = ImageDraw.Draw(frame)
            draw.rectangle((42, 20, 85, 99), fill=(180, 95, 40, 255))
            draw.rectangle((42 + i, 90, 47 + i, 99), fill=(60, 40, 20, 255))
            frames.append(frame)
        return frames

    def test_normalization_preserves_clearance_and_uniform_scale(self):
        clearance = [0, 0, 6, 4] * 2
        strip, detail = normalize_strip(self.frames(), 128, 80, 110, 64, 110,
                                        ground_clearance=clearance)
        for i in range(8):
            self.assertEqual(visible_bbox(strip.crop((i * 128, 0, (i + 1) * 128, 128)))[3], 110 - clearance[i])
        self.assertEqual(detail['scale'], 1)
        with self.assertRaises(ValueError):
            normalize_strip(self.frames()[:2], 128, 80, 110, 64, 110, ground_clearance=clearance)

    def test_audit_flight_is_explicit_and_drift_still_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            clearance = [0, 0, 6, 4] * 2
            strip, _ = normalize_strip(self.frames(), 128, 80, 110, 64, 110, ground_clearance=clearance)
            strip.save(root / 'run.png')
            definition = dict(path='run.png', frame_width=128, frame_height=128, frame_count=8,
                              role='gait', gait_kind='run', pose_order=RUN_PHASES, fps=20,
                              ground_clearance=clearance)
            def check(value):
                issues = []
                report = audit_animation('run', value, root, {'baseline_tolerance': 2}, [], root / 'audit', False, 80, issues)
                return report, {i['code'] for i in issues}
            report, codes = check(definition)
            self.assertNotIn('baseline_jitter', codes)
            self.assertEqual(report['ground_metrics']['positions'], [110] * 8)
            bad = copy.deepcopy(definition)
            bad['ground_clearance'] = [0, 0, 2, 1] * 2
            self.assertIn('baseline_jitter', check(bad)[1])
            bad['gait_kind'] = 'walk'
            self.assertIn('invalid_run_contract', check(bad)[1])
            walking = {k:v for k,v in definition.items() if k not in ('gait_kind', 'pose_order', 'ground_clearance')}
            self.assertIn('baseline_jitter', check(walking)[1])

    def test_partial_run_set_is_not_accepted(self):
        spec = dict(gait=dict(pose_order=list('abcdefgh'), pixels_per_frame=3, base_speed=32,
                             speed_multipliers=[1] * 8, acceleration_multipliers=[1] * 8),
                    run_gait=dict(pose_order=RUN_PHASES, pixels_per_frame=6, base_speed=185), directions={})
        animations = {}
        for direction in CANONICAL_DIRECTIONS:
            name = 'run_' + direction
            spec['directions'][direction] = {'run_animation': name}
            animations[name] = {'role':'gait', 'gait_kind':'run', 'frame_count':8}
        issues = []
        validate_gait(spec, animations, issues)
        self.assertEqual(issues, [])
        spec['directions']['west']['run_animation'] = 'run_east'
        issues = []
        validate_gait(spec, animations, issues)
        self.assertIn('incomplete_run_set', {i['code'] for i in issues})

    def test_doctor_detects_run_and_requires_all_directional_pairs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / 'assets/sprites/character-animations/test-fox'
            folder.mkdir(parents=True)
            (folder / 'run.png').touch()
            doctor = SpriteDoctor(root)
            actions = doctor.audit_actions('test-fox')
            self.assertTrue(set(RUN_ACTION_SPECS).issubset(actions))
            self.assertIn('walk_west', actions)
            self.assertIn('idle_north', actions)
            self.assertEqual(doctor.expected_frame_count('test-fox', 'run'), 8)

    def test_run_reviews_require_distinct_artifacts_and_clean_doctor(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifacts = expected_review_artifacts({'directions': {'east': {'run_animation': 'run_east'}}}, root, root)
            self.assertIn('run_preview_half_speed', artifacts['east'])
            path = root / 'doctor.json'
            path.write_text(json.dumps({'summary': {'errors': 0}, 'issues': [
                {'severity': 'warning', 'action': 'run_north', 'code': 'baseline_mismatch'}]}))
            issues = _validate_clean_reports({'sprite_doctor': path})
            self.assertIn('sprite_doctor_locomotion_issue', {i.code for i in issues})

    def test_doctor_flight_envelope_does_not_hide_bad_ground_or_body_size(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            folder = root / 'assets/sprites/character-animations/test-fox'
            folder.mkdir(parents=True)
            clearance = [0, 0, 6, 4] * 2
            manifest = {'character': 'test-fox', 'framing': {'frame_size': 128,
                'target_height': 80, 'center_x': 64, 'baseline': 110},
                'runs': {'run.png': {'ground_clearance': clearance}}}
            path = root / 'build.json';path.write_text(json.dumps(manifest))
            strip, _ = normalize_strip(self.frames(), 128, 80, 110, 64, 110, ground_clearance=clearance)
            strip.save(folder / 'run.png')
            doctor = SpriteDoctor(root, build_manifest=path)
            codes = {i.code for i in doctor.inspect_sheet('test-fox', 'run').issues}
            self.assertNotIn('baseline_mismatch', codes)
            self.assertNotIn('scale_mismatch', codes)
            # A contact frame cannot use flight clearance to hide a lower foot.
            altered = strip.copy()
            ImageDraw.Draw(altered).rectangle((54, 100, 70, 120), fill=(180, 95, 40, 255))
            altered.save(folder / 'run.png')
            self.assertIn('baseline_mismatch', {i.code for i in doctor.inspect_sheet('test-fox', 'run').issues})
            # Even flight frames retain a bounded body-size envelope.
            altered = strip.copy()
            ImageDraw.Draw(altered).rectangle((2 * 128 + 54, 2, 2 * 128 + 70, 95), fill=(180, 95, 40, 255))
            altered.save(folder / 'run.png')
            self.assertIn('scale_mismatch', {i.code for i in doctor.inspect_sheet('test-fox', 'run').issues})
