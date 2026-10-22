"""Build the portable HTML fragment and optional in-conversation copy."""
from pathlib import Path
import argparse
import json
import runpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--inline-dir', type=Path)
args = parser.parse_args()
runpy.run_path(str(HERE / 'prepare_sprites.py'))
data = (ROOT / 'tmp/battle-environment-study/sprite-data.json').read_text(encoding='utf-8')
json.loads(data)
source = (HERE / 'lab.template.html').read_text(encoding='utf-8')
assert source.count('/* SPRITE_DATA */{}') == 1
result = source.replace('/* SPRITE_DATA */{}', data)
assert len(result.encode('utf-8')) < 1_000_000
dest = ROOT / 'docs/concepts/battle-environment-study/battle-terrain-lab.html'
dest.write_text(result, encoding='utf-8')
if args.inline_dir:
    assert args.inline_dir.is_dir()
    (args.inline_dir / 'battle-terrain-lab.html').write_text(result, encoding='utf-8')
print(f'Built {dest}: {len(result.encode("utf-8")):,} bytes')
