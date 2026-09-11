"""Check removal of retired stop quests from saves without losing other progress."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class RetiredStopActivityBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path
            Schema=require('game.save_schema')
            HelpQuest=require('game.help_quest_session')
            data=assert(Schema.migrate({character='scout-frog.png',location=2,scene='stop',
                health=16,maxHealth=20,scrap=21,goodwill=7,resources={water=12}}))
            data.version=33
            local active=HelpQuest.ensure(data,{id='pump-active',source='community-water-pump',
                kind='settlement-activity',mode='dialogue',location=2})
            HelpQuest.activate(data,active.id)
            local completed=HelpQuest.ensure(data,{id='pump-completed',source='community-water-pump',
                kind='settlement-activity',mode='dialogue',location=1})
            HelpQuest.resolve(data,completed.id,'successful')
            completed.rewardClaimed=true
            local aid=HelpQuest.ensure(data,{id='first-aid',source='first-aid',kind='first-aid',location=2})
            aid.state='active'; aid.stage=3; aid.progress={cleaned=true}
            local dialogue=HelpQuest.ensure(data,{id='dialogue',source='missing-family',kind='dialogue',location=1})
            HelpQuest.resolve(data,dialogue.id,'exceptional')
            dialogue.rewardClaimed=true
            data.stopLayouts={
                [1]={worldActivity={kind='water-pump',version=2,sessionId=completed.id,completed=true},
                    npc='settler.png',shootingRange={rewarded=true}},
                [2]={worldActivity={kind='water-pump',version=2,sessionId=active.id,completed=false},
                    props={{name='barrel',x=410,y=300}}},
                ['8']={worldActivity={kind='community-garden',version=1,sessionId='legacy-linked'},npc='medic.png'},
            }
            data.helpQuestSessions['legacy-linked']={state='accepted',source='old-format'}
            data.helpHistory={{kind='settlement-activity',gained=1,location=1},{kind='first-aid',gained=3,location=2}}
            data.activeHelpQuestId=active.id
        ''')

    def test_old_pump_saves_clear_all_stops_and_preserve_earned_progress(self) -> None:
        self.lua.execute(r'''
            local migrated,info=Schema.migrate(data)
            assert(migrated,info)
            assert(info.fromVersion==33 and info.toVersion==Schema.CURRENT_VERSION)
            assert(info.steps==1 and info.rewriteRequired,'old saves must be rewritten after cleanup')
            for _,layout in pairs(migrated.stopLayouts) do assert(layout.worldActivity==nil) end
            assert(migrated.helpQuestSessions['pump-active']==nil)
            assert(migrated.helpQuestSessions['pump-completed']==nil)
            assert(migrated.helpQuestSessions['legacy-linked']==nil)
            assert(migrated.activeHelpQuestId==nil,'the retired objective must no longer be active')
            assert(migrated.health==16 and migrated.scrap==21 and migrated.goodwill==7)
            assert(migrated.resources.water==12 and #migrated.helpHistory==2)
            assert(migrated.helpHistory[1].kind=='settlement-activity' and migrated.helpHistory[1].gained==1)
            assert(migrated.stopLayouts[1].shootingRange.rewarded)
            assert(migrated.stopLayouts[2].props[1].name=='barrel')
            assert(migrated.stopLayouts['8'].npc=='medic.png')
            local aid=migrated.helpQuestSessions['first-aid']
            assert(aid.state=='active' and aid.stage==3 and aid.progress.cleaned)
            local dialogue=migrated.helpQuestSessions.dialogue
            assert(dialogue.state=='resolved' and dialogue.rewardClaimed and dialogue.result=='exceptional')
            assert(data.stopLayouts[2].worldActivity,'migration must not mutate the original save')
            assert(data.helpQuestSessions['pump-active'] and data.activeHelpQuestId=='pump-active')
        ''')

    def test_orphaned_activity_sessions_are_removed_without_interrupting_other_quests(self) -> None:
        self.lua.execute(r'''
            data.stopLayouts={}
            data.helpQuestSessions.orphanKind={kind='settlement-activity',source='legacy-pump',state='active'}
            data.helpQuestSessions.orphanSource={kind='community',source='community-water-pump',state='accepted'}
            data.activeHelpQuestId='first-aid'
            local migrated=assert(Schema.migrate(data))
            assert(migrated.helpQuestSessions.orphanKind==nil and migrated.helpQuestSessions.orphanSource==nil)
            assert(migrated.helpQuestSessions['pump-active']==nil and migrated.helpQuestSessions['pump-completed']==nil)
            assert(migrated.activeHelpQuestId=='first-aid')
            assert(migrated.helpQuestSessions['first-aid'].progress.cleaned)
            assert(migrated.helpQuestSessions.dialogue.rewardClaimed)
        ''')

    def test_cleanup_is_idempotent_and_also_applies_to_current_saves(self) -> None:
        self.lua.execute(r'''
            data.version=Schema.CURRENT_VERSION
            local migrated=assert(Schema.migrate(data))
            assert(migrated.stopLayouts[2].worldActivity==nil)
            assert(migrated.helpQuestSessions['pump-active']==nil and migrated.activeHelpQuestId==nil)
            local reloaded,info=Schema.migrate(migrated)
            assert(reloaded,info)
            assert(info.steps==0 and not info.rewriteRequired)
            assert(reloaded.stopLayouts[2].worldActivity==nil)
            assert(reloaded.goodwill==7 and reloaded.scrap==21 and reloaded.health==16)
            assert(reloaded.helpQuestSessions['first-aid'].stage==3)
            assert(reloaded.helpQuestSessions.dialogue.rewardClaimed)
        ''')


if __name__ == "__main__":
    unittest.main()
