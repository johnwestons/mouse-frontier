"""Incremental draft review. Never installs sprites or grants semantic acceptance."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, __version__ as pillow_version

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.sprite_motion_audit import audit_animation, render_gif
from tools.character_sprite_doctor import SpriteDoctor
from tools.character_gait_contract import RUN_PHASES, run_ground_clearance

PHASES = ['left_contact', 'left_down', 'right_passing', 'right_up',
          'right_contact', 'right_down', 'left_passing', 'left_up']


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))


def engine_signature():
    return [platform.python_version(), pillow_version, np.__version__,
            *[digest(ROOT / p) for p in ['tools/review_character_motion.py',
              'tools/sprite_motion_audit.py', 'tools/build_directional_character_assets.py',
              'tools/character_gait_contract.py', 'tools/character_sprite_doctor.py']]]


def valid_cache(entry, key, output):
    if (not entry or entry.get('key') != key or not entry.get('files')
            or entry.get('result') not in entry['files']):
        return False
    for name, expected in entry['files'].items():
        path = (output / name).resolve()
        if not path.is_relative_to(output.resolve()) or not path.is_file() or digest(path) != expected:
            return False
    return True


def review_strip(source, definition, settings, output, entry=None, signature=None, pose_ms=108,
                 *, doctor=None, character=None):
    """Cache structural measurements only; all visible judgments remain pending."""
    before = digest(source)
    # Moving identical pixels into a new staging revision does not change their
    # structural measurements. Provenance/path bindings are checked at final acceptance.
    contract = {k:v for k,v in definition.items() if k != 'path'}
    doctor_contract = None
    if doctor is not None:
        doctor_contract = doctor.action_framing[(character, source.stem)]
    payload = [source.stem, before, contract, settings, pose_ms, signature or engine_signature(),
               doctor_contract]
    key = hashlib.sha256(encode(payload).encode()).hexdigest()
    if valid_cache(entry, key, output):
        result = json.loads((output / entry['result']).read_text())
        if digest(source) != before:
            raise RuntimeError('Input changed during review; result cannot be reused')
        return entry, result, True
    target = output / (source.stem + '-' + key[:16])
    target.mkdir(parents=True, exist_ok=True)
    issues = []
    phases = definition.get('pose_order', PHASES)
    result = audit_animation(source.stem, definition, ROOT, settings, phases,
                             target, True, pose_ms, issues)
    doctor_result = None
    if doctor is not None:
        inspection = doctor.inspect_sheet(character, source.stem)
        if inspection.path.resolve() != source.resolve():
            raise ValueError('Draft doctor must inspect the same staged sprite')
        doctor_issues = [issue.to_dict() for issue in inspection.issues]
        issues.extend(dict(issue, validator='sprite_doctor') for issue in doctor_issues)
        doctor_result = dict(issues=doctor_issues, framing_measurements=inspection.framing_measurements)
    with Image.open(source) as opened:
        strip = opened.convert('RGBA')
    size = definition['frame_width']
    count = definition['frame_count']
    frames = [strip.crop((i * size, 0, (i + 1) * size, size)) for i in range(count)]
    if definition['role'] == 'gait':
        render_gif(frames, target / 'previews' / (source.stem + '-half.gif'), pose_ms * 2)
        # Full-resolution opposing phases in one reviewable sheet, no new art.
        sheet = Image.new('RGBA', (size * 2, (size + 28) * 4), '#24313d')
        draw = ImageDraw.Draw(sheet)
        for row in range(4):
            for col, index in enumerate([row, row + 4]):
                x, y = col * size, row * (size + 28)
                draw.text((x + 8, y + 8), f'{index + 1}: {phases[index]}', fill='white')
                sheet.alpha_composite(frames[index], (x, y + 28))
        sheet.save(target / 'opposing.png')
    if digest(source) != before:
        raise RuntimeError('Input changed during review; result cannot be cached')
    counts = Counter(i['severity'] for i in issues)
    report = dict(status='draft_only', semantic_review='required', source_sha256=before,
                  summary=dict(errors=counts['error'], warnings=counts['warning']),
                  issues=issues, animation=result, sprite_doctor=doctor_result)
    result_path = target / 'result.json'
    result_path.write_text(json.dumps(report, indent=2) + '\n')
    files = {p.relative_to(output).as_posix(): digest(p) for p in target.rglob('*') if p.is_file()}
    entry = dict(key=key, result=result_path.relative_to(output).as_posix(), files=files)
    return entry, report, False


def run(manifest_path, *, base_speed=185, pixels_per_frame=20,
        run_base_speed=185, run_pixels_per_frame=None):
    started = time.monotonic()
    if base_speed <= 0 or pixels_per_frame <= 0:
        raise ValueError('Gait timing must be positive')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest.get('runs') and (run_pixels_per_frame is None or run_pixels_per_frame <= 0
                                 or run_base_speed <= 0):
        raise ValueError('Run drafts require positive run_base_speed and run_pixels_per_frame')
    character = manifest['character']
    if not character or Path(character).name != character or character in {'.', '..'}:
        raise ValueError('Invalid character name')
    base = ROOT / 'output/character-motion' / character
    stage = (ROOT / manifest['runtime_root']).resolve()
    if not stage.is_relative_to(base.resolve()) or stage == base.resolve():
        raise ValueError('Draft review requires a private staged subdirectory')
    doctor = SpriteDoctor(ROOT, base.parent, animation_subdirectory=str(stage.relative_to(base)),
                          build_manifest=manifest_path)
    output = base / 'workbench'
    output.mkdir(parents=True, exist_ok=True)
    index_path = output / 'index.json'
    try:
        index = json.loads(index_path.read_text())
    except (OSError, ValueError):
        index = {}
    frame_size = int(manifest['framing']['frame_size'])
    contracts = {}
    idle_sets = manifest.get('idle_sets') or [manifest['idle']]
    for item in idle_sets:
        for name in item['outputs']:
            contracts[name] = ('directional_idle', 2, item)
    for name, item in manifest['walks'].items():
        contracts[name] = ('gait', 8, item if isinstance(item, dict) else {})
    for name, item in manifest.get('runs', {}).items():
        if name in contracts:
            raise ValueError('Run outputs must not overlap walking or idle')
        contracts[name] = ('run', 8, item if isinstance(item, dict) else {})
    signature = engine_signature()
    results = []
    reused = 0
    for name, (role, count, options) in contracts.items():
        if Path(name).name != name or not name.endswith('.png'):
            raise ValueError('Output must be a PNG basename')
        source = stage / name
        definition = dict(path=str(source), frame_width=frame_size, frame_height=frame_size,
                          frame_count=count, role='gait' if role == 'run' else role, fps=.65, loop=True)
        pose_ms = round(1000 * pixels_per_frame / base_speed)
        if role == 'run':
            definition.update(gait_kind='run', pose_order=RUN_PHASES,
                              ground_clearance=run_ground_clearance(options.get('ground_clearance'), frame_size),
                              fps=run_base_speed / run_pixels_per_frame)
            pose_ms = round(1000 * run_pixels_per_frame / run_base_speed)
        elif role == 'gait':
            definition['fps'] = base_speed / pixels_per_frame
        else:
            pose_ms = round(1000 / definition['fps'])
        settings = dict(alpha_threshold=16, edge_margin=2, detached_component_ratio=.003,
                        baseline_tolerance=8, center_tolerance=14,
                        center_metric=options.get('horizontal_anchor', manifest['framing'].get('horizontal_anchor', 'bbox')))
        entry, result, cached = review_strip(source, definition, settings, output,
                                             index.get(name), signature, pose_ms,
                                             doctor=doctor, character=character)
        index[name] = entry
        reused += cached
        results.append(dict(action=source.stem, source=str(source), cached=cached,
                            report=entry['result'], **result['summary']))
    index_path.write_text(json.dumps(index, indent=2) + '\n')
    summary = dict(character=character, status='draft_only', semantic_acceptance=False,
                   measured=len(results)-reused, reused=reused,
                   errors=sum(r['errors'] for r in results), warnings=sum(r['warnings'] for r in results),
                   seconds=round(time.monotonic()-started, 3), actions=results)
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--base-speed', type=float, default=185)
    parser.add_argument('--pixels-per-frame', type=float, default=20)
    parser.add_argument('--run-base-speed', type=float, default=185)
    parser.add_argument('--run-pixels-per-frame', type=float)
    args = parser.parse_args()
    result = run(args.manifest.resolve(), base_speed=args.base_speed,
                 pixels_per_frame=args.pixels_per_frame, run_base_speed=args.run_base_speed,
                 run_pixels_per_frame=args.run_pixels_per_frame)
    print(json.dumps({k:v for k,v in result.items() if k != 'actions'}))
    return 1 if result['errors'] or result['warnings'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
