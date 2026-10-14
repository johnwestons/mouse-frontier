"""Read-only model/render prototype acceptance; never launches the game."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class JourneyPanelsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            Panels=require('game.coop_guest_journey_panels')
            F=require('tools.tests.lua.coop_fixtures');State=require('game.net.game_state')
            Help=require('game.help_quest_session');Entities=require('game.coop_entities')
            Codec=require('game.net.codec');Records=require('game.net.state_records')
            data=F.campaign(6,{scene='stop',visitedStops={[1]=true,[6]=true}});assert(F.enroll(data))
            function bytes(value)
                return assert(Codec.encode(assert(Records.encode(value,Records.budget())),
                    {maxBytes=524288,maxDepth=32,maxEntries=200000,maxStringBytes=4096}))
            end
            function projected()
                assert(Entities.ensure(data));return assert(State.project(data)).view
            end
            function renderContext(mobile)
                texts={};buttons={};local controls={}
                local g=setmetatable({getColor=function()return 1,1,1,1 end,getShader=function()return nil end},
                    {__index=function()return function()end end})
                love.graphics=g
                local colors={cream={1,1,1},red={1,0,0},ink={0,0,0},brass={1,.8,.4},blue={0,0,1},green={0,1,0}}
                return {controls=controls,colors=colors,mobileEnabled=function()return mobile end,
                    textBox=function(value,x,y,w,h)texts[#texts+1]={value=value,x=x,y=y,w=w,h=h}end,
                    button=function(value,x,y,w,h,enabled)
                        local b={value=value,x=x,y=y,w=w,h=h,enabled=enabled};buttons[#buttons+1]=b;return b end,
                    drawMenuFrame=function()end}
            end
        ''')

    def test_real_projection_trail_only_reveals_actual_visited_flags(self):
        self.lua.execute('''
            local view=projected();local before=bytes(view)
            local m=Panels.trail(view)
            assert(#m.points==2 and m.points[1].stop==1 and m.points[2].stop==6)
            assert(#m.segments==0 and m.current.stop==6 and m.location==6)
            assert(m.current[1]==805 and m.current[2]==215+math.sin(6*1.73)*42)
            m.points[1].stop=48;m.current.biome='changed'
            assert(bytes(view)==before and Panels.trail(view).points[1].stop==1)
        ''')

    def test_numeric_and_string_true_flags_but_no_truthy_or_generated_future_locations(self):
        self.lua.execute('''
            local input={location=6,visitedStops={[1]=true,['2']=true,[3]='true',[4]=1,[5]=false},
                stopLayouts={['49']={}},encounters={['49']={hasMob=true,resolved=false}}}
            local m=Panels.trail(input)
            assert(#m.points==2 and m.points[2].stop==2 and #m.segments==1)
            assert(not m.current and m.biome=='Unexplored stop' and m.status=='Unexplored stop')
            assert(m.maxScroll==0)
        ''')

    def test_missing_data_stays_empty_and_is_not_repaired(self):
        self.lua.execute('''
            local d={location=40};local before=bytes(d)
            local m=Panels.trail(d);local j=Panels.journal(d,'train')
            assert(#m.points==0 and m.scroll==0 and m.maxScroll==0 and not m.current)
            assert(#j.rows==0 and j.currentObjective=='No active objectives right now.')
            assert(bytes(d)==before and not d.helpQuestSessions and not d.visitedStops)
            assert(#Panels.trail(nil).points==0 and #Panels.journal(nil).rows==0)
        ''')

    def test_private_scroll_clamps_finite_bounds_and_does_not_change_route_or_saved_data(self):
        self.lua.execute('''
            local d={location=50,visitedStops={['50']=true}}
            assert(Panels.trail(d,-10).scroll==0 and Panels.trail(d,100).scroll==6)
            assert(Panels.trail(d,0/0).scroll==6 and Panels.trail(d,math.huge).scroll==6)
            assert(Panels.journal(d,'train',nil,-2).scroll==0)
            assert(Panels.journal(d,'train',nil,math.huge).scroll==0)
            assert(d.mapScroll==nil and d.journeyLogScroll==nil)
        ''')

    def accepted_tasks(self):
        self.lua.execute('''
            data.mailQuests={{origin=2,destination=8,recipient='crow-merchant.png',complete=false,
                letter='Do not expose this letter.'},{origin=2,destination=49,recipient='scout-frog.png',complete=true}}
            data.supplyQuests={{origin=3,destination=9,cargoKind='water',complete=false}}
            data.passengers={{npc='cook-mouse.png',origin=2,destination=10,job='medic'}}
            local offered=Help.ensure(data,{source='maintenance',location=6,npc='mechanic.png',
                title='SERVICE',objective='Inspect the mechanism.'})
            local accepted=Help.ensure(data,{source='first-aid',location=6,npc='medic.png',
                title='FIRST AID',objective='Continue the active task.'})
            assert(Help.accept(data,accepted.id));assert(Help.pause(data,accepted.id))
            acceptedId=accepted.id;offeredId=offered.id
        ''')

    def test_actual_projected_accepted_tasks_are_read_only_and_detached_without_offers_letters_or_rewards(self):
        self.accepted_tasks()
        self.lua.execute('''
            local view=projected();local before=bytes(view);local sourceBefore=bytes(State.project(data).encoded)
            Help.summary=function()error('mutating help summary invoked')end
            Help.ensureData=function()error('repair invoked')end
            require('game.expedition_areas').state=function()error('mutating area getter invoked')end
            local j=Panels.journal(view,'stop');assert(#j.rows==4)
            assert(j.rows[1].kind=='help' and not j.rows[1].active and j.rows[1].detail=='ACCEPTED  •  STEP 1 / 3')
            local encoded=bytes(j)
            assert(not encoded:find('Inspect the mechanism.',1,true))
            assert(not encoded:find('Do not expose this letter.',1,true))
            assert(not encoded:find('reward',1,true) and not encoded:find('49',1,true))
            assert(bytes(view)==before and bytes(State.project(data).encoded)==sourceBefore)
            j.rows[1].objective='changed';assert(Panels.journal(view,'stop').rows[1].objective=='Continue the active task.')
            assert(view.helpQuestSessions[acceptedId].paused and view.helpQuestSessions[offeredId].state=='offered')
        ''')

    def test_accepted_destination_tasks_can_name_future_stop_without_revealing_unvisited_terrain(self):
        self.accepted_tasks()
        self.lua.execute('''
            local view=projected();local j=Panels.journal(view,'stop');local m=Panels.trail(view)
            local mail,water,passenger
            for _,r in ipairs(j.rows)do
                if r.kind=='mail' then mail=r elseif r.kind=='supplies' then water=r elseif r.kind=='passenger' then passenger=r end
            end
            assert(mail.destination==8 and mail.objective=='Deliver the letter to Crow Merchant at Stop 8.')
            assert(water.destination==9 and water.objective=='Deliver 3 water supplies to Stop 9.')
            assert(passenger.destination==10 and passenger.objective=='Bring Cook Mouse to Stop 10.')
            assert(#m.points==2 and m.points[2].stop==6)
        ''')

    def test_current_expedition_objective_is_supplied_read_only_and_never_looked_up_or_advanced(self):
        self.lua.execute('''
            local view=projected();local before=bytes(view)
            local objective={title='EXPEDITION',text='Explore the current area.',status='CLEARED 1/2'}
            local original=bytes(objective);local m=Panels.journal(view,'expedition',objective)
            assert(#m.rows==1 and m.rows[1].active and m.rows[1].kind=='expedition')
            assert(m.currentObjective==objective.text and m.rows[1].detail==objective.status)
            m.rows[1].objective='changed';assert(bytes(objective)==original and bytes(view)==before)
            assert(#Panels.journal(view,'train',objective).rows==0)
        ''')

    def test_actual_current_area_objective_uses_saved_gates_without_creation_or_future_area_reveal(self):
        self.lua.execute('''
            local A=require('game.expedition_areas')
            A.ensure(data);data.scene='expedition';data.activeExpeditionArea=A.DUNGEON_ID
            local state=data.expeditions[A.DUNGEON_ID]
            state.gates.bossGateOpen=false;state.gates.bossDefeated=false
            local view=projected();local before=bytes(view)
            A.ensure=function()error('area created')end;A.state=function()error('state getter mutated')end
            A.updateGates=function()error('gate advanced')end
            local objective=Panels.expeditionObjective(view);local area=A.definition(A.DUNGEON_ID)
            assert(objective.title==area.name and objective.text==area.objectives.gateClosed)
            local j=Panels.journal(view,'expedition',objective)
            assert(j.rows[1].objective==area.objectives.gateClosed and bytes(view)==before)
            view.expeditions[A.DUNGEON_ID].gates.bossGateOpen=true
            assert(Panels.expeditionObjective(view).text==area.objectives.bossReady)
            view.scene='train';assert(not Panels.expeditionObjective(view))
            view.scene='expedition';view.expeditions[A.DUNGEON_ID]=nil
            assert(not Panels.expeditionObjective(view) and not view.expeditions[A.DUNGEON_ID])
        ''')

    def test_accepted_help_active_first_and_paused_tasks_sort_by_actual_destination(self):
        self.accepted_tasks()
        self.lua.execute('''
            local other=Help.ensure(data,{source='sewing',location=12,npc='tailor.png',
                title='SEWING',objective='Continue the active task.'})
            Help.accept(data,other.id)
            local view=projected();local before=bytes(view);local j=Panels.journal(view,'train')
            assert(#j.rows==5 and j.rows[1].kind=='help' and j.rows[1].active and j.rows[1].destination==12)
            assert(j.rows[2].kind=='help' and not j.rows[2].active and j.rows[2].destination==6)
            assert(j.rows[3].destination==8 and j.rows[4].destination==9 and j.rows[5].destination==10)
            assert(bytes(view)==before)
        ''')

    def test_original_desktop_and_touch_rendering_returns_private_controls_and_no_campaign_mutation(self):
        self.accepted_tasks()
        self.lua.execute('''
            local view=projected();local before=bytes(view)
            for _,mobile in ipairs({false,true})do
                local c=renderContext(mobile);local m=Panels.trail(view);local modelBefore=bytes(m)
                Panels.drawTrail(c,m);assert(bytes(m)==modelBefore)
                assert(c.controls.mapUp and c.controls.mapDown and c.controls.mapUp.enabled==false)
                assert(not c.controls.mapDown.enabled)
                assert(c.controls.map.value=='CLOSE MAP' and c.controls.map.h==(mobile and 50 or 38))
                assert(c.controls.map.y+c.controls.map.h<c.controls.mapUp.y,
                    'map close and scroll targets overlap')
                assert(c.controls.mapUp.y+c.controls.mapUp.h<c.controls.mapDown.y)
                local seen={};for _,t in ipairs(texts)do seen[t.value]=true end
                assert(seen['THE MOUSE FRONTIER TRAIL'] and seen['1'] and seen['6'] and not seen['2'])
                c=renderContext(mobile);m=Panels.journal(view,'stop');modelBefore=bytes(m)
                Panels.drawJournal(c,m);assert(bytes(m)==modelBefore)
                assert(c.controls.journeyLogClose.value=='CLOSE' and c.controls.journeyLogUp and c.controls.journeyLogDown)
                assert(c.controls.journeyLogBounds.w==(mobile and 904 or 670))
                assert(bytes(view)==before and not view.mapOpen and not view.journeyLogOpen)
            end
        ''')

    def test_render_private_journal_pagination_respects_original_card_bounds(self):
        self.lua.execute('''
            local d={location=6,mailQuests={}}
            for i=1,10 do d.mailQuests[i]={origin=1,destination=i,recipient='cook-mouse.png'}end
            local m=Panels.journal(d,'train',nil,999);local c=renderContext(false)
            Panels.drawJournal(c,m)
            assert(c.controls.journeyLogPageSize==3 and c.controls.journeyLogMaxScroll==7)
            assert(c.controls.journeyLogScroll==7)
            assert(c.controls.journeyLogUp.enabled and not c.controls.journeyLogDown.enabled)
            local found=false
            for _,t in ipairs(texts)do if t.value=='OBJECTIVE 8–10 OF 10'then found=true end end
            assert(found and m.scroll==999) -- Caller owns the private requested scroll.
        ''')

    def test_compile_and_module_has_no_save_network_input_or_generation_callback(self):
        path = ROOT / 'game/coop_guest_journey_panels.lua'
        source = path.read_text(encoding='utf-8')
        self.assertIsNotNone(self.lua.eval('loadstring')(source))
        for forbidden in ('submitCommand(', 'writeSave(', 'Areas.ensure(', 'Help.summary(', 'runtime.saveData'):
            self.assertNotIn(forbidden, source)


if __name__ == '__main__':
    unittest.main()
