"""Stage authored ImageGen swings, retain source pixels, audit, then install reviewed strips.

Hand positions are manually reviewed source-atlas pixel coordinates. Angles are
authored weapon-tip vectors in degrees (right=0, down=90), one per body frame.
This tool only segments, scales and packs artwork; it never synthesizes poses.
"""
from __future__ import annotations
import argparse, hashlib, json, math, shutil, sys
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from tools.build_resident_chore_assets import split_source, component_summary, sha256
from tools.build_character_action_assets import normalize, frames, previews
from tools import sprite_motion_audit as audit
OUT=ROOT/'output/character-swings'
SPECS=ROOT/'character-motion/swings'

def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')

def sources():
    result=json.loads((SPECS/'sources.json').read_text())['characters']
    for p in sorted((SPECS/'generation').glob('*.json')):
        record=json.loads(p.read_text()); result[record['character']]=record
    return result

def build(slug,record):
    dest=OUT/slug; runtime=dest/'runtime'; runtime.mkdir(parents=True,exist_ok=True)
    source=OUT/'sources'/f'{slug}.png'; source.parent.mkdir(parents=True,exist_ok=True)
    generated=Path(record['generated_path'])
    if not source.exists() or (generated.exists() and sha256(source)!=sha256(generated)):
        shutil.copyfile(generated,source)
    rows,split=split_source(source,2,3)
    cells=[f for row in rows for f in row]
    framing=json.loads((ROOT/'character-motion/actions/framing'/f'{slug}.json').read_text())
    baseline=framing['baseline']
    scale=min(framing['target_height']/cells[0].height,(baseline-5)/max(f.height for f in cells))
    strip,details=normalize(cells,scale,baseline)
    path=runtime/'swing.png'; strip.save(path)
    hand_file=SPECS/'hands'/f'{slug}.json'
    hands=[]
    if hand_file.exists():
        authored=json.loads(hand_file.read_text())
        assert len(authored)==6
        for p,cell,info,seg in zip(authored,cells,details,split['frames']):
            # normalize() uses rounded dimensions, so transform with the exact pixel scale.
            bx,by,_,_=seg['bbox']
            sx=round(cell.width*scale)/cell.width; sy=round(cell.height*scale)/cell.height
            hands.append({'x':(info['left']+(p[0]-bx)*sx)/512,
                          'y':(info['top']+(p[1]-by)*sy)/256,'side':1,'angle':math.radians(p[2])})
    definition={'path':path.relative_to(ROOT).as_posix(),'frame_width':512,'frame_height':256,
                'frame_count':6,'fps':6/.35,'loop':False,'role':'authored_action','playback':{'duration':.35}}
    settings={'alpha_threshold':16,'edge_margin':2,'center_metric':'core','center_tolerance':12,'baseline_tolerance':3}
    spec={'version':1,'character':slug,'animations':{'swing':definition},'audit':settings,
          'scope':'Authored weapon swing; original unarmed melee and locomotion retained.'}
    write(SPECS/f'{slug}.json',spec)
    issues=[]; original=audit.component_summary; audit.component_summary=component_summary
    try: audit.audit_animation('swing',definition,ROOT,settings,[],dest/'audit',True,None,issues)
    finally: audit.component_summary=original
    report={'summary':{'errors':sum(i['severity']=='error' for i in issues),'warnings':sum(i['severity']=='warning' for i in issues)},'issues':issues}
    write(dest/'audit/report.json',report)
    previews(slug,runtime,dest,{'swing':hands} if hands else {},['swing'])
    source_im=Image.open(source).convert('RGBA')
    for style,color in [('light',(244,241,229,255)),('dark',(22,30,40,255))]:
        review=Image.new('RGBA',source_im.size,color); review.alpha_composite(source_im)
        if hands:
            draw=ImageDraw.Draw(review)
            for x,y,angle in authored:
                draw.ellipse((x-6,y-6,x+6,y+6),outline='cyan',width=3)
                draw.line((x,y,x+70*math.cos(math.radians(angle)),y+70*math.sin(math.radians(angle))),fill='cyan',width=3)
        review.thumbnail((768,512));review.convert('RGB').save(dest/f'source-{style}.png')
    result={'character':slug,'source_sha256':sha256(source),'sha256':sha256(path),'frame_count':6,
            'scale':scale,'body_scale_ratio':cells[0].height*scale/framing['target_height'],
            'split':split,'frames':details,'hands':hands,'audit':report['summary'],
            'evidence':{name:sha256(dest/name) for name in ['contact-backgrounds.png','source-light.png','source-dark.png','audit/report.json']}}
    write(dest/'build-report.json',result)
    print(f'{slug}: {report["summary"]}, hands={len(hands)}, body scale={result["body_scale_ratio"]:.2f}',flush=True)

def install(slug):
    dest=OUT/slug; record=json.loads((dest/'build-report.json').read_text())
    assert record['audit']['errors']==0 and len(record['hands'])==6,slug
    for name,digest in record['evidence'].items(): assert sha256(dest/name)==digest
    source=OUT/'sources'/f'{slug}.png'; strip=dest/'runtime/swing.png'
    assert sha256(source)==record['source_sha256'] and sha256(strip)==record['sha256']
    shutil.copyfile(strip,ROOT/'assets/sprites/character-animations'/slug/'swing.png')
    ledger_path=SPECS/'acceptance.json'
    ledger=json.loads(ledger_path.read_text()) if ledger_path.exists() else {'version':1,'characters':{}}
    ledger['characters'][slug]={**record,'status':'reviewed_and_installed'}
    write(ledger_path,ledger)
    lines=['-- Generated from reviewed character-motion/swings/acceptance.json.','return {',
           ' actions={swing={count=6,bodyExtent=256,authoredRight=true,duration=.35}},',' characters={']
    for name,item in sorted(ledger['characters'].items()):
        points=','.join('{x=%.8f,y=%.8f,side=1,angle=%.8f}'%(p['x'],p['y'],p['angle']) for p in item['hands'])
        lines.append('  ["'+name+'.png"]={'+points+',bodyScale=%.8f,baseline=%d},'%(item['body_scale_ratio'],item['frames'][0]['baseline']))
    lines+=[' }','}','']
    (ROOT/'game/character_swing_profiles.lua').write_text('\n'.join(lines),encoding='utf-8')
    print(f'{slug}: installed reviewed swing',flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only',nargs='*');parser.add_argument('--install-reviewed',action='store_true')
    args=parser.parse_args(); records=sources()
    for slug in args.only or sorted(records):
        if args.install_reviewed: install(slug)
        else: build(slug,records[slug])

if __name__=='__main__': main()
