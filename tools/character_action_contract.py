"""Read the same reviewed rectangular action contract used by the game."""
from functools import lru_cache
import json
from pathlib import Path


@lru_cache(maxsize=8)
def reviewed_actions(project_root: Path) -> dict:
    path = Path(project_root) / 'character-motion/actions/acceptance.json'
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding='utf-8'))['characters']


def action_contract(project_root: Path, character: str, action: str) -> dict | None:
    if action == 'swing':
        record = reviewed_swings(Path(project_root).resolve()).get(character)
        if record and record.get('status') == 'reviewed_and_installed':
            return {'frame_count': 6, 'frame_width': 512, 'frame_height': 256, 'hands': record['hands']}
        return None
    record = reviewed_actions(Path(project_root).resolve()).get(character)
    definition = record and record.get('actions', {}).get(action)
    if not definition or record.get('status') != 'reviewed_and_installed':
        return None
    return {'frame_count': definition['frame_count'], 'frame_width': 512, 'frame_height': 256,
            'hands': record.get('hands', {}).get(action)}


@lru_cache(maxsize=8)
def reviewed_swings(project_root: Path) -> dict:
    path = project_root / 'character-motion/swings/acceptance.json'
    return json.loads(path.read_text(encoding='utf-8'))['characters'] if path.is_file() else {}
