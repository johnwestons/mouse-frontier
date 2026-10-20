"""Stage and audit authored action atlases, then install only reviewed hashes.

Sources are immutable built-in ImageGen outputs. Six columns form one action;
optional action lists allow a source repair to replace only the affected rows.
Locomotion and chore assets are preserved. No new motion is synthesized here.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.build_resident_chore_assets import split_source, installed_framing, component_summary, sha256
from tools.build_directional_character_assets import visible_bbox, core_horizontal_anchor_x
from tools.character_sprite_doctor import detect_hand_anchor
from tools import sprite_motion_audit as audit

ACTIONS = ('sit', 'lay', 'melee', 'ranged', 'use', 'hit', 'death', 'unconscious')
COUNT, WIDTH, HEIGHT = 6, 512, 256
OUT = ROOT / 'output/character-actions'
SPECS = ROOT / 'character-motion/actions'
SETTINGS = {'alpha_threshold': 16, 'edge_margin': 2, 'center_metric': 'core',
            'center_tolerance': 12, 'baseline_tolerance': 3}
PLAYBACK = {
    'idle': {'fps': .65, 'loop': True},
    'sit': {'fps': 8, 'intro_frames': 4, 'loop_start': 5, 'hold_fps': .7},
    'lay': {'fps': 7, 'intro_frames': 4, 'loop_start': 5, 'hold_fps': .5},
    'melee': {'duration': .35}, 'ranged': {'duration': .35}, 'use': {'duration': .35},
    'hit': {'duration': .5}, 'death': {'duration': .85},
    'unconscious': {'fps': .8, 'loop': True},
}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def normalize(cells, scale, baseline):
    strip = Image.new('RGBA', (WIDTH * COUNT, HEIGHT))
    details = []
    for index, source in enumerate(cells):
        crop = source.resize((max(1, round(source.width * scale)), max(1, round(source.height * scale))),
                             Image.Resampling.LANCZOS)
        box = visible_bbox(crop)
        core = core_horizontal_anchor_x(crop, box)
        x, y = round(WIDTH / 2 - core), baseline - box[3]
        if x < 3 or y < 3 or x + crop.width > WIDTH - 3 or y + crop.height > HEIGHT - 3:
            raise ValueError(f'frame {index + 1} would clip; repair the source')
        strip.alpha_composite(crop, (index * WIDTH + x, y))
        details.append({'source_size': list(source.size), 'left': x, 'top': y, 'baseline': baseline})
    return strip, details


def frames(strip):
    return [strip.crop((i * WIDTH, 0, (i + 1) * WIDTH, HEIGHT)) for i in range(COUNT)]


def right_hand_anchor(frame, index):
    # New action art always faces right. The old detector compares both outer
    # edges, so a large tail or backpack can win over the actual weapon hand.
    box = visible_bbox(frame)
    height = box[3] - box[1]
    top, bottom = round(box[1] + height * .43), round(box[1] + height * .67)
    mask = np.asarray(frame.getchannel('A'))[top:bottom] > 16
    ys, xs = np.nonzero(mask)
    if not len(xs):
        return asdict(detect_hand_anchor(frame, index))
    edge = np.percentile(xs, 99)
    near = (xs >= edge - max(4, height * .07)) & (xs <= edge)
    return {'frame': index, 'x': float(np.mean(xs[near])) / WIDTH,
            'y': float(np.mean(ys[near]) + top) / HEIGHT, 'side': 1, 'confidence': .7}


def previews(slug, runtime, destination, hands, actions):
    # All frames on both light and dark backgrounds; the small hand markers
    # belong to the review evidence only and never enter runtime artwork.
    tile_w, tile_h = 192, 110
    sheet = Image.new('RGB', (COUNT * tile_w, len(actions) * 2 * tile_h), 'white')
    draw = ImageDraw.Draw(sheet)
    for row, action in enumerate(actions):
        strip = Image.open(runtime / f'{action}.png').convert('RGBA')
        for bg, color in enumerate(((241, 238, 226, 255), (20, 29, 39, 255))):
            top = (row * 2 + bg) * tile_h
            for index, frame in enumerate(frames(strip)):
                canvas = Image.new('RGBA', frame.size, color); canvas.alpha_composite(frame)
                if action in hands:
                    point = hands[action][index]
                    marker = ImageDraw.Draw(canvas)
                    x, y = point['x'] * WIDTH, point['y'] * HEIGHT
                    marker.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(0, 255, 180), width=2)
                sheet.paste(canvas.resize((tile_w, 96), Image.Resampling.LANCZOS).convert('RGB'),
                            (index * tile_w, top + 14))
            draw.text((4, top + 2), f'{slug} / {action}', fill='black')
    sheet.save(destination / 'contact-backgrounds.png')


def review_pages(slugs, tag):
    """All staged poses at game size, beside the immutable neutral reference."""
    paths=[]; directory=OUT/'reviews';directory.mkdir(parents=True,exist_ok=True)
    for offset in range(0,len(slugs),2):
        pair=slugs[offset:offset+2]
        extra=any((OUT/slug/'runtime/idle.png').exists() for slug in pair)
        rows=['reference']+list(ACTIONS)+(['idle'] if extra else [])
        for style,color in (('light',(241,238,226,255)),('dark',(20,29,39,255))):
            sheet=Image.new('RGB',(1968,len(rows)*100),'white');draw=ImageDraw.Draw(sheet)
            for column,slug in enumerate(pair):
                for row,action in enumerate(rows):
                    x,y=column*984,row*100
                    draw.text((x+4,y+2),f'{slug} / {action}',fill='black')
                    if action=='reference':
                        reference=Image.open(OUT/'references/identity'/f'{slug}.png').convert('RGBA')
                        canvas=Image.new('RGBA',(512,512),color);canvas.alpha_composite(reference)
                        frame=canvas.resize((82,82),Image.Resampling.LANCZOS).convert('RGB')
                        for index in range(6):
                            sheet.paste(color[:3],(x+index*164,y+18,x+(index+1)*164,y+100))
                            sheet.paste(frame,(x+index*164+41,y+18))
                        continue
                    path=OUT/slug/'runtime'/f'{action}.png'
                    if not path.exists():continue
                    for index,frame in enumerate(frames(Image.open(path).convert('RGBA'))):
                        canvas=Image.new('RGBA',frame.size,color);canvas.alpha_composite(frame)
                        sheet.paste(canvas.resize((164,82),Image.Resampling.LANCZOS).convert('RGB'),(x+index*164,y+18))
            path=directory/f'{tag}-{offset//2+1:02d}-{style}.png';sheet.save(path);paths.append(path)
    return paths


def build(slug, sources):
    destination = OUT / slug; runtime = destination / 'runtime'; runtime.mkdir(parents=True, exist_ok=True)
    selected, source_records, source_heights = {}, [], {}
    for source in sources:
        path = OUT / 'sources' / source['file']
        shutil.copyfile(source['generated_path'], path) if not path.exists() else None
        actions = source.get('actions', list(ACTIONS))
        rows, record = split_source(path.resolve(), len(actions), COUNT)
        source_records.append(record)
        # The first sit/use pose is the upright neutral reference. Guarding
        # attack poses can have bent knees, so their median height must not
        # enlarge the entire atlas or make entering a pose change body size.
        reference = next((a for a in ('sit', 'use', 'idle', 'death', 'hit', 'melee', 'ranged') if a in actions), actions[0])
        source_heights[source['file']] = rows[actions.index(reference)][0].height
        for action, cells in zip(actions, rows):
            selected[action] = (cells, source, record)
    if not set(ACTIONS) <= set(selected):
        raise ValueError(f'{slug}: action coverage incomplete')
    actions = list(ACTIONS) + (['idle'] if 'idle' in selected else [])
    # One scale for the whole atlas: crouching and lying intentionally reduce
    # the visible body height. Never enlarge those poses to standing height.
    framing_path = SPECS / 'framing' / f'{slug}.json'
    if framing_path.exists():
        framing=json.loads(framing_path.read_text())
    elif (destination / 'build-report.json').exists():
        old=json.loads((destination / 'build-report.json').read_text())
        framing={k:old[k] for k in ('target_height','baseline')}
    else:
        target_height,baseline=installed_framing(slug)
        framing={'target_height':target_height,'baseline':baseline}
    write_json(framing_path,framing)
    target_height,baseline=framing['target_height'],framing['baseline']
    scales = {name: target_height / height for name, height in source_heights.items()}
    result = {'character': slug, 'sources': source_records, 'source_scales': scales,
              'target_height': target_height, 'baseline': baseline, 'actions': {}}
    hands = {}
    definitions = {}
    issues = []
    original = audit.component_summary; audit.component_summary = component_summary
    try:
        for action in actions:
            cells, source, record = selected[action]
            # A repair generated at a different resolution retains the same
            # source body's scale using its own upright reference, if supplied.
            action_scale = target_height / source['standing_height'] if 'standing_height' in source else scales[source['file']]
            strip, details = normalize(cells, action_scale, baseline)
            unique = len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames(strip)})
            if unique != COUNT:
                raise ValueError(f'{slug}/{action}: {unique} unique poses for {COUNT} frames')
            path = runtime / f'{action}.png'; strip.save(path)
            if action in ('melee', 'ranged'):
                hands[action] = [right_hand_anchor(frame, i + 1) for i, frame in enumerate(frames(strip))]
            playback = PLAYBACK[action]
            fps = playback.get('fps', COUNT / playback.get('duration', 1))
            definition = {'path': path.relative_to(ROOT).as_posix(), 'frame_width': WIDTH, 'frame_height': HEIGHT,
                          'frame_count': COUNT, 'fps': fps, 'role': 'authored_action',
                          'loop': playback.get('loop', False), 'playback': playback}
            definitions[action] = definition
            audit.audit_animation(action, definition, ROOT, SETTINGS, [], destination / 'audit', True, None, issues)
            audit.render_gif(frames(strip), destination / 'audit/previews' / f'{action}-half-speed.gif', round(2000 / fps))
            result['actions'][action] = {'source': source['file'], 'source_sha256': record['sha256'],
                'sha256': sha256(path), 'frame_count': COUNT, 'unique_frames': unique, 'frames': details}
    finally:
        audit.component_summary = original
    spec = {'version': 1, 'character': slug, 'animations': definitions, 'audit': SETTINGS,
            'scope': 'Authored non-locomotion actions; existing gait, directional idles and chores are unchanged.',
            'body_extent': HEIGHT, 'core_x': WIDTH / 2, 'baseline': baseline}
    write_json(SPECS / f'{slug}.json', spec)
    report = {'summary': {'errors': sum(i['severity'] == 'error' for i in issues),
                          'warnings': sum(i['severity'] == 'warning' for i in issues)}, 'issues': issues}
    write_json(destination / 'audit/report.json', report)
    previews(slug, runtime, destination, hands, actions)
    result['hands'] = hands; result['audit'] = report['summary']
    result['evidence'] = {name: {'path': path.relative_to(ROOT).as_posix(), 'sha256': sha256(path)}
        for name, path in {'spec': SPECS / f'{slug}.json', 'audit': destination / 'audit/report.json',
                           'contact': destination / 'contact-backgrounds.png'}.items()}
    write_json(destination / 'build-report.json', result)
    print(f'{slug}: staged {COUNT * len(actions)} poses, audit {report["summary"]}', flush=True)


def runtime_profiles(ledger):
    lines = ['-- Generated from reviewed character-motion/actions/acceptance.json.', 'return {', '  actions={']
    for action, playback in PLAYBACK.items():
        fields = ['count=6', 'bodyExtent=256', 'authoredRight=true']
        mapping = {'intro_frames': 'introFrames', 'loop_start': 'loopStart', 'hold_fps': 'holdFps'}
        for key, value in playback.items():
            fields.append(f'{mapping.get(key, key)}={str(value).lower()}')
        lines.append(f'    {action}={{' + ','.join(fields) + '},')
    lines.extend(['  },', '  characters={'])
    for slug, record in sorted(ledger['characters'].items()):
        lines.append(f'    ["{slug}.png"]={{hasIdle={str("idle" in record["actions"]).lower()},hands={{')
        for action, points in record['hands'].items():
            values = ['{x=%.6f,y=%.6f,side=%d}' % (p['x'], p['y'], p['side']) for p in points]
            lines.append(f'      {action}={{' + ','.join(values) + '},')
        lines.append('    }},')
    lines.extend(['  }', '}', ''])
    (ROOT / 'game/character_action_profiles.lua').write_text('\n'.join(lines), encoding='utf-8')


def install(slug):
    destination = OUT / slug
    report = json.loads((destination / 'build-report.json').read_text())
    if report['audit']['errors'] or not set(ACTIONS) <= set(report['actions']):
        raise ValueError(f'{slug}: all actions must pass the audit')
    for evidence in report['evidence'].values():
        if sha256(ROOT / evidence['path']) != evidence['sha256']:
            raise ValueError(f'{slug}: review evidence changed')
    for action, record in report['actions'].items():
        if sha256(OUT / 'sources' / record['source']) != record['source_sha256']:
            raise ValueError(f'{slug}: source changed after review')
        staged = destination / 'runtime' / f'{action}.png'
        if sha256(staged) != record['sha256']:
            raise ValueError(f'{slug}/{action}: staging changed after review')
        shutil.copyfile(staged, ROOT / 'assets/sprites/character-animations' / slug / f'{action}.png')
    path = SPECS / 'acceptance.json'
    ledger = json.loads(path.read_text()) if path.exists() else {'version': 1, 'characters': {}}
    ledger['characters'][slug] = {'status': 'reviewed_and_installed', 'reviewed_at': datetime.now(timezone.utc).isoformat(),
                                'actions': report['actions'], 'hands': report['hands'], 'evidence': report['evidence'],
                                'audit': report['audit']}
    write_json(path, ledger); runtime_profiles(ledger)
    print(f'{slug}: installed exact reviewed staging files', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', nargs='*')
    parser.add_argument('--install-reviewed', action='store_true')
    args = parser.parse_args()
    sources=[]
    for name in ('generation-prompts.json','orientation-repairs.json'):
        path=SPECS/name
        if path.exists(): sources.extend(s for s in json.loads(path.read_text())['sources'] if not s.get('discarded'))
    characters = args.only or sorted({s['character'] for s in sources})
    (OUT / 'sources').mkdir(parents=True, exist_ok=True)
    for slug in characters:
        if args.install_reviewed: install(slug)
        else: build(slug, [s for s in sources if s['character'] == slug])


if __name__ == '__main__':
    main()
