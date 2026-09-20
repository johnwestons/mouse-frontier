from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image, ImageDraw
from tools import review_character_motion as review
from tools.character_sprite_doctor import SpriteDoctor


class DraftReviewCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'idle.png'
        Image.new('RGBA', (64, 32), (20, 50, 100, 255)).save(self.source)
        self.definition = dict(path=str(self.source), frame_width=32, frame_height=32,
                               frame_count=2, role='directional_idle', loop=True, fps=.65)
        self.output = self.root / 'review'
        self.mock = patch.object(review, 'audit_animation', side_effect=self.audit).start()
        self.addCleanup(patch.stopall)

    def audit(self, *args):
        target = args[5]
        (target / 'contact.png').write_bytes(b'fixture preview')
        return {'frames': []}

    def run_review(self, entry=None, signature=None, settings=None):
        return review.review_strip(self.source, self.definition, settings or {}, self.output,
                                   entry, signature or ['fixture engine'])

    def test_unchanged_input_and_artifacts_reuse_without_acceptance(self):
        entry, result, cached = self.run_review()
        self.assertFalse(cached)
        _, result, cached = self.run_review(entry)
        self.assertTrue(cached)
        self.assertEqual(self.mock.call_count, 1)
        self.assertEqual(result['status'], 'draft_only')
        self.assertEqual(result['semantic_review'], 'required')

    def test_changed_sprite_remeasured(self):
        entry, _, _ = self.run_review()
        Image.new('RGBA', (64, 32), (30, 50, 100, 255)).save(self.source)
        self.assertFalse(self.run_review(entry)[2])

    def test_explicit_pose_labels_are_audited_and_invalidate_cache(self):
        entry, _, _ = self.run_review()
        labels = ['neutral', 'blink']
        self.definition['pose_order'] = labels
        self.assertFalse(self.run_review(entry)[2])
        self.assertEqual(self.mock.call_args.args[4], labels)

    def test_identical_pixels_in_new_staging_revision_reuse(self):
        entry, _, _ = self.run_review()
        moved = self.root / 'revision2' / 'idle.png'
        moved.parent.mkdir()
        moved.write_bytes(self.source.read_bytes())
        self.source = moved
        self.definition['path'] = str(moved)
        self.assertTrue(self.run_review(entry)[2])

    def test_changed_engine_or_settings_remeasured(self):
        entry, _, _ = self.run_review()
        self.assertFalse(self.run_review(entry, signature=['changed engine'])[2])
        self.assertFalse(self.run_review(entry, settings={'edge_margin': 9})[2])

    def test_tampered_result_or_missing_artifact_remeasured(self):
        entry, _, _ = self.run_review()
        (self.output / entry['result']).write_text('{}')
        self.assertFalse(self.run_review(entry)[2])
        (self.output / next(k for k in entry['files'] if k.endswith('contact.png'))).unlink()
        self.assertFalse(self.run_review(entry)[2])

    def test_input_change_during_review_refuses_cache(self):
        # Change after image loading by intercepting the final digest check.
        with patch.object(review, 'digest', side_effect=['before', 'after']):
            with self.assertRaisesRegex(RuntimeError, 'changed during review'):
                self.run_review()

    def test_failed_measurement_is_not_hidden_by_cache(self):
        def warning(*args):
            args[8].append({'severity':'warning', 'code':'fixture'})
            return self.audit(*args)
        self.mock.side_effect = warning
        entry, result, _ = self.run_review()
        self.assertEqual(result['summary']['warnings'], 1)
        _, result, cached = self.run_review(entry)
        self.assertTrue(cached)
        self.assertEqual(result['summary']['warnings'], 1)

    def test_cache_cannot_reference_outside_review_directory(self):
        outside = self.root / 'outside.txt'
        outside.write_text('fixture')
        entry = {'key':'key', 'files':{'../outside.txt':review.digest(outside)}}
        self.assertFalse(review.valid_cache(entry, 'key', self.output))


class DraftDoctorParityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / 'output/character-motion/test-mouse'
        self.stage = self.base / 'east-v1'
        self.stage.mkdir(parents=True)
        self.manifest = self.base / 'build.json'
        self.data = dict(character='test-mouse', runtime_root=str(self.stage.relative_to(self.root)),
                         framing=dict(frame_size=512, target_height=340, center_x=256, baseline=458),
                         idle_sets=[dict(outputs=['idle.png'])], walks={'walk.png': {}},
                         runs={'run.png': dict(ground_clearance=[0,0,8,6,0,0,8,6])})
        self.manifest.write_text(json.dumps(self.data))
        for name, count in [('idle', 2), ('walk', 8), ('run', 8)]:
            strip = Image.new('RGBA', (512 * count, 512))
            for index in range(count):
                clearance = self.data['runs']['run.png']['ground_clearance'][index] if name == 'run' else 0
                # Deliberately too short, reproducing the late Courier west fault.
                ImageDraw.Draw(strip).rectangle((index*512+156, 132-clearance,
                                                index*512+355, 457-clearance),
                                               fill=(60+index, 90, 120, 255))
            strip.save(self.stage / (name+'.png'))
        self.addCleanup(patch.stopall)
        patch.object(review, 'ROOT', self.root).start()
        patch.object(review, 'engine_signature', return_value=['fixture']).start()
        self.audit = patch.object(review, 'audit_animation', return_value={'frames': []}).start()

    def run_review(self):
        return review.run(self.manifest, base_speed=32, pixels_per_frame=2.56,
                          run_base_speed=185, run_pixels_per_frame=6)

    def test_all_three_actions_use_exact_final_doctor_checks_and_cache_failures(self):
        result = self.run_review()
        self.assertEqual(len(result['actions']), 3)
        self.assertGreater(result['warnings'], 0)
        doctor = SpriteDoctor(self.root, self.base.parent, animation_subdirectory='east-v1',
                              build_manifest=self.manifest)
        for action in result['actions']:
            report = json.loads((self.base / 'workbench' / action['report']).read_text())
            expected = [issue.to_dict() for issue in doctor.inspect_sheet('test-mouse', action['action']).issues]
            self.assertEqual(report['sprite_doctor']['issues'], expected)
            self.assertTrue(any(issue['code'] == 'scale_mismatch' for issue in expected))
            self.assertFalse(any(issue['code'] == 'frame_count_mismatch' for issue in expected))
        cached = self.run_review()
        self.assertEqual(cached['warnings'], result['warnings'])
        self.assertEqual(cached['reused'], 3)
        self.assertEqual(self.audit.call_count, 3)
        self.assertFalse(cached['semantic_acceptance'])

    def test_run_phases_clearance_and_separate_cadence_are_audited(self):
        self.run_review()
        calls = {call.args[0]: call.args for call in self.audit.call_args_list}
        self.assertEqual(calls['run'][1]['pose_order'], review.RUN_PHASES)
        self.assertEqual(calls['run'][1]['ground_clearance'], [0,0,8,6,0,0,8,6])
        self.assertEqual(calls['run'][7], round(1000*6/185))
        self.assertEqual(calls['walk'][7], 80)
        self.assertEqual(calls['idle'][7], round(1000/.65))

    def test_changed_framing_contract_invalidates_unchanged_pixel_cache(self):
        self.run_review()
        self.data['framing']['target_height'] = 339
        self.manifest.write_text(json.dumps(self.data))
        self.assertEqual(self.run_review()['reused'], 0)

    def test_run_timing_is_required_instead_of_silently_using_walk_cadence(self):
        with self.assertRaisesRegex(ValueError, 'run_pixels_per_frame'):
            review.run(self.manifest)
        self.assertFalse((self.base / 'workbench').exists())


if __name__ == '__main__':
    unittest.main()
