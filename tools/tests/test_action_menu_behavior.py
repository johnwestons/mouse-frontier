"""Real menu/editor hit geometry, pointer ownership, and preset persistence."""
import unittest
import test_player_ui_editor_behavior as editor_fixture


@unittest.skipIf(editor_fixture.LuaRuntime is None, 'Lua 5.1 runtime unavailable')
class ActionMenuTests(unittest.TestCase):
    def setUp(self):
        editor_fixture.PlayerUIEditorBehaviorTests.setUp(self)
        self.lua.execute('''
            local noop=function() end
            package.loaded['game.action_menu']=nil
            package.loaded['game.action_menu_art']={frame=noop,icon=noop,wheel=noop,image=function()
                return {getWidth=function() return 1254 end,getHeight=function() return 1254 end}
            end}
            love.graphics.stencil=function(fn) fn() end
            love.graphics.polygon=noop;love.graphics.setStencilTest=noop;love.graphics.draw=noop
            Menu=require('game.action_menu');count=0;allowed=true;hudRight=810
            menu=Menu.new({actions=function() return {travel={enabled=allowed,reason='Stop first',run=function()count=count+1;return true end}} end,
                rightHudX=function() return hudRight end})
            function drawMenu(canvas)
                manager:beginFrame();menu:draw(canvas or {left=0,top=0,right=960,bottom=720})
            end
            function target(id)
                for _,t in ipairs(menu.targets) do if t.id==id then
                    for row=1,19 do for col=1,19 do local x,y=t.rect.x+t.rect.w*col/20,t.rect.y+t.rect.h*row/20
                        if t.rect:contains(x,y) then return x,y,t.rect end
                    end end
                end end;error('missing target '..id)
            end
            drawMenu()
        ''')

    def test_tap_release_cancellation_and_multitouch(self):
        self.lua.execute('''
            local x,y=target('travel');assert(menu:press('a',x,y));assert(count==0)
            assert(menu:press('b',x,y));assert(menu:release('b',x,y));assert(count==0)
            assert(menu:release('a',x,y));assert(count==1)
            drawMenu();x,y=target('travel');menu:press('a',x,y);menu:release('a',0,0);assert(count==1)
            menu:press('a',x,y);menu:hide();assert(menu:release('a',x,y));assert(count==1)
        ''')

    def test_fresh_permissions_and_stale_page_release(self):
        self.lua.execute('''
            local x,y=target('travel');menu:press('a',x,y);allowed=false;menu:release('a',x,y)
            assert(count==0 and menu.notice=='Stop first')
            allowed=true;menu:press('a',x,y);menu:setPage('poses');drawMenu();menu:release('a',x,y);assert(count==0)
        ''')

    def test_nested_edited_controls_follow_transforms(self):
        self.lua.execute('''
            manager:set('actions_dock_dock',{x=-50,y=-80,scale=1.2,rotation=12},false)
            manager:set('actions_dock_dock_travel',{x=25,y=-30,scale=.8,rotation=37},false)
            drawMenu();local x,y,r=target('travel')
            assert(not r:contains(r.x+.1,r.y+.1),'AABB corner must not activate rotated button')
            menu:press('a',x,y);menu:release('a',x,y);assert(count==1)
        ''')

    def test_wheel_hole_and_slices_have_distinct_hits(self):
        self.lua.execute('''
            manager:setMenuLayout('radial',false);drawMenu();menu:setPage('main');drawMenu()
            for _,id in ipairs({'poses','leave','travel','backpack','map','more'}) do
                local x,y=target(id);local found=menu:at(x,y);assert(found.id==id)
            end
            local x,y=target('close');assert(menu:at(x,y).id=='close')
            assert(menu:key('escape') and not menu.page)
        ''')

    def test_controls_and_drawer_tiles_share_clean_aligned_geometry(self):
        self.lua.execute('''
            local function closeTo(actual,expected)
                assert(math.abs(actual-expected)<.000001,tostring(actual)..' ~= '..tostring(expected))
            end
            for _,layout in ipairs({'dock','drawer','radial'}) do
                manager:setMenuLayout(layout,false);menu.lastLayout=layout;menu:setPage(nil);drawMenu()
                local controls={}
                for _,id in ipairs(layout=='dock' and {'poses','leave','travel','backpack','more'} or {'backpack','launcher'}) do
                    local _,_,r=target(id);controls[#controls+1]=r
                    assert(r.w==60 and r.h==50,'bottom controls use one touch size')
                    assert(r.y==604,'bottom controls share one baseline')
                end
                for i=2,#controls do
                    closeTo(controls[i].x-(controls[i-1].x+controls[i-1].w),5)
                end
                closeTo(controls[#controls].x+controls[#controls].w,759)
                if layout=='drawer' then
                    menu:setPage('main');drawMenu()
                    local _,_,first=target('poses');local _,_,second=target('leave')
                    assert(first.w==96 and first.h==50 and second.w==96 and second.h==50)
                    closeTo(second.x-(first.x+first.w),8)
                    closeTo(first.y,second.y)
                    closeTo(second.x+second.w,755)
                    local _,_,close=target('close')
                    assert(close.w==60 and close.h==36,'panel close button remains compact')
                end
            end
            hudRight=970;manager:setMenuLayout('drawer',false);menu.lastLayout='drawer';menu:setPage(nil)
            drawMenu({left=-160,top=0,right=1120,bottom=720})
            local _,_,pack=target('backpack');local _,_,actions=target('launcher')
            closeTo(actions.x+actions.w,919,'controls stop before the wide-screen objective gutter')
            assert(pack.w==60 and actions.w==60 and pack.y==actions.y)
            hudRight=nil;drawMenu()
            local _,_,compactActions=target('launcher')
            closeTo(compactActions.x+compactActions.w,942,'compact screen uses its available width')
        ''')

    def test_action_menu_can_preserve_hud_without_unpausing_other_modals(self):
        self.lua.execute('''
            local Pause=require('game.world_pause')
            local runtime={state='game'};local ui={mobileMenuOpen=true};local maintenance={}
            assert(Pause.isPaused(runtime,ui,maintenance),'action menu still pauses gameplay by default')
            assert(not Pause.isPaused(runtime,ui,maintenance,{allowActionMenu=true}),
                'HUD-only allowance did not exclude the action menu pause')
            ui.optionsOpen=true
            assert(Pause.isPaused(runtime,ui,maintenance,{allowActionMenu=true}),
                'action-menu allowance must not bypass other modal screens')
            ui.optionsOpen=nil;runtime.inventoryOpen=true
            assert(Pause.isPaused(runtime,ui,maintenance,{allowActionMenu=true}),
                'action-menu allowance must not bypass inventory')
        ''')

    def test_independent_presets_round_trip_and_undo(self):
        self.lua.execute('''
            local before=manager:snapshotSlot();manager:setMenuLayout('drawer',false)
            manager:set('actions_drawer_main_travel',{x=38,rotation=17},false)
            local edited=manager:snapshotSlot();manager:restoreSlot(before,false);assert(manager:menuLayout()=='dock')
            manager:restoreSlot(edited,false);manager:save()
            manager:useSlot(2);assert(manager:menuLayout()=='dock');manager:setMenuLayout('radial');manager:useSlot(1)
            local restored=UIStyle.new({filesystem=fs,screen=function()return 'game_train'end})
            assert(restored:menuLayout()=='drawer' and restored:get('actions_drawer_main_travel').rotation==17)
            restored:useSlot(2);assert(restored:menuLayout()=='radial')
        ''')

    def test_packed_action_atlases_keep_authored_icon_and_wheel_bounds(self):
        self.lua.execute('''
            local noop=function() end;local captured={}
            love.graphics.newImage=function()
                return {setFilter=noop,getDimensions=function()return 1024,1024 end}
            end
            love.graphics.newQuad=function(...)captured.quad={...};return captured.quad end
            love.graphics.draw=function(...)captured.draw={...}end
            love.graphics.setColor=noop
            package.loaded['game.action_menu_art']=nil
            local Art=require('game.action_menu_art');local factor=1024/1254
            Art.icon('idle',10,20,40)
            assert(math.abs(captured.quad[1]-681*factor)<.000001,'packed icon x crop is not scaled')
            assert(math.abs(captured.quad[2]-372*factor)<.000001,'packed icon y crop is not scaled')
            assert(math.abs(captured.quad[3]-188*factor)<.000001,'packed icon width is not scaled')
            assert(math.abs(captured.quad[4]-247*factor)<.000001,'packed icon height is not scaled')
            assert(math.abs(captured.draw[6]-40/(247*factor))<.000001,'packed glyph rendered at a different size')
            Art.wheel('poses',10,20,120)
            assert(math.abs(captured.draw[5]-240/(1058*factor))<.000001,'packed wheel rendered at a different size')
            assert(math.abs(captured.draw[7]-626*factor)<.000001,'packed wheel origin x is not scaled')
            assert(math.abs(captured.draw[8]-622*factor)<.000001,'packed wheel origin y is not scaled')
        ''')

    def test_editor_drags_actual_menu_child_and_undo_restores(self):
        self.lua.execute('''
            ui.uiPanel.x=4;ui.uiPanel.y=4;ui.uiPanel.collapsed=true
            drawMenu();ui:draw()
            local x,y=target('travel');ui:press(x,y,1)
            assert(ui.uiElement=='actions_dock_dock_travel' and ui.uiDrag)
            ui:move(x-90,y-60);ui:finishDrag()
            assert(manager:get(ui.uiElement).x==-90 and manager:get(ui.uiElement).y==-60)
            ui:undoUi(false);assert(manager:get(ui.uiElement).x==0)
        ''')

    def test_debug_guards_and_failed_provisioning_leave_save_untouched(self):
        self.lua.execute('''
            package.loaded['game.player_tools_model']=nil
            local runtime={state='game',session={networkMode='offline'}}
            local service=require('game.debug_activities').new({runtime=runtime,ui={},
                controller={isClient=function()return false end},catalog=require('game.catalog')})
            assert(not service:available())
            local data={inventory={'a','b','c','d','e','f'},inventoryCapacity=6,health=2,maxHealth=20,
                resources={food=1},ammo={},scrap=0,scene='house',location=8,activeCar=1}
            runtime.saveData=data;runtime.selectedSlot=1
            runtime.session.networkMode='host';assert(not service:available())
            local ok=service:launch('range',true);assert(not ok and runtime.saveData==data)
            runtime.session.networkMode='offline';assert(service:available())
            assert(not service:launch('unknown',true))
            local ok,reason=service:launch('range',true)
            assert(not ok and reason:match('backpack'))
            assert(data.health==2 and data.scrap==0 and data.scene=='house' and data.resources.food==1)
            runtime.session.checkpointPending=true;assert(not service:available())
        ''')


if __name__ == '__main__':
    unittest.main()
