"""Save-window focus, authored train motion and texture lifetime regressions."""
from collections import Counter
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from tools.tests.test_lazy_scene_asset_loading import AllocationProbe


class TitleSlotTrainTests(unittest.TestCase):
    def test_only_the_focused_train_animates_and_unfocus_restores_a_still_train(self):
        self.lua.execute('''
            local Train=require('game.cinematic_train');local oldDraw=Train.draw
            local phases={};Train.draw=function(_,x,y,scale,clock)phases[#phases+1]={x=x,clock=clock}end
            -- The initial pointer is outside all save rows and no slot has
            -- been selected: normal title state on a touchscreen.
            ui.updateSlots(.05);ui.drawSlots()
            assert(ui.titleSlotTrains.focused==nil and #phases==3)
            local first=phases;phases={}
            ui.updateSlots(.1);ui.drawSlots()
            assert(#phases==3)
            for i=1,3 do
                assert(phases[i].clock==0 and first[i].clock==0,'unfocused train '..i..' animated')
                assert(phases[i].x==first[i].x,'idle train drifted out of its save card')
            end
            ui.keyboardFocusVisible=true;ui.keyboardFocusScreen='title-slots';ui.keyboardFocusId='slot.2.continue'
            for i=1,3 do ui.updateSlots(.1)end
            phases={};ui.drawSlots()
            assert(#phases==3 and phases[1].clock==0 and phases[2].clock>0 and phases[3].clock==0,
                'only the focused control may play train motion')
            ui.keyboardFocusVisible=false;ui.updateSlots(.01);phases={};ui.drawSlots()
            assert(#phases==3 and ui.titleSlotTrains.rows[2].amount==0)
            for i=1,3 do
                assert(phases[i].clock==0 and phases[i].x==first[i].x,'motion continued after unfocus')
            end
            ui.menuSettings={accessibility={reducedMotion=true}};phases={}
            ui.updateSlots(.1);ui.drawSlots()
            for i=1,3 do assert(phases[i].clock==0,'reduced motion still animated a parked train')end
            Train.draw=oldDraw
        ''')

    def setUp(self):
        self.probe=AllocationProbe()
        self.lua=self.probe.lua
        self.lua.execute('''
            Trains=require('game.title_slot_trains')
            runtime.state='slots';runtime.saveData=nil
            ui=screens();mouseX,mouseY=0,0
            love.mouse.getPosition=function()return mouseX,mouseY end
        ''')

    def test_shader_clip_matches_screen_and_canvas_pixel_density(self):
        self.lua.execute('''
            local g=love.graphics;local uniforms={}
            g.newShader=function()return {send=function(_,key,value)uniforms[key]=value end}end
            g.transformPoint=function(x,y)return 120+x*.5,40+y*.5 end
            local rect={x=90,y=215,w=780,h=126}
            local function check(dpi,target)
                g.getCanvas=function()return target end
                Trains.draw(Trains.new(),1,rect,455,scenery)
                local x,y=g.transformPoint(rect.x+77,rect.y+36)
                local dx,dy=x*dpi-uniforms.clipOrigin[1],y*dpi-uniforms.clipOrigin[2]
                local px=dx*uniforms.clipInverseX[1]+dy*uniforms.clipInverseX[2]
                local py=dx*uniforms.clipInverseY[1]+dy*uniforms.clipInverseY[2]
                assert(math.abs(px-77)<.00001 and math.abs(py-36)<.00001,
                    'framebuffer pixels were clipped as graphics units')
            end
            g.getDPIScale=function()return 1 end;check(1)
            g.getDPIScale=function()return 2.625 end;check(2.625)
            check(3,{getDPIScale=function()return 3 end})
        ''')

    def test_train_leaves_once_and_waits_for_unfocus_and_refocus(self):
        self.lua.execute('''
            local state=Trains.new();local row=state.rows[1]
            local rect={x=210,y=225,w=540,h=96}
            local start=Trains.position(row,rect,605)
            assert(start==605)
            Trains.update(state,.1,1,false)
            local moving=Trains.position(row,rect,605)
            assert(moving<start,'the left-facing locomotive must travel left')
            row.elapsed=Trains.travelSeconds
            local finish,rail,scale=Trains.position(row,rect,605)
            assert(finish+require('game.cinematic_train').rearExtent(scale)<rect.x)
            for frame=1,1200 do Trains.update(state,1/60,1,false)end
            assert(row.elapsed==Trains.travelSeconds and Trains.position(row,rect,605)==finish,
                'a focused train must stay off screen after it leaves')
            Trains.update(state,.02,nil,false);Trains.update(state,.02,1,false)
            assert(row.elapsed==.02 and Trains.position(row,rect,605)>moving,
                'unfocus and refocus must start a fresh departure')
        ''')

    def test_keyboard_focus_wins_over_stationary_pointer_and_same_row_does_not_restart(self):
        self.lua.execute('''
            mouseX,mouseY=600,250
            ui.keyboardFocusVisible=true;ui.keyboardFocusScreen='title-slots';ui.keyboardFocusId='slot.2.continue'
            ui.updateSlots(.1);assert(ui.titleSlotTrains.focused==2)
            local row=ui.titleSlotTrains.rows[2];local previous=row.elapsed
            ui.keyboardFocusId='slot.2.new';ui.updateSlots(.1)
            assert(row.elapsed>previous,'moving to New in the same row restarted the train')
            row.elapsed=Trains.travelSeconds;ui.keyboardFocusId='slot.2.delete';ui.updateSlots(.1)
            assert(row.elapsed==Trains.travelSeconds,'changing buttons in a completed row replayed the train')
            ui.keyboardFocusId='slot.3.delete';ui.updateSlots(.05)
            assert(ui.titleSlotTrains.focused==3 and ui.titleSlotTrains.rows[3].elapsed==.05)
            previous=row.elapsed;ui.updateSlots(.1);assert(row.elapsed==previous,'unfocused train kept moving')
            ui.keyboardFocusVisible=false;ui.updateSlots(.1)
            assert(ui.titleSlotTrains.focused==1,'pointer did not take over focus')
        ''')

    def test_selection_empty_slots_modals_and_reduced_motion(self):
        self.lua.execute('''
            ui.titleSelectedSlot=3;ui.updateSlots(.1)
            assert(ui.titleSlotTrains.focused==3)
            ui.menuSettings={accessibility={reducedMotion=true}}
            for frame=1,30 do ui.updateSlots(1/60)end
            assert(ui.titleSlotTrains.rows[3].elapsed==0 and ui.titleSlotTrains.rows[3].amount==1)
            runtime.pendingConfirmation={};ui.updateSlots(.1)
            assert(ui.titleSlotTrains.focused==nil)
            runtime.pendingConfirmation=nil;ui.resetSlotTrains()
            assert(ui.titleSelectedSlot==nil and ui.titleSlotTrains.rows[3].elapsed==0)
        ''')

    def test_mobile_car_resizing_preserves_coupling_and_consist_width(self):
        self.lua.execute('''
            local Train=require('game.cinematic_train');local calls={}
            local original=love.graphics.draw
            love.graphics.draw=function(image,x,y,rotation,sx,sy,ox,oy)
                calls[#calls+1]={left=x-ox*sx,right=x+(image:getWidth()-ox)*sx}
            end
            local function cars(width,height)
                return {getWidth=function()return width end,getHeight=function()return height end}
            end
            Train.draw({introCars=cars(2172,724)},605,300,.42,0)
            Train.draw({introCars=cars(2048,683)},605,300,.42,0)
            assert(math.abs(calls[1].left-calls[2].left)<.001)
            assert(math.abs(calls[1].right-calls[2].right)<.001)
            love.graphics.draw=original
        ''')

    def test_real_title_render_keeps_shared_train_images_warm_and_releases_on_exit(self):
        self.lua.execute('''
            mouseX,mouseY=600,250;ui.updateSlots(.1);ui.drawSlots()
            trainBackground=scenery.introBackground
            for frame=1,180 do
                Assets.releaseIntroImages(scenery,runtime)
                ui.updateSlots(1/60);ui.drawSlots()
            end
            assert(trainBackground.releases==0)
            runtime.state='characters';Assets.releaseIntroImages(scenery,runtime)
            assert(trainBackground.releases==1)
        ''')
        counts=Counter(path for kind,path in self.probe.events if kind=='texture')
        for path in ('assets/backgrounds/intro/train-journey-sunrise.png',
                     'assets/sprites/train/cinematic-locomotive-run-10-v2.png',
                     'assets/sprites/train/cinematic-five-car-consist.png'):
            self.assertEqual(counts[path],1,path+' was reloaded while browsing save slots')

    def test_slot_paint_colors_apply_only_to_existing_train_sprites(self):
        self.lua.execute('''
            local originalShader,originalDraw=love.graphics.newShader,love.graphics.draw
            local hue;local colored={};local backgrounds=0
            love.graphics.newShader=function(source)
                local shader=originalShader(source);local send=shader.send
                shader.send=function(self,name,value)
                    if name=='paintTone' then hue=value[1] end
                    return send(self,name,value)
                end
                return shader
            end
            love.graphics.draw=function(image,...)
                if image.path:find('/intro/train%-journey') then
                    assert(hue==-1,'slot tint leaked into scenery');backgrounds=backgrounds+1
                elseif image.path:find('/train/cinematic%-') then
                    colored[hue]=true
                end
                return originalDraw(image,...)
            end
            ui.drawSlots()
            assert(backgrounds==3 and colored[-1] and colored[.582] and colored[.215],
                'red, blue and green slots must reuse the train sprite sheets')
            love.graphics.newShader=originalShader;love.graphics.draw=originalDraw
        ''')


if __name__=='__main__':
    unittest.main()
