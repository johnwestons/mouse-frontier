"""Execute actual Lua save ownership, permission and persistence behavior."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopFoundationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Players=require('game.coop_players')
            Schema=require('game.save_schema')
            Capabilities=require('game.coop_capabilities')
            Fixtures=require('tools.tests.lua.coop_fixtures')
            data=Fixtures.campaign(20)
        ''')

    def test_legacy_migration_has_one_authoritative_host_record(self):
        self.lua.execute('''
            assert(data.version==Schema.CURRENT_VERSION and data.players.host.id=='host')
            assert(rawget(data,'health')==nil and rawget(data,'inventory')==nil)
            assert(data.health==17 and data.players.host.health==17)
            data.health=12
            data.inventory[2]='test-item'
            assert(data.players.host.health==12 and data.players.host.inventory[2]=='test-item')
            data.players.host.ammo.rocks=3
            assert(data.ammo.rocks==3)
            assert(data.inventory[3]==nil and data.inventory[4]=='cowboy-hat')
            assert(data.conversations.completed.example.answer==2 and data.location==20)
            local migrated,report=Schema.migrate(data)
            assert(report.steps==0 and not report.rewriteRequired)
            assert(migrated.health==12 and migrated.players.host~=data.players.host)
            assert(migrated.inventory[2]=='test-item' and Schema.validate(migrated))
        ''')

    def test_enrollment_catches_up_once_without_cloning_possessions(self):
        self.lua.execute('''
            local guest=assert(Fixtures.enroll(data))
            assert(guest.id=='companion' and guest.stats.level==2 and guest.stats.xp==4)
            assert(guest.stats~=data.stats and guest.health==25 and guest.maxHealth==25)
            assert(next(guest.inventory)==nil and guest.ammo.rocks==12)
            assert(next(guest.weaponDurability)==nil)
            guest.ammo.rocks=1; guest.health=7
            local again,reason=Fixtures.enroll(data)
            assert(not again and reason=='companion_exists')
            assert(guest.ammo.rocks==1 and guest.health==7)
            assert(data.health==17 and data.ammo.rocks==8)
        ''')

    def test_enrollment_rejects_guest_and_unloaded_character(self):
        self.lua.execute('''
            local catalog={characterTrait=function() error('must not reach catalog') end}
            local value,reason=Players.enroll(data,'companion','cook-mouse.png',catalog,{})
            assert(not value and reason=='host_only')
            value,reason=Players.enroll(data,'host','../unknown.png',catalog,{})
            assert(not value and reason=='invalid_character' and not data.players.companion)
        ''')

    def test_actor_scoped_domains_never_switch_host_identity(self):
        self.lua.execute('''
            assert(Fixtures.enroll(data))
            local guest=Players.forActor(data,'companion')
            local host=Players.forActor(data,'host')
            guest.ammo.rocks=2; guest.inventory[1]='gift'; guest.health=5
            guest.scrap=10
            assert(host.ammo.rocks==8 and host.health==17 and host.inventory[1]=='orange-rose-vase')
            assert(data.character=='scout-frog.png' and data.players.companion.health==5)
            assert(data.scrap==10 and host.scrap==10)
            local Progression=require('game.player_progression')
            Progression.gainExperience(guest,14)
            assert(guest.stats.level==3 and host.stats.level==2)
            assert(not Schema.migrate(guest) and not Schema.copy(guest))
        ''')

    def test_save_roundtrip_keeps_both_players_without_legacy_duplicates(self):
        self.lua.execute('''
            assert(Fixtures.enroll(data))
            data.players.companion.inventory[6]='saved-item'
            data.players.companion.health=4
            local fs,files=Fixtures.filesystem()
            love={filesystem=fs}
            local Save=require('game.save')
            assert(Save.write(1,data))
            local decoded=assert(loadstring(files[Save.path(1)]))()
            assert(decoded.character==nil and decoded.inventory==nil)
            assert(decoded.players.host.character=='scout-frog.png')
            assert(Schema.validate(decoded))
            local writes=0; local original=fs.write
            fs.write=function(...) writes=writes+1; return original(...) end
            local loaded=assert(Save.read(1))
            assert(writes==0,'canonical save read must not perpetually rewrite')
            assert(loaded.health==17 and loaded.players.companion.health==4)
            assert(loaded.players.companion.inventory[6]=='saved-item')
            assert(loaded.conversations.completed.example.answer==2)
            local copied=assert(Schema.copy(loaded))
            assert(copied.character=='scout-frog.png' and copied.inventory[4]=='cowboy-hat')
            copied.players.companion.inventory[6]=nil
            assert(loaded.players.companion.inventory[6]=='saved-item')
        ''')

    def test_invalid_records_cannot_silently_replace_host_or_companion(self):
        self.lua.execute('''
            assert(Fixtures.enroll(data))
            for _,mutate in ipairs({
                function(d) d.players.impostor={} end,
                function(d) d.players.companion.id='host' end,
                function(d) d.players.companion.health=math.huge end,
                function(d) d.players.companion.inventory='invalid' end,
                function(d) d.players.companion.stats.xp=0/0 end,
                function(d) d.players.companion.ammo.rocks=-1 end,
                function(d) rawset(d,'health',99) end,
            }) do
                local invalid=assert(Schema.copy(data)); mutate(invalid)
                assert(not Schema.migrate(invalid))
            end
            assert(data.players.companion.id=='companion' and data.health==17)
        ''')

    def test_guest_progression_and_indirect_story_effects_are_denied(self):
        self.lua.execute('''
            assert(Capabilities.validate())
            local hostOnly,help=0,0
            for name,spec in pairs(Capabilities.commands) do
                if spec.policy=='host_progression' or spec.policy=='host_admin' then
                    local ok,reason=Capabilities.authorize(name,'guest')
                    assert(not ok and reason=='host_only',name)
                    assert(Capabilities.authorize(name,'host'),name)
                    hostOnly=hostOnly+1
                elseif spec.policy~='local_presentation' then
                    assert(Capabilities.authorize(name,'guest'),name)
                    help=help+1
                end
            end
            assert(hostOnly>30 and help>40)
            for _,name in ipairs({'quest.deliver','roaming.attack','npc.chatter','train.upgrade'}) do
                assert(not Capabilities.authorize(name,'guest',{scene=true}))
                assert(not Capabilities.authorize(name,'guest',{story=true}))
                assert(Capabilities.authorize(name,'host',{scene=true}))
            end
            assert(not Capabilities.authorize('invented.command','host'))
            assert(not Capabilities.authorize('gun.fire','stranger'))
            assert(not Capabilities.authorize('settings.change','host'))
        ''')

    def test_world_interaction_registry_fails_closed(self):
        self.lua.execute('''
            for _,kind in ipairs({'item','chest','mailbox','radio','carPrev','carNext','returnTrain',
                'house','houseExit','shootingRange','npc','passenger','fire','expedition','crowCaravan'}) do
                assert(Capabilities.requireInteraction(kind))
            end
            assert(not pcall(Capabilities.requireInteraction,'unclassified'))
            local Router=require('game.interaction_router')
            local selected=false
            local ok,message=pcall(Router.select,{data={droppedItems={},passengers={},trainCars={}},
                scene='test',car={x=0,y=0,w=100},player={x=0,y=0},expeditionInteraction={kind='unclassified'},
                choose=function() selected=true end})
            assert(not ok and not selected and message:find('undeclared co%-op interaction'))
        ''')

    def test_client_session_cannot_save_or_update_host_scene_position(self):
        self.lua.execute('''
            assert(Fixtures.enroll(data))
            local Session=require('game.game_session')
            local session=Session.new()
            session:activate(data,{x=11,y=12}); session:selectSlot(1)
            session:setNetworkMode('client')
            assert(session:character().id=='companion')
            assert(not session:scheduleSave({schedule=function() error('guest wrote') end}))
            session:setScene('house')
            session:sync('game',1,data,{x=99,y=100},'house')
            assert(data.scene=='train' and data.playerX==200 and data.playerY==250)
            session:setNetworkMode('host')
            local wrote=false
            assert(session:scheduleSave({schedule=function() wrote=true; return true end}) and wrote)
            assert(not session:scheduleSave({schedule=function() return false end}))
        ''')

    def test_every_persistence_entry_point_is_blocked_on_client(self):
        self.lua.execute('''
            local Session=require('game.game_session')
            local session=Session.new(); session:setNetworkMode('client')
            local runtime={selectedSlot=1,saveData=data,syncForSave=function() error('guest synced save') end}
            local touched=0
            local function forbidden() touched=touched+1; error('guest accessed campaign storage') end
            local Persistence=require('game.persistence_runtime').new({runtime=runtime,ui={},session=session,
                save={schedule=forbidden,update=forbidden,read=forbidden,remove=forbidden,flush=forbidden},
                maintenance={release=function() end},maintenanceSession={},
                focusMobile=function() end,focusAudio=function() end,shutdownAudio=function() end})
            assert(Persistence.schedule()==false)
            assert(Persistence.update(1)==false)
            assert(Persistence.read(1)==nil)
            assert(Persistence.remove(1)==false)
            assert(Persistence.flush()==false)
            Persistence.focus(false); Persistence.shutdown()
            assert(touched==0)
        ''')


if __name__ == '__main__':
    unittest.main()
