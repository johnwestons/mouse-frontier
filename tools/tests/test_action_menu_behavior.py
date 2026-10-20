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
            Menu=require('game.action_menu');count=0;allowed=true
            menu=Menu.new({actions=function() return {travel={enabled=allowed,reason='Stop first',run=function()count=count+1;return true end}} end})
            function drawMenu()
                manager:beginFrame();menu:draw({left=0,top=0,right=960,bottom=720})
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
