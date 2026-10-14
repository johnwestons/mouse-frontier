"""Static packaged PNG/ownership evidence, not a measured runtime memory profile.

Reads PNG headers and Lua source only. Does not launch LOVE/ADB, decode textures,
touch saves, infer an Android kill cause, or change packaged/source assets.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct


def png(path: Path, root: Path) -> dict:
    with path.open('rb') as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError(f'Not a PNG IHDR: {path}')
    width, height = struct.unpack('>II', header[16:24])
    return {'path': path.relative_to(root).as_posix(), 'width': width, 'height': height,
            'rgba8_mib_estimate': round(width * height * 4 / 1048576, 6)}


def audit(root: Path) -> dict:
    root = root.resolve()
    read = lambda name: (root / 'game' / name).read_text(encoding='utf-8')
    guest, boundary, app, update, renderer, animation = (
        read(name) for name in ('coop_guest_view.lua', 'local_play_host.lua', 'application_composition.lua',
                               'gameplay_update.lua', 'view_composition.lua', 'character_animation.lua'))
    rows = [png(path, root) for path in (root / 'assets').rglob('*.png')]
    indexed = {row['path']: row for row in rows}
    groups = {}
    for name, pattern in {
        'playable_portraits': 'assets/sprites/MainCharacters/*.png',
        'family_portraits': 'assets/sprites/NPCS/families/*.png',
        'walkmasks': 'assets/sprites/stops/walkmask-*.png',
        'title_art_potential': 'assets/sprites/ui/title/**/*.png',
    }.items():
        paths = list(root.glob(pattern))
        values = [indexed[path.relative_to(root).as_posix()] for path in paths]
        groups[name] = {'files': len(values), 'rgba8_mib_estimate': round(sum(row['rgba8_mib_estimate'] for row in values), 3)}
    characters = {}
    for name in ('botanist-frog', 'conductor-cat', 'cook-mouse', 'crow-merchant', 'scout-frog'):
        paths = list((root / 'assets/sprites/character-animations' / name).glob('*.png'))
        values = [indexed[path.relative_to(root).as_posix()] for path in paths]
        characters[name] = {'authored_files': len(values), 'all_files_rgba8_mib_estimate': round(sum(row['rgba8_mib_estimate'] for row in values), 3)}
    retain = animation.split('function CharacterAnimation.retain(', 1)[1].split('function CharacterAnimation.draw(', 1)[0]
    relevant = ('assets/sprites/events/help-a.png', 'assets/sprites/stops/settlement-wide-01.png',
                'assets/sprites/ui/title/title-header-backdrop-v1.png', 'assets/sprites/ui/title/title-footer-backdrop-v1.png')
    return {'game_root': str(root), 'evidence_kind': 'static packaged source + PNG IHDR only',
            'limits': ['RGBA8 estimates are not measured CPU/GPU/RSS allocation.',
                       'Potential asset groups are not proof that all assets were simultaneously resident.',
                       'Android kill cause and runtime peak must be measured on the device.'],
            'ownership_evidence': {
                'normal_update_releases_intro': 'Assets.releaseIntroImages(scenery)' in update,
                'normal_update_releases_dormant_art': 'Assets.releaseDormantSceneArt(scenery,runtime)' in update,
                'guest_view_releases_intro': 'releaseIntroImages(' in guest,
                'guest_view_releases_dormant_art': 'releaseDormantSceneArt(' in guest,
                'client_boundary_uses_idle_update': 'context.idleUpdate(dt,client()' in boundary,
                'idle_update_only_persistence_audio': 'idleUpdate=function(dt,presentation) platform.persistenceRuntime.update(dt); platform.audioRuntime.update(presentation)' in app,
                'guest_renderer_reuses_content_options': 'for key,value in pairs(rendererOptions)' in renderer,
                'character_retain_loads_new_before_old_release': retain.index('loadSet(manager,file)') < retain.index('releaseSet(set)'),
            }, 'asset_groups': groups, 'character_sets': characters,
            'transition_assets': [indexed[path] for path in relevant if path in indexed]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-root', type=Path, default=Path('output/mobile/stage'))
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = audit(args.game_root)
    encoded = json.dumps(result, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded + '\n', encoding='utf-8')
    print(encoded)


if __name__ == '__main__':
    main()
