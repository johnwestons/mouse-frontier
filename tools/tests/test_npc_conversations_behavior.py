"""Real Lua behavior: author wording, save persistence, pacing and exact rewards."""
from pathlib import Path
import os
import re
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime
from tools.import_user_conversations import parse


class ConversationTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            C=require('game.npc_conversations')
            Schema=require('game.save_schema')
            data=assert(Schema.migrate({character='frog',location=1}))
            data.currentNPC='resident'
            xp=0; items={}
            services={gainExperience=function(amount) xp=xp+amount end,
                random=function(a) return a end,
                storeItem=function(item) items[#items+1]=item; return 'backpack' end}
            function force(id)
                local request={id=id,npc='resident',location=data.location}
                C.ensure(data).assignments[tostring(data.location)]=request
                return request
            end
        ''')

    def test_wording_matches_all_91_author_lines(self):
        content=self.lua.eval('C.content')
        for i,entry in enumerate(parse(),1):
            self.assertEqual(content[i]['question'],entry['question'])
            for n in range(1,4):
                self.assertEqual(content[i]['choices'][n]['label'],entry['answers'][n])
                self.assertEqual(content[i]['choices'][n]['response'],entry['responses'][n])

    def test_restored_regular_lines_match_approved_archive_verbatim(self):
        archive=(ROOT/'docs/dialogue-review/changed-text.md').read_text(encoding='utf-8-sig')
        block=re.search(r'Catalog\.dialogueLines = \{.*?\n\}',archive,re.S).group()
        expected=self.lua.execute('Catalog={}; '+block+'; return Catalog.dialogueLines')
        actual=self.lua.execute('return require("game.catalog").dialogueLines')
        self.assertEqual(len(actual),33)
        self.assertEqual(list(actual.values()),list(expected.values()))

    def test_all_39_branches_complete_once(self):
        self.lua.execute('''
            for _,entry in ipairs(C.content) do
                for index=1,3 do
                    data.conversations={}; data.resources={food=5,water=5}
                    local request=force(entry.id)
                    local before=xp
                    local result=C.choose(data,request,index,services)
                    assert(result.completed and result.text==entry.choices[index].response)
                    assert(xp==before+5)
                    assert(not C.choose(data,request,index,services).completed)
                    assert(xp==before+5 and not C.begin(data,'resident'))
                end
            end
        ''')

    def test_pacing_assignments_are_random_unique_and_persistent(self):
        self.lua.execute('''
            for seed=1,30 do
                math.randomseed(seed); data.conversations={}
                local previous=0; local used={}; local count=0
                for stop=1,50 do
                    data.location=stop
                    local layout={npcOutside='outside-'..stop,houseDoors={['1']={npc='inside-'..stop}}}
                    local request=C.assign(data,layout)
                    if request then
                        assert(previous==0 or (stop-previous>=2 and stop-previous<=4))
                        assert(not used[request.id]); used[request.id]=true; count=count+1
                        assert(request.npc==layout.npcOutside or request.npc==layout.houseDoors['1'].npc)
                        assert(C.assign(data,layout)==request)
                        previous=stop
                    end
                end
                assert(count==13)
                local saved=assert(Schema.migrate(data))
                assert(saved.conversations.nextStop==data.conversations.nextStop)
                for stop,r in pairs(data.conversations.assignments) do
                    assert(saved.conversations.assignments[stop].id==r.id)
                    assert(saved.conversations.assignments[stop].npc==r.npc)
                end
            end
        ''')

    def test_shortage_blocks_without_partial_cost_and_free_answer_works(self):
        self.lua.execute('''
            local request=force('food'); data.resources={food=2,water=0}
            local view=C.begin(data,'resident')
            assert(view.choices[1].enabled and not view.choices[2].enabled and view.choices[3].enabled)
            assert(not C.choose(data,request,2,services).completed)
            assert(data.resources.food==2 and xp==0)
            data.resources.food=0
            assert(not C.choose(data,request,1,services).completed)
            assert(C.choose(data,request,3,services).completed and xp==5)
            assert(data.resources.food==0 and data.resources.water==0)
        ''')

    def test_food_uses_train_storage_and_exact_cost(self):
        self.lua.execute('''
            for answer=1,2 do
                data.conversations={}; data.resources={food=4,water=3}; data.inventory={'food-ration'}
                assert(C.choose(data,force('food'),answer,services).completed)
                assert(data.resources.food==2 and data.resources.water==(answer==1 and 3 or 2))
                assert(data.inventory[1]=='food-ration')
            end
        ''')

    def test_exact_ammo_and_mixed_cartridges(self):
        self.lua.execute('''
            for answer=1,3 do
                data.conversations={}; data.ammo={}
                assert(C.choose(data,force('ammunition'),answer,services).completed)
                if answer==1 then assert(data.ammo['22lr']==20)
                elseif answer==2 then assert(data.ammo['9mm']==10)
                else
                    local count,kinds=0,0
                    for caliber,n in pairs(data.ammo) do
                        assert(caliber~='rocks' and caliber~='arrows' and caliber~='ball-bearings')
                        count=count+n; kinds=kinds+1
                    end
                    assert(count==15 and kinds>=2)
                end
            end
        ''')

    def test_healing_rewards_use_real_full_inventory_fallback(self):
        self.lua.execute('''
            local Q=require('game.quest_progression'); local Catalog=require('game.catalog')
            local I=require('game.inventory'); local House=require('game.house')
            services.storeItem=function(item)
                return Q.storeRewardItem(data,Catalog,I,item,function(name) House.storeLoot(data,Catalog,name,data.location) end)
            end
            data.inventoryCapacity=1; data.inventory={'food-ration'}
            data.droppedItems={{name='mailbox-reward',scene='train',storage={}}}
            assert(C.choose(data,force('wounds'),2,services).completed)
            assert(data.droppedItems[1].storage[1]=='field-bandage-roll')
            data.conversations={}; data.droppedItems={}
            assert(C.choose(data,force('wounds'),3,services).completed)
            assert(data.droppedItems[1].storage[1]=='frontier-medkit')
        ''')

    def test_resume_and_reward_once_after_real_serialization(self):
        self.lua.execute('''
            local files={}
            love.filesystem={getInfo=function(p) return files[p] and {type='file'} end,
                createDirectory=function() return true end,
                write=function(p,text) files[p]=text; return true end,
                read=function(p) return files[p] end,
                load=function(p) return loadstring(files[p] or '') end,
                remove=function(p) files[p]=nil; return true end}
            local Save=require('game.save')
            local request=force('wastes'); assert(C.begin(data,'resident'))
            -- Schema uses the same deep-copy path as reads, then bind to the
            -- reloaded assignment rather than keeping a stale runtime reference.
            assert(Save.write(1,data)); data=assert(Save.read(1))
            assert(not C.choose(data,request,1,services).completed)
            local view=C.begin(data,'resident'); assert(view and data.conversations.seen.wastes)
            assert(C.choose(data,view.request,2,services).completed)
            assert(Save.write(1,data)); data=assert(Save.read(1))
            assert(not C.begin(data,'resident') and xp==5)
            assert(data.conversations.completed.wastes.answer==2)
        ''')

    def test_old_speech_sessions_retire_without_changing_rewards(self):
        self.lua.execute('''
            data.version=34; data.goodwill=12; data.stats.xp=9
            data.stopLayouts={['1']={dialogueHelpRequests={resident={accepted=true}},npcOffers={resident='dialogue'}}}
            data.helpQuestSessions={old={kind='dialogue-help',state='active'}}; data.activeHelpQuestId='old'
            data=assert(Schema.migrate(data))
            assert(data.version==35 and data.goodwill==12 and data.stats.xp==9)
            assert(not data.stopLayouts['1'].dialogueHelpRequests and not data.helpQuestSessions.old)
            assert(not data.activeHelpQuestId)
        ''')

    def test_corrupt_state_rejected(self):
        self.lua.execute('''
            for _,bad in ipairs({{assignments=4},{seen='bad'},{completed=false},{nextStop=-1},
                {assignments={['1']={id='wastes',npc='resident',location=2}}}}) do
                data.conversations=bad
                assert(not Schema.migrate(data))
            end
        ''')

    def test_journey_wires_pause_resume_response_and_single_reward(self):
        context=self.lua.table()
        source=(ROOT/'game/journey_rules.lua').read_text(encoding='utf-8')
        for name,kind in re.findall(r'required\(context,\s*"([^"]+)",\s*"([^"]+)"\)',source):
            context[name]=self.lua.table() if kind=='table' else self.lua.eval('function() end')
        self.lua.globals().context=context
        self.lua.execute('''
            runtime={saveData=data}; context.runtime=runtime
            context.util=require('game.util')
            context.catalog=require('game.catalog'); context.inventory=require('game.inventory')
            context.questProgression=require('game.quest_progression')
            context.stopHelpProgression=require('game.stop_help_progression')
            context.npcRelationships=require('game.npc_relationships')
            context.helpDialogueQuests=require('game.help_dialogue_quests')
            context.battleRules={gainExperience=function(_,amount) xp=xp+amount end}
            context.ensureStopLayout=function() return {npcOutside='resident',npcOffers={}} end
            writes=0; context.writeSave=function() writes=writes+1 end
            local journey=require('game.journey_rules').new(context)
            force('food'); data.resources={food=2,water=1}
            journey.talkToNPC()
            assert(runtime.helpDialogue.authored and runtime.dialogue.text=='Got any food i can get?')
            journey.chooseHelpDialogue(nil)
            assert(not runtime.dialogue and not runtime.helpDialogue and xp==0)
            journey.talkToNPC(); journey.chooseHelpDialogue(2)
            assert(not runtime.helpDialogue and runtime.dialogue.authored)
            assert(runtime.dialogue.text=='You bet I am, and yes please that would be delightful')
            assert(runtime.dialogue.notice:find('+5 XP',1,true))
            assert(data.resources.food==0 and data.resources.water==0 and xp==5)
            assert(not journey.chooseHelpDialogue(2))
            runtime.dialogue=nil; journey.talkToNPC()
            assert(runtime.dialogue and runtime.dialogue.text==context.catalog.dialogueLines[1] and xp==5 and writes>=4)
            assert(not runtime.helpDialogue)
            -- Regular speech stays available between the one-time trees.
            context.catalog.dialogueLines={C.content[1].choices[1].response}
            runtime.dialogue=nil; journey.talkToNPC()
            assert(runtime.dialogue.text==C.content[1].choices[1].response and not runtime.helpDialogue)
            assert(xp==5)
            context.catalog.dialogueLines={}; runtime.dialogue=nil; journey.talkToNPC()
            assert(runtime.dialogue.text=='No new conversation available.' and xp==5)
        ''')

    def test_regular_npc_and_passenger_only_use_supplied_chatter(self):
        self.lua.execute('''
            local R=require('game.npc_relationships')
            local lines={C.content[1].choices[1].response,C.content[1].choices[2].response}
            assert(R.npcDialogue(data,'resident',lines)==lines[1])
            assert(R.npcDialogue(data,'resident',lines)==lines[2])
            assert(R.npcDialogue(data,'resident',lines)==lines[1])
            local passenger={npc='resident',destination=7}
            assert(R.passengerDialogue(data,passenger,lines)==lines[1])
            assert(R.passengerDialogue(data,passenger,lines)==lines[2])
            assert(not R.passengerDialogue(data,passenger,{}))
            assert(not R.npcDialogue(data,'resident',{}))
            assert(xp==0)
        ''')

    def test_mobile_talk_button_opens_closes_and_resumes_regular_chatter(self):
        for module,global_name in [('journey_rules','journey_context'),('gameplay_input','input_context'),('mobile_runtime','mobile_context')]:
            context=self.lua.table()
            source=(ROOT/f'game/{module}.lua').read_text(encoding='utf-8')
            for name,kind in re.findall(r'required\(context,\s*"([^"]+)",\s*"([^"]+)"\)',source):
                context[name]=self.lua.table() if kind=='table' else 960 if kind=='number' else self.lua.eval('function() end')
            self.lua.globals()[global_name]=context
        self.lua.execute('''
            love.system={getOS=function() return 'Android' end}
            love.graphics={getDimensions=function() return 960,720 end}
            love.timer={getTime=function() return 0 end}
            love.keyboard={isDown=function() return false end}
            local Catalog=require('game.catalog'); local R=require('game.npc_relationships')
            local Util=require('game.util'); local noop=function() end
            runtime={state='game',scene='stop',saveData=data}; ui={playSfx=noop}
            for _,ctx in ipairs({journey_context,input_context,mobile_context}) do
                ctx.runtime=runtime; ctx.ui=ui; ctx.util=Util; ctx.catalog=Catalog
                ctx.npcRelationships=R
            end
            journey_context.questProgression=require('game.quest_progression')
            journey_context.stopHelpProgression=require('game.stop_help_progression')
            journey_context.helpDialogueQuests=require('game.help_dialogue_quests')
            journey_context.ensureStopLayout=function() return {npcOutside='resident',npcOffers={}} end
            journey_context.battleRules={gainExperience=function(_,amount) xp=xp+amount end}
            local journey=require('game.journey_rules').new(journey_context)
            input_context.talkToNPC=journey.talkToNPC
            input_context.chooseHelpDialogue=journey.chooseHelpDialogue
            input_context.interactionKeyAction=require('game.interaction_router').keyAction
            local input=require('game.gameplay_input').new(input_context)
            mobile_context.mobileControls=require('game.mobile_controls')
            mobile_context.width=960; mobile_context.height=720
            mobile_context.viewportToGame=function(x,y) return x,y end
            mobile_context.getGameplayInput=function() return input end
            local mobile=require('game.mobile_runtime').new(mobile_context)
            local controls=mobile.initialize()
            local function tap()
                controls:_updateCornerLayout()
                assert(mobile.touchpressed('talk',controls.primary.x,controls.primary.y))
                mobile.touchreleased('talk',controls.primary.x,controls.primary.y)
            end
            ui.interaction={kind='npc'}
            assert(select(2,controls.primaryAction())=='TALK')
            tap(); assert(runtime.dialogue.text==Catalog.dialogueLines[1])
            assert(select(2,controls.primaryAction())=='CLOSE')
            tap(); assert(not runtime.dialogue)
            tap(); assert(runtime.dialogue.text==Catalog.dialogueLines[2]); tap()
            force('travel-time'); tap(); assert(runtime.helpDialogue.authored)
            input.keypressed('1'); assert(xp==5 and not runtime.helpDialogue)
            input.keypressed('q'); tap()
            assert(runtime.dialogue.text==Catalog.dialogueLines[3] and xp==5); tap()
            runtime.scene='train'; data.passengers={{npc='rider',destination=8}}
            ui.interaction={kind='passenger',index=1}
            tap(); assert(runtime.dialogue.text==Catalog.dialogueLines[1]); tap()
            tap(); assert(runtime.dialogue.text==Catalog.dialogueLines[2] and xp==5)
        ''')


if __name__=='__main__': unittest.main()
