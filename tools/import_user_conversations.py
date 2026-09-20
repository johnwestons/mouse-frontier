"""Import the author's exact Q/A/R text; parentheses describe game actions."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDS = ['travel-time','wastes','going-west','worries','weapons','food','great-flash',
       'ammunition','wounds','mutations','mean-critters','sludges','westward']

def parse():
    entries=[]
    for line in (ROOT/'docs/dialogue-review/user-conversations.txt').read_text(encoding='utf-8-sig').splitlines():
        match=re.match(r'\s*(Q|A[123]|R[123]):\s*(.*?)\s*$',line)
        if not match: continue
        kind,text=match.groups()
        text=re.sub(r'\s*\(gives .*?\)\s*$','',text)
        if kind=='Q': entries.append({'id':IDS[len(entries)],'question':text,'answers':{},'responses':{}})
        else: entries[-1]['answers' if kind[0]=='A' else 'responses'][int(kind[1])]=text
    assert len(entries)==13
    return entries

def main():
    quote=lambda text: json.dumps(text,ensure_ascii=False)
    lines=['-- AUTHOR-SUPPLIED TEXT ONLY. Source: docs/dialogue-review/user-conversations.txt.',
           '-- Preserve spelling, punctuation and capitalization; do not invent dialogue.', 'return {']
    for entry in parse():
        lines += ['    {id='+quote(entry['id'])+', question='+quote(entry['question'])+', choices={']
        for i in range(1,4):
            effect=''
            if entry['id']=='food' and i<3: effect=', cost={food=2'+(',water=1' if i==2 else '')+'}'
            if entry['id']=='ammunition': effect=[', ammo={caliber="22lr",amount=20}',', ammo={caliber="9mm",amount=10}',', ammo={mixed=true,amount=15}'][i-1]
            if entry['id']=='wounds' and i>1: effect=', item="'+('field-bandage-roll' if i==2 else 'frontier-medkit')+'"'
            lines += ['        {label='+quote(entry['answers'][i])+', response='+quote(entry['responses'][i])+effect+'},']
        lines += ['    }},']
    lines += ['}']
    (ROOT/'game/authored_dialogue.lua').write_text('\n'.join(lines)+'\n',encoding='utf-8')

if __name__=='__main__': main()
