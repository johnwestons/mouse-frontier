"""Inspection ownership, fog-safe effects, local panels and GPU release."""
import unittest
from tools.tests import test_coop_battles_behavior as fixtures


class NativePresentationTests(unittest.TestCase):
    def setUp(self):
        fixture=fixtures.TacticalCommandTests();fixture.setUp();self.lua=fixture.lua
        self.lua.execute('''
            assert(begin().ok);b=ready()
            Presentation=require('game.battle_presentation');Fog=require('game.battle_fog')
            ctx={battle=b,saveData=data,scenery={}}
        ''')

    def test_details_use_inspected_owners_resources_and_all_conditions(self):
        self.lua.execute(r'''
            local guest=b.units[2];guest.guarding=true;guest.bleedRounds=2;guest.regenRounds=3
            local lines=table.concat(Presentation.details(ctx,guest),'\n')
            assert(lines:find('BLEED 2',1,true)and lines:find('REGEN 3',1,true)and lines:find('GUARD',1,true))
            assert(lines:find('AMMO 9',1,true)and not lines:find('AMMO 20',1,true),'inspection used host ammo')
            assert(host.ammo['22lr']==20 and data.players.companion.ammo['22lr']==9)
            local hidden=Presentation.details(ctx,b.units[3])
            assert(#hidden==1 and hidden[1]=='Select a visible unit to inspect.')
        ''')

    def test_projectiles_use_authored_atlas_and_disappear_outside_party_sight(self):
        self.lua.execute('''
            local quad={};local image={};ctx.scenery.projectiles={image=image,w=64,h=32,quads={quad,quad,quad,quad,quad}}
            b.projectile={fromQ=1,fromR=3,toQ=3,toR=3,ammo='arrows',t=.5,duration=1}
            local p=assert(Presentation.projectile(ctx));assert(p.image==image and p.quad==quad and p.x==2.5)
            local camera=require('game.battle_camera').new();camera:configure({x=0,y=0,w=960,h=540})
            local drawn=0;local renderer={camera=camera,stats={},drawSprite=function(_,im,q,x,y,z,w,h,tint,options)
                assert(im==image and q==quad and options.centered and options.rotation==options.rotation);drawn=drawn+1
            end}
            assert(Presentation.drawProjectile(ctx,renderer)and drawn==1 and renderer.stats.projectiles==1)
            b.projectile.fromQ=60;b.projectile.toQ=62
            assert(not Presentation.projectile(ctx)and not Presentation.drawProjectile(ctx,renderer)and drawn==1)
        ''')

    def test_target_cell_is_not_stolen_by_an_overhanging_friendly_sprite(self):
        self.lua.execute('''
            local fixture=require('tools.tests.lua.native_battle_ui_fixture');fixture.install()
            package.loaded['game.battle_native_ui']=nil;local Native=require('game.battle_native_ui')
            local ui={};fixture.prepare(ui,b,data);ctx.ui=ui
            b.units[3].q,b.units[3].r=2,3;b.phase='target';b.chosenWeapon='scratch'
            local x,y=Native.project(ctx,2,3)
            ui.nativeBattle.unitHits={{unit=b.units[1],x=x-20,y=y-20,w=40,h=40,depth=1}}
            local resolved;ctx.resolveBattleAttack=function(_,target)resolved=target end
            Native.handleMouse(ctx,x,y,false);assert(resolved==b.units[3],'friendly sprite swallowed the attack target')
        ''')

    def test_panel_focus_and_release_are_local_and_idempotent(self):
        self.lua.execute('''
            local fixture=require('tools.tests.lua.native_battle_ui_fixture');fixture.install()
            package.loaded['game.battle_native_ui']=nil;local Native=require('game.battle_native_ui')
            local ui={};fixture.prepare(ui,b,data);local state=ui.nativeBattle;local releases=0
            state.renderer.release=function()releases=releases+1 end
            local revision=data.coop.revision;b.selected=b.units[3].id
            Native.cameraAction(ui,b,'focus')
            assert(state.renderer.camera.targetX==b.units[1].q+.5,'focus exposed a hidden enemy')
            Native.cameraAction(ui,b,'info');assert(state.panel=='info')
            Native.cameraAction(ui,b,'log');assert(state.panel=='log')
            Native.cameraAction(ui,b,'panelClose');assert(not state.panel)
            assert(data.coop.revision==revision and not b.panel)
            Native.release(ui);Native.release(ui);assert(releases==1 and not ui.nativeBattle)
        ''')


if __name__=='__main__':unittest.main()
