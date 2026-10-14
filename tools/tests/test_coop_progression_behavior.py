"""Controller-level host progression checks, beyond the packet policy."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopProgressionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            local Fixtures=require('tools.tests.lua.coop_fixtures')
            data=Fixtures.campaign(20); assert(Fixtures.enroll(data))
            Session=require('game.game_session')
            session=Session.new(); session:setSaveData(data)
            session:setPlayer({x=200,y=250}); session:setScreen('game')
            runtime=require('game.runtime_state').new({session=session,
                transition=function(name) session:setScreen(name) end})
            writes=0
            function save() writes=writes+1 end
            function tripwire() error('guest reached a progression effect') end
            function tables(context,names)
                for name in names:gmatch('%S+') do context[name]={} end
                return context
            end
            session:setNetworkMode('client')
        ''')

    def test_journey_denies_guest_before_rolling_encounters_or_accepting_quests(self):
        self.lua.execute('''
            local context=tables({runtime=runtime,ensureStopLayout=tripwire,setupNPC=function() end,
                writeSave=save,beginEncounter=tripwire,beginRequiredEvent=tripwire,beginRandomEvent=tripwire},
                'car inventory catalog engineUpgrades progressionBalance combatBalance eventBalance trainUpgradeBalance questProgression lootProgression stopHelpProgression helpQuestSession helpDialogueQuests npcRelationships firstAid battleRules maintenance passengers util house')
            local journey=require('game.journey_rules').new(context)
            assert(journey.attemptLeaveTrain()==false)
            assert(journey.enterStop()==false)
            assert(journey.acceptQuest('mail')==false)
            runtime.helpDialogue={authored=true,request={npc='test'}}
            assert(journey.chooseHelpDialogue(1)==false)
            assert(runtime.scene=='train' and data.scene=='train' and #data.mailQuests==0 and writes==0)
            session:setNetworkMode('host')
            local epoch=data.coop.sceneEpoch
            journey.enterStop()
            assert(runtime.scene=='stop' and data.scene=='stop' and writes==1)
            assert(data.coop.sceneEpoch>epoch and runtime.player.x==270)
        ''')

    def test_events_cannot_generate_or_resolve_on_guest(self):
        self.lua.execute('''
            local events=require('game.event_runtime').new({runtime=runtime,ui={playSfx=tripwire},
                events={resolve=tripwire,required=tripwire,random=tripwire},eventUI={},catalog={},
                combatBalance={},eventBalance={},trainUpgradeBalance={},pointIn=tripwire,
                writeSave=save,beginEncounter=tripwire,enterStop=tripwire})
            runtime.randomEvent={id='saved-event'}
            assert(events.begin({})==false and events.beginRequired(20)==false)
            assert(events.beginRandom()==false and events.choose(1)==false)
            assert(runtime.randomEvent.id=='saved-event' and runtime.state=='game' and writes==0)
        ''')

    def test_return_to_train_is_guarded_before_sound_position_or_save(self):
        self.lua.execute('''
            runtime.scene='house'
            local train=require('game.train_car_runtime').new({runtime=runtime,ui={playSfx=tripwire},
                scenery={},car={},train={},width=960,height=720,writeSave=save})
            assert(train.enterTrain(true)==false)
            assert(runtime.scene=='house' and runtime.player.x==200 and runtime.player.y==250 and writes==0)
        ''')

    def test_expedition_shortcuts_and_challenges_cannot_progress_guest(self):
        self.lua.execute('''
            local context=tables({runtime=runtime,ui={playSfx=tripwire},
                roamingMobs={new=function() return {} end},getIsWeapon=tripwire,getBeginEncounter=tripwire,
                writeSave=save,clampToStop=tripwire,width=960,height=720},
                'catalog areas mobImages mobIdleImages mobWalkImages mobAttackImages mobHitImages mobDeathImages mobRangedImages')
            local expedition=require('game.expedition_runtime').new(context)
            for _,action in ipairs({'enterArea','returnStop','challenge'}) do
                assert(expedition.activateInteraction({kind='expedition',action=action,targetArea='test'})==false)
            end
            assert(runtime.scene=='train' and data.activeExpeditionArea==nil and writes==0)
        ''')

    def test_last_stand_buttons_and_automatic_progression_wait_for_host(self):
        self.lua.execute('''
            local quest={state='waiting',holdElapsed=0}
            runtime.lastStand={mode='offer',capture=true,quest=quest,offerPage=1}
            local service=require('game.last_stand_quest').new({runtime=runtime,catalog={},writeSave=save,
                characterImages={},width=960,height=720,controlBindings={}})
            service:keypressed('y'); service:keypressed('n')
            assert(quest.state=='waiting' and writes==0)
            runtime.lastStand.mode='escort'; runtime.lastStand.clock=0
            service:keypressed('space'); service:update(60)
            assert(runtime.lastStand.mode=='escort' and runtime.lastStand.clock==0 and writes==0)
            runtime.lastStand.mode='shootout'
            runtime.lastStand.shootout={result='retreat'}
            service:keypressed('return'); service:mousepressed(480,450,1,true)
            assert(runtime.lastStand.shootout.result=='retreat' and writes==0)
        ''')

    def test_scene_scope_invalidates_old_actions_for_same_scene_different_stop(self):
        self.lua.execute('''
            session:setNetworkMode('host')
            local epoch=data.coop.sceneEpoch
            session:syncSceneEpoch()
            assert(data.coop.sceneEpoch==epoch)
            local authority=require('game.coop_authority').new({campaign=data,sessionId='scene-test'})
            authority:register('npc.chatter',function()
                return {scopes={'npc'},apply=tripwire}
            end)
            authority:admit('companion',1)
            local request=assert(authority:prepareRequest('companion','npc.chatter',{}))
            data.location=data.location+1
            runtime:syncForSave()
            assert(data.coop.sceneEpoch==epoch+1)
            assert(authority:execute('companion',1,request).reason=='stale_scene')
            runtime:syncForSave(); assert(data.coop.sceneEpoch==epoch+1)
            session:setScene('house')
            epoch=data.coop.sceneEpoch
            data.activeHouseDoor=2; session:setScene('house')
            assert(data.coop.sceneEpoch==epoch+1)
            epoch=data.coop.sceneEpoch
            session:setScreen('battle'); assert(data.coop.sceneEpoch==epoch+1)
            session:setNetworkMode('client'); epoch=data.coop.sceneEpoch
            session:setScene('train'); session:setScreen('game'); runtime:syncForSave()
            assert(data.coop.sceneEpoch==epoch and data.scene=='house')
        ''')


if __name__ == '__main__':
    unittest.main()
