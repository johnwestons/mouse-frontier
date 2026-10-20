"""Stage authored combat frames; never synthesize poses or modify source art.

Uses the character motion auditor's per-animation gate. Directional locomotion
is outside this combat-only specification. Review contact-backgrounds.png and
previews before installing a staged, source-hash-checked suite.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
from statistics import median

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.build_resident_chore_assets import split_source, component_summary
from tools.build_character_action_assets import normalize, frames
from tools.build_directional_character_assets import visible_bbox
from tools import sprite_motion_audit as audit

OUT = ROOT / 'output/mob-combat'
SPECS = ROOT / 'mob-motion/combat'
ACTIONS = ('melee', 'ranged', 'hit', 'death')
DURATIONS = {'melee': .68, 'ranged': .68, 'hit': .58, 'death': .85}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def stage(record):
    name = record['name']
    source = Path(record['source'])
    destination = OUT / 'sources' / f'{name}.png'
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists() or sha(source) != sha(destination):
        shutil.copy2(source, destination)
    rows, segmentation = split_source(destination, 4, 6)
    ready_heights = [visible_bbox(row[0])[3] - visible_bbox(row[0])[1] for row in rows]
    max_height = max(visible_bbox(cell)[3] - visible_bbox(cell)[1] for row in rows for cell in row)
    max_width = max(cell.width for row in rows for cell in row)
    # One scale shared across the whole creature, including its collapse.
    scale = min(190 / median(ready_heights), 217 / max_height, 470 / max_width)
    target = OUT / 'staged' / name
    target.mkdir(parents=True, exist_ok=True)
    audit.component_summary = component_summary
    issues = []
    definitions = {}
    hashes = {}
    sheet = Image.new('RGB', (1152, 4 * 2 * 112), 'white')
    draw = ImageDraw.Draw(sheet)
    for row, action in enumerate(ACTIONS):
        strip, placements = normalize(rows[row], scale, 235)
        path = target / f'{action}.png'
        strip.save(path, optimize=True)
        definition = {'path': path.relative_to(ROOT).as_posix(), 'frame_width': 512,
                      'frame_height': 256, 'frame_count': 6, 'loop': False,
                      'fps': 6 / DURATIONS[action], 'duration': DURATIONS[action]}
        definitions[action] = definition
        audit.audit_animation(action, definition, ROOT,
            {'alpha_threshold': 16, 'edge_margin': 2, 'center_metric': 'core',
             'center_tolerance': 16, 'baseline_tolerance': 3}, [], target, True, None, issues)
        hashes[action] = sha(path)
        if len({frame.tobytes() for frame in frames(strip)}) != 6:
            raise ValueError(f'{name}/{action}: six distinct authored frames required')
        for style, color in enumerate(((241, 238, 226, 255), (20, 29, 39, 255))):
            top = (row * 2 + style) * 112
            draw.rectangle((0, top, 1152, top + 112), fill=color[:3])
            draw.text((4, top + 2), f'{name} / {action}', fill='black' if style == 0 else 'white')
            for index, frame in enumerate(frames(strip)):
                composite = Image.new('RGBA', frame.size, color)
                composite.alpha_composite(frame)
                sheet.paste(composite.resize((192, 96)).convert('RGB'), (index * 192, top + 16))
    sheet.save(target / 'contact-backgrounds.png')
    errors = [item for item in issues if item['severity'] == 'error']
    report = {'name': name, 'tool': 'built-in image_gen', 'prompt': record['prompt'],
              'source': destination.relative_to(ROOT).as_posix(), 'source_sha256': sha(destination),
              'scale': scale, 'segmentation': segmentation, 'hashes': hashes, 'issues': issues,
              'summary': {'errors': len(errors), 'warnings': len(issues) - len(errors)}}
    write(target / 'report.json', report)
    write(SPECS / f'{name}.json', {'version': 1, 'scope': 'combat-only', 'character': name,
        'animations': definitions, 'audit': {'alpha_threshold': 16, 'edge_margin': 2}})
    if errors:
        raise ValueError(f'{name}: animation audit failed: {errors}')
    print(f'STAGED {name}: 24 distinct poses, {len(issues)} review warnings', flush=True)


def install(name):
    target = OUT / 'staged' / name
    report = json.loads((target / 'report.json').read_text(encoding='utf-8'))
    assert report['summary']['errors'] == 0
    assert sha(ROOT / report['source']) == report['source_sha256'], 'source changed since audit'
    runtime = ROOT / 'assets/sprites/Mobs/combat' / name
    runtime.mkdir(parents=True, exist_ok=True)
    spec = json.loads((SPECS / f'{name}.json').read_text(encoding='utf-8'))
    for action in ACTIONS:
        source = target / f'{action}.png'
        assert sha(source) == report['hashes'][action], 'staged art changed since audit'
        shutil.copy2(source, runtime / source.name)
        spec['animations'][action]['path'] = (runtime / source.name).relative_to(ROOT).as_posix()
    spec.update({'status': 'reviewed_and_installed', 'source_sha256': report['source_sha256'],
                 'hashes': report['hashes'], 'tool': report['tool'], 'prompt': report['prompt']})
    write(SPECS / f'{name}.json', spec)
    print('INSTALLED ' + name)


def write_profiles():
    installed = {}
    for path in sorted(SPECS.glob('*.json')):
        spec = json.loads(path.read_text(encoding='utf-8'))
        if spec.get('status') == 'reviewed_and_installed':
            installed[spec['character']] = {a: v['path'] for a, v in spec['animations'].items()}
    for name in ('cowboy-mouse-no-skull', 'raccoon-cape', 'raccoon-heart',
                 'red-hood-mouse', 'shield-mouse', 'vampire-mouse'):
        installed[name] = {action: f'assets/sprites/character-animations/{name}/{action}.png' for action in ACTIONS}
    lines = ['-- Reviewed six-frame combat strips. Locomotion stays in its existing pipeline.', 'return {']
    for name, paths in sorted(installed.items()):
        with Image.open(ROOT / paths['melee']) as image:
            ready = image.crop((0, 0, image.width // 6, image.height)).convert('RGBA')
            box = visible_bbox(ready)
            ready_height = (box[3] - box[1]) * 256 / image.height
        reference = ROOT / f'assets/sprites/Mobs/{name}.png'
        if reference.exists() and name != 'sludge-crawler':
            with Image.open(reference) as image:
                box = visible_bbox(image.convert('RGBA'))
                neutral_height = min(76 / image.width, 96 / image.height) * (box[3] - box[1])
        else:
            neutral_height = 64 if name == 'sludge-crawler' else 84
        extent = ready_height * 96 / neutral_height
        facing = -1 if name in ('dust-beetle', 'sludge-crawler', 'wasteland-scorpion') else 1
        lines.append(f'    ["{name}.png"]={{bodyExtent={extent:.6f},baseFacing={facing},'
                     + ('neutralFromCombat=true,' if name == 'sludge-crawler' else '') + 'paths={')
        for action, path in paths.items():
            lines.append(f'        {action}="{path}",')
        lines.append('    }},')
    lines.extend(['}', ''])
    (ROOT / 'game/mob_combat_profiles.lua').write_text('\n'.join(lines), encoding='utf-8')
    print(f'PROFILES {len(installed)} mobs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path)
    parser.add_argument('--only', nargs='*')
    parser.add_argument('--install-reviewed', nargs='*')
    parser.add_argument('--write-profiles', action='store_true')
    args = parser.parse_args()
    if args.sources:
        for record in json.loads(args.sources.read_text(encoding='utf-8')):
            if not args.only or record['name'] in args.only:
                stage(record)
    for name in args.install_reviewed or []:
        install(name)
    if args.write_profiles:
        write_profiles()


if __name__ == '__main__':
    main()
