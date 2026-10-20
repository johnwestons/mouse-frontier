"""Weapon swing routing, unarmed field combat and mirrored grip transforms."""
import os,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime

class SwingBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute("package.path=root..'/?.lua;'..package.path; love={math={random=function(a,b)return a end}}")

    def test_action_and_held_item_match_selected_weapon(self):
        self.lua.execute('''
          local A=require('game.character_attack'); local C=require('game.catalog')
          for name,combat in pairs(C.weaponCombat) do
            local expected=combat.kind=='ranged' and 'ranged' or ((name=='scratch' or name=='mob-claw') and 'melee' or 'swing')
            assert(A.action(name,combat)==expected,name)
          end
          assert(A.action(nil)=='melee' and A.heldItem('scratch')==nil and A.heldItem('mob-claw')==nil)
          assert(A.heldItem('train-wrench')=='train-wrench')
        ''')

    def test_stop_empty_hands_gun_only_broken_weapon_and_equipped_melee(self):
        self.lua.execute('''
          local S=require('game.stop_sludges'); local C=require('game.catalog')
          for _,equipment in ipairs({{}, {'frontier-22-pocket-pistol'}, {'train-wrench'}}) do
            local sys=S.new();local data={equipment=equipment,weaponDurability={}}
            local used;local ctx={data=data,location=1,player={x=0,y=0,facing=1},catalog=C,
              isWeapon=function(n)return C.weaponStats[n]~=nil end,onAction=function(n)used=n end}
            local mobs=S.ensure(sys,data,1,ctx);mobs[1].x,mobs[1].y=50,0
            assert(S.attack(sys,ctx,50,0));assert(used==(equipment[1]=='train-wrench' and 'train-wrench' or 'scratch'))
            assert(mobs[1].hp<mobs[1].maxHp)
            local hp=mobs[1].hp;assert(not S.attack(sys,ctx,50,0));assert(mobs[1].hp==hp)
            sys.attackTimer=0;data.equipment={'train-wrench'};data.weaponDurability['train-wrench']=0
            assert(S.attack(sys,ctx,-500,0));assert(used=='scratch')
          end
        ''')

    def test_unarmed_roaming_has_damage_cooldown_and_no_item_wear(self):
        self.lua.execute('''
          local R=require('game.roaming_mobs');local C=require('game.catalog')
          local sys=R.new();local data={equipment={},weaponDurability={},weaponProficiency={}}
          local mob={id='test',x=60,y=0};local state={mobs={test={x=60,y=0,hp=10,maxHp=10}}}
          local ctx={data=data,catalog=C,isWeapon=function(n)return C.weaponStats[n]~=nil end,
            area={id='test',mobs={mob}},areaState=state,player={x=0,y=0,facing=1}}
          local ok,reason,cue=R.attack(sys,ctx,60,0)
          assert(ok and cue.weapon=='scratch' and cue.damage==1 and state.mobs.test.hp==9)
          assert(next(data.weaponDurability)==nil and not R.attack(sys,ctx,60,0))
          sys.attackTimer=0;ctx.canReach=function()return false end
          assert(R.attack(sys,ctx,60,0));assert(state.mobs.test.hp==9)
        ''')

    def test_mobile_resizing_preserves_body_grip_and_weapon_size(self):
        self.lua.execute('''
          local A=require('game.character_animation');local W=require('game.weapon_attachment')
          local calls={};love.graphics={setColor=function()end,newQuad=function(...)return {...}end,
            draw=function(image,quad,x,y,r,sx,sy,ox,oy)calls[#calls+1]={x=x,y=y,r=r,sx=sx,sy=sy,ox=ox,oy=oy}end}
          love.filesystem={getInfo=function()return {type='directory'}end,
            getDirectoryItems=function()return {'botanist-frog'}end}
          local reference
          for _,h in ipairs({256,192,128}) do
            local manager=A.load('assets',function(path)return {getDimensions=function()return h*12,h end}end)
            local animation=manager['botanist-frog.png'].swing
            local sprite={image='weapon',quad='weapon',w=100,h=100}
            for frame=1,6 do
              calls={};local phase=(frame-.5)*.35/6
              assert(A.draw(manager,'botanist-frog.png','swing',100,200,82,104,-1,phase,phase))
              assert(W.draw(manager,'botanist-frog.png','train-wrench',sprite,100,200,82,104,-1,phase,'swing',{}))
              local body,weapon=calls[1],calls[2]
              local actual={body.x-body.ox*body.sx,body.y-body.oy*body.sy,body.sx*h,
                weapon.x,weapon.y,weapon.r,weapon.sx,weapon.sy,weapon.ox,weapon.oy}
              if h==256 then reference=reference or {};reference[frame]=actual
              else for i,value in ipairs(actual)do assert(math.abs(value-reference[frame][i])<1e-6,'mobile transform changed')end end
            end
          end
        ''')

    def test_each_frame_uses_authored_hand_and_tip_vector_in_both_facings(self):
        self.lua.execute('''
          local A=require('game.character_animation'); local W=require('game.weapon_attachment')
          local G=require('game.melee_weapon_grips');local p=require('game.character_swing_profiles')
          local points={{x=.4,y=.6,side=1,angle=-1},{x=.3,y=.4,side=1,angle=-2.5},
            {x=.45,y=.1,side=1,angle=-1.7},{x=.7,y=.5,side=1,angle=.2},
            {x=.7,y=.8,side=1,angle=1},{x=.4,y=.6,side=1,angle=-1}}
          local animation={image='body',quads={1,2,3,4,5,6},count=6,w=512,h=256,
            bodyExtent=256,handPoints=points,playback=p.actions.swing}
          local sets={['test.png']={swing=animation,baseExtent=512}}
          local calls={};love.graphics={setColor=function()end,newQuad=function()return 'patch'end,
            draw=function(image,quad,x,y,r,sx,sy,ox,oy)calls[#calls+1]={image=image,x=x,y=y,r=r,sx=sx,sy=sy,ox=ox,oy=oy}end}
          local sprite={image='weapon',quad='weapon',w=100,h=100}
          for name,grip in pairs(G) do for _,facing in ipairs({-1,1}) do for frame=1,6 do
            calls={};local phase=(frame-.5)*.35/6
            assert(A.actionFrame(animation,phase)==frame)
            assert(W.draw(sets,'test.png',name,sprite,100,200,82,104,facing,phase,'swing',{}))
            local c=calls[1];local hand=points[frame]
            assert(math.abs(c.x-(100+(hand.x*512-256)*82/256*facing))<1e-6)
            assert(math.abs(c.y-(200+(hand.y*256-256)*82/256))<1e-6)
            assert(math.abs(c.r-facing*(hand.angle-grip.angle))<1e-6)
            assert(c.sx*facing>0 and c.sy>0 and c.ox==grip.x*100 and c.oy==grip.y*100)
            assert(calls[2].image=='body','grip must be covered by the authored fingers')
          end end end
        ''')

if __name__=='__main__':unittest.main()
