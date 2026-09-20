"""One-time archival inventory of pre-review dialogue and surrounding UI text."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FILES = ['catalog','npc_relationships','help_dialogue_quests','journey_rules',
         'quest_progression','stop_help_progression','gameplay_input','inventory_actions',
         'world_scene','last_stand_quest','last_stand_tuning','last_stand_shootout',
         'events','finale_progression','screen_ui']

def main():
    target = ROOT / 'docs/dialogue-review/legacy-text.md'
    if target.exists():
        raise SystemExit('Archive already exists; do not overwrite the original text.')
    target.parent.mkdir(parents=True, exist_ok=True)
    lines = ['# Original dialogue review inventory', '',
             'Captured before the September 14, 2026 dialogue changes. Authorship is unverified: these are review candidates, not a claim that every line was AI-written. Original line numbers refer to the pre-change files. Nearby gameplay notices and narrative text are included for context; they are not automatically dialogue.', '',
             'Only the 13 conversations in user-conversations.txt are approved by the current request. Reply with an entry ID and KEEP, DELETE, or your replacement. KEEP requires confirmation that the line is your supplied/approved text.', '']
    count = 0
    for name in FILES:
        path = ROOT / f'game/{name}.lua'
        lines += [f'## {path.relative_to(ROOT).as_posix()}', '']
        for number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
            if line.lstrip().startswith('--'): continue
            for match in re.finditer(r'"((?:\\.|[^"\\])*)"', line):
                value=match.group(1)
                if not re.search(r'[A-Za-z]+[ ,.!?][A-Za-z ]', value): continue
                if any(word in value for word in [' requires ', ' must be ', 'require an ', 'context']): continue
                count += 1
                lines += [f'- **D{count:04d}** (original line {number}): {value.replace(chr(124), chr(92)+chr(124))}']
        lines += ['']
    target.write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(f'Archived {count} dialogue/narrative/UI candidates in {target}')

if __name__ == '__main__': main()
