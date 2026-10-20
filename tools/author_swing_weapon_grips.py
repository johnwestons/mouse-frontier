"""Convert reviewed weapon-catalog grip/tip landmarks into normalized runtime data."""
import json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# Pixel landmarks in each 250x300 review tile: actual grip and shaft-tip vector.
POINTS={
 'brass-knuckle-duster':(122,204,122,133,24),
 'train-wrench':(407-250,207,326-250,108,48),
 'salvage-pry-bar':(590-500,202,679-500,100,48),
 'scrap-hatchet':(839-750,200,891-750,116,46),
 'rusty-cleaver':(77,490-300,168,405-300,44),
 'frontier-short-sword':(322-250,509-300,438-250,382-300,50),
 'patched-trench-knife':(584-500,510-300,685-500,397-300,34),
 'scrap-hunting-spear':(857-750,487-300,949-750,382-300,72),
 'salvaged-track-hatchet':(75,797-600,153,693-600,46),
 'miners-pick':(368-250,799-600,368-250,712-600,46),
 'gear-hammer':(583-500,795-600,660-500,709-600,46),
 'rail-spike-spear':(830-750,816-600,940-750,674-600,72),
 'gear-toothed-falchion':(67,210,206,79,50),
 'frontier-fork-trident':(333-250,198,421-250,94,72),
 'gearwright-bearded-axe':(579-500,203,661-500,110,48),
 'chain-flail':(830-750,179,866-750,115,50),
 'rail-spike-dagger':(83,490-300,190,398-300,34),
 'frontier-hook-sickle':(336-250,503-300,388-250,441-300,45),
 'frontier-curved-saber':(688-500,530-300,598-500,439-300,52),
 'steam-shock-baton':(831-750,499-300,928-750,405-300,46),
 'railway-cutlass':(66,817-600,207,671-600,52),
 'hooked-railway-halberd':(334-250,781-600,435-250,652-600,72),
 'rail-splitter-axe':(557-500,806-600,653-500,689-600,54),
 'frontier-katana':(940-750,828-600,832-750,722-600,56),
 'frontier-mace':(61,210,166,105,52),
 'frontier-battle-axe':(436-250,207,350-250,108,56),
 'frontier-longsword':(677-500,203,571-500,90,56),
 'frontier-machete':(786-750,211,950-750,116,50),
 'frontier-spear':(153,473-300,39,399-300,72),
 'frontier-hatchet':(449-250,505-300,327-250,410-300,46),
 'frontier-hand-axe':(598-500,488-300,669-500,422-300,46),
 'frontier-cavalry-saber':(939-750,527-300,828-750,402-300,52),
 'boiler-smith-maul':(87,786-600,153,715-600,58),
 'railway-war-pick':(315-250,787-600,390-250,702-600,52),
 'brass-backed-greatsword':(553-500,821-600,704-500,671-600,58),
 'wasteland-partisan':(824-750,780-600,936-750,662-600,72),
 'frontier-executioner-axe':(58,202,151,101,58),
}
sources=json.loads((ROOT/'output/character-swings/weapons/sources.json').read_text())
records={}; lines=['-- Reviewed grip and native shaft vector for each equipped melee sprite.','return {']
for name,(gx,gy,tx,ty,length) in POINTS.items():
    w,h=sources[name]['cell'][2:]; scale=min(230/w,260/h); dw,dh=round(w*scale),round(h*scale)
    ox,oy=(250-dw)//2,30+(260-dh)//2
    x,y=(gx-ox)/dw,(gy-oy)/dh
    angle=math.atan2(ty-gy,tx-gx)
    records[name]={'x':x,'y':y,'angle':angle,'length':length,'source':sources[name]}
    lines.append(' ["%s"]={x=%.8f,y=%.8f,angle=%.8f,length=%d},'%(name,x,y,angle,length))
lines+=['}','']
(ROOT/'character-motion/swings/weapon-grips.json').write_text(json.dumps(records,indent=2)+'\n')
(ROOT/'game/melee_weapon_grips.lua').write_text('\n'.join(lines))
