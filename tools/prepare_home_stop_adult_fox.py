"""Pack reviewed adult poses; never repaint or alter the source artwork.

One scale is shared by every pose in each strip. Contact points are aligned
while the authored knee bend/arm swing remains in the image. Adult source art,
runtime cells and QA previews stay separate from the general character set.
"""
from pathlib import Path
import json
import shutil
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'art-source/home-stop/adult-tinker-fox'
RUNTIME=ROOT/'assets/sprites/home-stop/adult-tinker-fox'
REVIEW=ROOT/'output/home-stop-adult-motion-audit'
DIRECTIONS={'east':'','northeast':'_northeast','north':'_north','northwest':'_northwest',
            'west':'_west','southwest':'_southwest','south':'_south','southeast':'_southeast'}
SIZE,BASELINE,TARGET=512,458,385

def clean_detached_background(frame):
    pixels=np.array(frame.convert('RGBA'))
    mask=pixels[:,:,3]>16
    ys,xs=np.where(mask)
    center=np.array([np.median(ys),np.median(xs)])
    seed=int(np.argmin((ys-center[0])**2+(xs-center[1])**2))
    labels=Image.fromarray(np.uint8(mask)*255)
    ImageDraw.floodfill(labels,(int(xs[seed]),int(ys[seed])),128)
    main=np.asarray(labels)==128
    if main.sum()<=mask.sum()*.98:
        return frame  # Preserve any deliberately separated silhouette parts.
    my,mx=np.where(main)
    outside=np.ones(mask.shape,dtype=bool)
    outside[max(0,my.min()-2):my.max()+3,max(0,mx.min()-2):mx.max()+3]=False
    pixels[outside & ~main,3]=0
    return Image.fromarray(pixels)

def pack(frames,destination,normalize=True):
    boxes=[f.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox() for f in frames]
    assert all(boxes),destination
    scale=TARGET/float(np.median([b[3]-b[1] for b in boxes])) if normalize else SIZE/frames[0].height
    sheet=Image.new('RGBA',(SIZE*len(frames),SIZE))
    records=[]
    for index,(frame,box) in enumerate(zip(frames,boxes)):
        mask=np.asarray(frame.getchannel('A'))>16
        # Torso, rather than a swinging toe or tail tip, defines the X anchor.
        height=box[3]-box[1]
        _,xs=np.where(mask[box[1]+round(height*.45):box[1]+round(height*.70)])
        anchor=float(np.median(xs))
        sprite=frame.crop(box)
        sprite=sprite.resize((round(sprite.width*scale),round(sprite.height*scale)),Image.Resampling.LANCZOS)
        x=round(SIZE/2-(anchor-box[0])*scale)
        y=BASELINE-sprite.height
        assert x>=2 and x+sprite.width<=SIZE-2 and y>=2,(destination,index,x,y,sprite.size)
        sheet.alpha_composite(sprite,(index*SIZE+x,y))
        records.append({'source_box':list(box),'body_anchor':anchor,'scale':scale})
    sheet.save(destination,optimize=True)
    return records

def build():
    RUNTIME.mkdir(parents=True,exist_ok=True); REVIEW.mkdir(parents=True,exist_ok=True)
    imports={}; animations={}
    original=ROOT/'assets/sprites/character-animations/tinker-fox'
    for direction,suffix in DIRECTIONS.items():
        source=SOURCE/f'walk{suffix}-v1.png'
        image=Image.open(source).convert('RGBA')
        cutsX=[round(i*image.width/4) for i in range(5)]; cutsY=[round(i*image.height/2) for i in range(3)]
        frames=[clean_detached_background(image.crop((cutsX[col],cutsY[row],cutsX[col+1],cutsY[row+1]))) for row in range(2) for col in range(4)]
        filename=f'walk{suffix}.png'
        imports[filename]={'source':str(source.relative_to(ROOT)),'frames':pack(frames,RUNTIME/filename)}
        image=Image.open(original/f'idle{suffix}.png').convert('RGBA'); fw=image.width//2
        filename=f'idle{suffix}.png'
        imports[filename]={'source':str((original/filename).relative_to(ROOT)),
                          'frames':pack([image.crop((i*fw,0,(i+1)*fw,image.height)) for i in range(2)],RUNTIME/filename)}
        for action,count,role,fps in [('walk',8,'gait',10.35),('idle',2,'directional_idle',.65)]:
            animations[f'{action}_{direction}']={'path':str((RUNTIME/f'{action}{suffix}.png').relative_to(ROOT)).replace('\\','/'),
                'frame_width':SIZE,'frame_height':SIZE,'frame_count':count,'loop':True,'role':role,'fps':fps}
    carry=Image.open(original/'carry.png').convert('RGBA'); fw=carry.width//4
    imports['crates.png']={'source':str((original/'carry.png').relative_to(ROOT)),
                          'frames':pack([carry.crop((i*fw,0,(i+1)*fw,carry.height)) for i in range(4)],RUNTIME/'crates.png',normalize=False)}
    for action,source in [('wrench','tinker-wrench-runtime.png'),('oil','tinker-oil-west-runtime.png')]:
        path=ROOT/'assets/sprites/home-stop'/source
        shutil.copy2(path,RUNTIME/f'{action}.png')
        imports[f'{action}.png']={'source':str(path.relative_to(ROOT)),'unchanged_pixels':True}
    for action in ['crates','wrench','oil']:
        animations[action]={'path':str((RUNTIME/f'{action}.png').relative_to(ROOT)).replace('\\','/'),
            'frame_width':SIZE,'frame_height':SIZE,'frame_count':4,'loop':True,'role':'task_action','fps':4}
    spec={'version':1,'character':'home-tinker-fox','animations':animations,
        'directions':{name:{'walk_animation':'walk_'+name,'idle_animation':'idle_'+name,'mirror_x':False} for name in DIRECTIONS},
        'gait':{'pose_order':['left_contact','left_weight_down','right_passing','right_knee_up','right_contact','right_weight_down','left_passing','left_knee_up'],
                'pixels_per_frame':5.6,'base_speed':58,'speed_multipliers':[.96,.94,1.04,1.06]*2,
                'acceleration_multipliers':[.92,.90,1.08,1.10]*2},
        'audit':{'alpha_threshold':16,'edge_margin':2,'detached_component_ratio':.003,'baseline_tolerance':10,'center_tolerance':18},
        'source_notes':{'identity':'Adult tinker-fox idle and carry references; eight repaired authored walk views. No young-tinker-fox or Picture Shop worker frames.',
                        'framing':{'cell':SIZE,'foot_baseline':BASELINE,'standing_height':TARGET,'body_world_size':82,
                            'runtime_scale':'body_world_size / decoded frame height for every action; no cross-strip extent normalization',
                            'mobile_cells':'All 19 strips use characterAnimationFrameSize with isolated frame resizing.'},
                        'prompts':'docs/home-stop-adult-fox-prompts.txt'}}
    (ROOT/'character-motion/home-tinker-fox.json').write_text(json.dumps(spec,indent=2)+'\n',encoding='utf-8')
    (REVIEW/'import-report.json').write_text(json.dumps(imports,indent=2)+'\n',encoding='utf-8')
    # One comparison at actual runtime scale, on contrasting backgrounds.
    for background,label in [('#ffffff','light'),('#822655','pink')]:
        contact=Image.new('RGB',(8*160,3*140),background); draw=ImageDraw.Draw(contact)
        for col,(direction,suffix) in enumerate(DIRECTIONS.items()):
            for row,action in enumerate(['idle','walk']):
                image=Image.open(RUNTIME/f'{action}{suffix}.png').convert('RGBA').crop((0,0,SIZE,SIZE)).resize((104,104))
                contact.paste(image,(col*160+28,row*140+26),image); draw.text((col*160+5,row*140+5),action+' '+direction,fill='#111111')
        for col,action in enumerate(['crates','wrench','oil']):
            image=Image.open(RUNTIME/f'{action}.png').convert('RGBA').crop((0,0,SIZE,SIZE)).resize((104,104))
            contact.paste(image,(col*160+28,306),image); draw.text((col*160+5,285),action,fill='#111111')
        contact.save(REVIEW/f'adult-states-{label}.png')
    print('ADULT_FOX_IMPORT_OK: 8 authored walk views, 8 adult idles, 3 adult work strips')

if __name__=='__main__': build()
