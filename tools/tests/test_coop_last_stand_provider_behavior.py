"""Farmhouse supplies use actor-owned pools, checked poses and durable receipts."""
import unittest
import test_coop_last_stand_progression_behavior as progression
import test_coop_last_stand_movement_behavior as movement


class FarmhouseProviderTests(unittest.TestCase):
    setUp = progression.LastStandProgressionTests.setUp
    stand = progression.LastStandProgressionTests.stand

    def provider(self):
        self.stand()
        self.lua.execute('''
            enter(); Provider=require('game.coop_last_stand_provider'); Guns=require('game.coop_guns')
            WireResults=require('game.net.gun_results'); context={catalog=Catalog,
                actorState=function(id) return states[id] end,lastStandScene=function() return modal end}
            states={host={screen='game',scene='stop'},companion={screen='game',scene='stop',movementReady=true,modalDomain=Life.key(data)}}
            Guns.install(service,context)
            host.ammo['22lr']=0; guest.ammo['22lr']=0
            for _,id in ipairs({'host','companion'}) do local p=Life.pose(data,id); p.x,p.y=300,335 end
            function pa(extra)
                local a={mode='farmhouse',questId=quest.lifecycle.entityId,revision=quest.lifecycle.revision}
                for k,v in pairs(extra or {}) do a[k]=v end; return a
            end
            function supply(id,extra) return run(id or 'companion','lastStand.supply',pa(extra)) end
            writes=0
        ''')

    def test_each_actor_borrows_without_owned_gun_ammo_or_story_changes(self):
        self.provider()
        self.lua.execute('''
            local epoch,rev=data.coop.sceneEpoch,quest.lifecycle.revision
            local hi,gi=Items.weapons(host,Catalog)[1].id,Items.weapons(guest,Catalog)[1].id
            modal.paused=true
            local r=supply(); assert(r.ok and r.durable,r.reason); assert(WireResults.valid('lastStand.supply',r.result))
            assert(r.result.actorId=='companion' and r.result.suppliedRounds==48 and r.result.loanAmmo==48)
            assert(quest.shooterSessions.companion.loanAmmo==48 and quest.loanAmmo==0 and not quest.loanActive)
            assert(not quest.shooterSessions.companion.weaponSession and not quest.weaponSession)
            assert(host.ammo['22lr']==0 and guest.ammo['22lr']==0)
            assert(Items.selection(host,hi,Catalog) and Items.selection(guest,gi,Catalog))
            assert(supply('host').reason=='provider_unavailable'); modal.paused=false
            assert(supply('host').ok and quest.loanAmmo==48 and writes==2)
            assert(quest.lifecycle.revision==rev and quest.state=='interior' and data.coop.sceneEpoch==epoch)
            assert(Schema.validate(saved))
        ''')

    def test_supply_checks_saved_pose_not_claimed_or_ordinary_coordinates(self):
        self.provider()
        self.lua.execute('''
            Life.pose(data,'companion').x=500; states.companion.x=300; states.companion.y=335
            guest.playerX=300; guest.playerY=335
            assert(supply().reason=='provider_distance')
            assert(supply(nil,{x=300,y=335}).reason=='invalid_args')
            assert(not quest.shooterSessions and writes==0)
        ''')

    def test_supply_requires_current_modal_readiness_and_unblocked_actor(self):
        self.provider()
        self.lua.execute('''
            states.companion.movementReady=false; assert(supply().reason=='provider_unavailable'); states.companion.movementReady=true
            states.companion.modalDomain='old'; assert(supply().reason=='provider_unavailable'); states.companion.modalDomain=Life.key(data)
            states.companion.activeActivity='firstAid'; assert(supply().reason=='provider_unavailable'); states.companion.activeActivity=nil
            guest.health=0; assert(supply().reason=='provider_unavailable'); guest.health=20
            modal.blocked=true; assert(supply().reason=='provider_unavailable'); modal.blocked=nil
            modal.active=false; assert(supply().reason=='provider_unavailable'); assert(writes==0)
        ''')

    def test_old_phase_wrong_scene_victory_and_usable_owned_ammo_deny_supply(self):
        self.provider()
        self.lua.execute('''
            assert(supply(nil,{revision=quest.lifecycle.revision-1}).reason=='stale_phase')
            assert(supply(nil,{questId='e999999'}).reason=='provider_unavailable')
            quest.victory=true; assert(supply().reason=='provider_unavailable'); quest.victory=false
            guest.ammo['22lr']=1; assert(supply().reason=='supply_unavailable'); guest.ammo['22lr']=0
            assert(Life.move(quest,'backyard')); Life.ensure(data); refresh()
            assert(supply().reason=='provider_unavailable' and writes==0)
        ''')

    def test_repeat_and_refill_preserve_cached_exact_guns_and_other_pool(self):
        self.provider()
        self.lua.execute('''
            local gun=require('game.first_person_shooting').new(guest,Catalog,quest,960,720)
            local record=Sessions.record(gun); local scope=quest.shooterSessions.companion
            record.cooldown=.25; scope.weaponSessions={[record.itemId]=record}
            local ownId=record.itemId
            assert(supply().ok); assert(supply().reason=='supply_unavailable')
            assert(scope.weaponSession.itemId==ownId and not scope.weaponSession.borrowed and scope.weaponSession.cooldown==.25)
            assert(scope.weaponSessions[ownId].itemId==ownId and scope.weaponSessions[ownId].magazine==0)
            scope.loanAmmo=0
            local r=supply(); assert(r.ok and r.result.suppliedRounds==12,r.reason)
            assert(scope.loanAmmo==12 and quest.loanAmmo==0 and writes==2)
            assert(scope.weaponSession.itemId==ownId and scope.weaponSessions[ownId].cooldown==.25)
            assert(supply().reason=='supply_unavailable')
        ''')

    def test_failed_checkpoint_replay_does_not_duplicate_or_confirm_supplies(self):
        self.provider()
        self.lua.execute('''
            failSave=true; local request=assert(service:prepareRequest('companion','lastStand.supply',pa()))
            local r=service:execute('companion',1,request)
            assert(r.ok and r.savePending and not r.durable and quest.shooterSessions.companion.loanAmmo==48)
            assert(service:execute('companion',1,request).savePending and writes==1)
            failSave=false; assert(service:retryCheckpoint())
            r=service:execute('companion',1,request); assert(r.durable and quest.shooterSessions.companion.loanAmmo==48 and writes==2)
            local restored=assert(Schema.migrate(saved)); local next=Authority.new({campaign=restored,sessionId='provider-restored'})
            next:admit('companion',2); assert(next:execute('companion',2,request).reason=='wrong_session')
            local fingerprint=assert(require('game.net.codec').encode(request,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
            r=next:receipt('companion',2,request.sessionId,request.requestId,fingerprint)
            assert(r.ok and r.durable and restored.lastStand.shooterSessions.companion.loanAmmo==48)
        ''')

    def test_public_facts_do_not_expose_save_tables_or_accept_forged_resources(self):
        self.provider()
        self.lua.execute('''
            local r=supply(); assert(r.ok,r.reason); local facts=r.result
            facts.quest=quest; assert(not WireResults.valid('lastStand.supply',facts))
            local clean=assert(WireResults.project('lastStand.supply',facts)); assert(clean.quest==nil)
            clean.loanAmmo=999; assert(not WireResults.valid('lastStand.supply',clean)); clean.loanAmmo=48
            clean.actorId='enemy'; assert(not WireResults.valid('lastStand.supply',clean)); clean.actorId='companion'
            clean.suppliedRounds=49; assert(not WireResults.valid('lastStand.supply',clean))
        ''')

    def test_provider_loans_restore_into_separate_shooters_without_owned_ammo(self):
        self.provider()
        self.lua.execute('''
            assert(supply('host').ok and supply().ok)
            modal.x=350; modal.y=310; modal.action='window-wide'; modal.handoffWindow='wide'; modal.handoffElapsed=.8
            local pose=Life.pose(data,'host'); pose.x,pose.y=350,310
            assert(step('start',{window='wide'}).ok)
            local battle=Shootout.new(quest,data,Catalog,'wide',960,720)
            local other=assert(Shootout.forActor(battle,data,Catalog,'companion'))
            assert(battle.gun.borrowed and battle.gun.actorId=='host' and other.gun.borrowed and other.gun.actorId=='companion')
            assert(require('game.first_person_shooting').rounds(other.gun,guest,quest)==48)
            assert(host.ammo['22lr']==0 and guest.ammo['22lr']==0 and Schema.validate(data))
        ''')


class GuestProviderControlsTests(unittest.TestCase):
    setUp = movement.LastStandGuestMotionTests.setUp
    farm = movement.LastStandGuestMotionTests.farm

    def provider(self):
        self.farm()
        self.lua.execute('''
            Provider=require('game.coop_last_stand_provider'); sent={}
            view.runtime.saveData.players.companion.ammo={}; view.runtime.player.x,view.runtime.player.y=300,335
            controller.network.submitCommand=function(_,name,args,epoch,expected)
                sent[#sent+1]={name=name,args=args,epoch=epoch,expected=expected}; return #sent
            end
            assert(view.lastStand:action().id=='borrow-rifle')
        ''')

    def test_keyboard_supply_sends_only_identity_revision_and_waits_for_save(self):
        self.provider()
        self.lua.execute('''
            view:keypressed('e'); local r=sent[1]; assert(r.name=='lastStand.supply' and r.args.mode=='farmhouse')
            assert(r.args.questId==view.lastStand:state().entityId and r.args.revision==view.lastStand:state().revision and not r.args.x)
            for _,scope in ipairs(Provider.scopes(view.runtime.saveData,'companion')) do assert(r.expected[scope]~=nil) end
            assert(view.lastStand.pending and not view:inputAllowed()); view:keypressed('e'); assert(#sent==1)
            controller.network.lastCommandResult={requestId=1,ok=true,savePending=true}
            view.lastStand:update(.1); assert(view.lastStand.pending and not view.lastStand.notice:find('received'))
            controller.network.lastCommandResult={requestId=1,ok=true,durable=true,revision=view.runtime.saveData.coop.revision,
                details={actorId='companion',questId=view.lastStand:state().entityId,loanAmmo=48}}
            view.lastStand:update(.1); assert(not view.lastStand.pending and view.lastStand.notice:find('48'))
        ''')

    def test_controller_and_touch_use_same_supply_action_and_pause_blocks_it(self):
        self.provider()
        self.lua.execute('''
            view.lastStand:keypressed('p'); view.lastStand:gamepadpressed('a'); assert(#sent==0)
            view.lastStand:keypressed('p'); view.lastStand:gamepadpressed('x'); assert(#sent==1)
            controller.network.lastCommandResult={requestId=1,ok=false,reason='stale_revision'}; view.lastStand:update(.1)
            assert(view.lastStand:pointer(700,602,1,true) and #sent==2 and sent[2].args.mode=='farmhouse')
        ''')

    def test_failure_and_area_change_never_advance_story_or_supply_replica(self):
        self.provider()
        self.lua.execute('''
            local q=view.runtime.saveData.lastStand; local revision=q.lifecycle.revision
            view.lastStand:assist(); controller.network.lastCommandResult={requestId=1,ok=false,reason='provider_distance'}
            view.lastStand:update(.1); assert(not view.lastStand.pending and not q.shooterSessions)
            view.lastStand:assist(); assert(view.lastStand.pending)
            assert(Life.move(q,'backyard')); Life.ensure(view.runtime.saveData); view.lastStand:update(.1)
            assert(not view.lastStand.pending and q.lifecycle.revision==revision+1)
            view.lastStand:assist(); assert(#sent==2 and q.state=='backyard' and not q.shooterSessions)
        ''')


if __name__ == '__main__':
    unittest.main()
