"""Last Stand story authority, modal revisions, checkpoints and restore."""
import unittest
import test_coop_battles_behavior as tactical


class LastStandProgressionTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def stand(self):
        self.lua.execute('''
            setup(); data.scene='stop'; data.location=12; data.stopped=true
            Life=require('game.coop_last_stand_lifecycle'); Personal=require('game.coop_last_stand_state')
            Shootout=require('game.last_stand_shootout'); Sessions=require('game.coop_shooter_sessions')
            data.lastStand={state='waiting',version=1}; quest=data.lastStand; Life.ensure(data)
            state={screen='game',scene='stop',x=412,y=563}
            modal={active=true,questId=quest.lifecycle.entityId,revision=1,mode='approach',scoutReady=true}
            require('game.coop_last_stand_progression').install(service,{catalog=Catalog,
                actorState=function() return state end,lastStandScene=function() return modal end})
            function args(extra)
                local a={questId=quest.lifecycle.entityId,revision=quest.lifecycle.revision}
                for k,v in pairs(extra or {}) do a[k]=v end; return a
            end
            function action(name,extra,id) return run(id or 'host','lastStand.'..name,args(extra)) end
            function refresh()
                modal.mode=quest.lifecycle.mode; modal.revision=quest.lifecycle.revision
            end
            function step(name,extra)
                local r=action(name,extra); assert(r.ok,r.reason); refresh(); return r
            end
            function enter()
                step('offer'); step('accept'); step('advance',{action='arrive'})
                modal.x=480; modal.y=365; modal.action='enter-interior'; step('advance',{action='interior'})
            end
            function start()
                enter(); modal.x=350; modal.y=310; modal.action='window-wide'
                local pose=Life.pose(data,'host'); pose.x,pose.y=350,310
                modal.handoffWindow='wide'; modal.handoffElapsed=.8
                step('start',{window='wide'})
            end
            function victory()
                start(); quest.combat.result='victory'; step('advance',{action='result'})
                quest.residentChecked=true; modal.x=300; modal.y=335; modal.action='talk-fox'
            end
            writes=0
        ''')

    def test_offer_accept_and_scene_proximity_save_exact_host_return_position(self):
        self.stand()
        self.lua.execute('''
            local guestBefore=guest.ammo['22lr']; step('offer'); local r=step('accept')
            assert(r.durable and saved.lastStand.state=='escort' and quest.returnX==412 and quest.returnY==563)
            assert(quest.originStop==12 and quest.lifecycle.revision==3 and quest.lifecycle.entityId==modal.questId)
            step('advance',{action='arrive'})
            modal.x=200; modal.y=400; modal.action='enter-interior'
            assert(action('advance',{action='interior'}).reason=='transition_unavailable')
            modal.x=480; modal.y=365; step('advance',{action='interior'})
            assert(quest.conversations['enter-interior'] and guest.ammo['22lr']==guestBefore and Schema.validate(saved))
        ''')

    def test_guest_cannot_make_any_story_decision(self):
        self.stand()
        self.lua.execute('''
            for _,name in ipairs({'offer','accept','decline','start','advance','retry','withdraw'}) do
                assert(action(name,{},'companion').reason=='host_only')
            end
            assert(writes==0 and quest.state=='waiting' and quest.lifecycle.revision==1)
        ''')

    def test_forged_fields_and_stale_modal_revision_are_rejected_without_cost(self):
        self.stand()
        self.lua.execute('''
            for _,extra in ipairs({{scrap=999},{x=0},{actorId='host'},{revision=0},{revision=1.5}}) do
                assert(action('offer',extra).reason=='invalid_args')
            end
            local old=args(); step('offer')
            assert(run('host','lastStand.accept',old).reason=='stale_phase')
            assert(action('accept',{questId='e99999'}).reason=='quest_unavailable')
            modal.revision=1; assert(action('accept').reason=='stale_phase')
            assert(writes==1 and quest.state=='waiting')
        ''')

    def test_start_requires_actual_window_and_finished_handoff(self):
        self.stand()
        self.lua.execute('''
            enter(); modal.x=350; modal.y=310; modal.action='window-wide'; modal.handoffWindow='wide'; modal.handoffElapsed=.1
            assert(action('start',{window='wide'}).reason=='window_unavailable')
            modal.handoffElapsed=.8; assert(action('start',{window='tall'}).reason=='window_unavailable')
            modal.x=500; assert(action('start',{window='wide'}).reason=='window_unavailable')
            modal.x=350; local pose=Life.pose(data,'host'); pose.x,pose.y=350,310
            local r=step('start',{window='wide'})
            assert(r.durable and quest.combat and quest.targets and quest.weaponSession.actorId=='host')
            assert(saved.lastStand.lifecycle.mode=='shootout' and Schema.validate(saved))
        ''')

    def test_withdraw_invalidates_gun_phase_and_preserves_ammunition(self):
        self.stand()
        self.lua.execute('''
            start(); local phase=quest.combat.phaseRevision; local ammo=host.ammo['22lr']; local mag=quest.weaponSession.magazine
            step('withdraw'); assert(quest.state=='interior' and quest.combat.phaseRevision==phase+1)
            assert(host.ammo['22lr']==ammo and quest.weaponSession.magazine==mag and Schema.validate(saved))
        ''')

    def test_result_retry_preserves_health_and_costs_and_refreshes_both_defenders(self):
        self.stand()
        self.lua.execute('''
            start(); quest.combat.result='retreat'; quest.combat.retreatReason='wounded'; quest.holdElapsed=78; quest.phaseCheckpoint=60
            local hp=host.health; local ammo=host.ammo['22lr']; local phase=quest.combat.phaseRevision
            local r=step('advance',{action='result'})
            assert(r.result.action=='retreat' and r.result.retreatReason=='wounded')
            assert(quest.state=='interior' and quest.holdElapsed==60 and quest.intermission==2 and quest.recoveries==1)
            assert(quest.combat.phaseRevision==phase+2 and host.health==hp and host.ammo['22lr']==ammo)
            assert(quest.combat.result==nil and Schema.validate(saved))
        ''')

    def test_manual_retry_uses_new_modal_and_combat_revisions(self):
        self.stand()
        self.lua.execute('''
            start(); quest.combat.result='retreat'; local rev=quest.lifecycle.revision; local phase=quest.combat.phaseRevision
            local r=step('retry'); assert(r.result.action=='retry')
            assert(quest.lifecycle.revision==rev+1 and quest.combat.phaseRevision==phase+1 and quest.state=='shootout')
            assert(action('retry').reason=='retry_unavailable' and Schema.validate(saved))
        ''')

    def test_intermission_and_victory_cannot_be_requested_from_live_combat(self):
        self.stand()
        self.lua.execute('''
            start(); assert(action('advance',{action='result'}).reason=='transition_unavailable')
            quest.combat.result='intermission'; quest.combat.stage=2; step('advance',{action='result'})
            assert(quest.intermission==2 and not quest.victory and quest.state=='interior')
            modal.x=350; modal.y=310; modal.action='window-wide'; modal.handoffWindow='wide'; modal.handoffElapsed=1
            local pose=Life.pose(data,'host'); pose.x,pose.y=350,310
            step('start',{window='wide'}); assert(quest.combat.result==nil)
            quest.combat.result='victory'; step('advance',{action='result'})
            assert(quest.victory and quest.weaponSession==nil and quest.state=='interior' and Schema.validate(saved))
        ''')

    def test_reward_is_one_durable_command_and_return_uses_host_position(self):
        self.stand()
        self.lua.execute('''
            victory(); quest.woundedTreated=true; quest.positionIntegrity=70
            local scrap,food,goodwill=data.scrap,data.resources.food,data.goodwill
            local r=step('advance',{action='reward'})
            assert(r.result.rewardScrap==36 and data.scrap==scrap+36 and data.resources.food==food+2 and data.goodwill==goodwill+3)
            assert(action('advance',{action='reward'}).reason=='transition_unavailable')
            step('advance',{action='returning'}); step('advance',{action='complete'})
            assert(quest.completed and quest.completedAtStop==12 and host.playerX==412 and host.playerY==563)
            assert(Schema.validate(saved) and saved.lastStand.lifecycle.mode=='complete')
        ''')

    def test_failed_reward_checkpoint_replays_once_without_double_payment(self):
        self.stand()
        self.lua.execute('''
            victory(); local scrap=data.scrap; failSave=true
            local request=assert(service:prepareRequest('host','lastStand.advance',args({action='reward'})))
            local r=service:execute('host',0,request); assert(r.ok and r.savePending and not r.durable)
            assert(data.scrap==scrap+28 and service.pendingSave and modal.mode=='interior')
            assert(service:execute('host',0,request).savePending and data.scrap==scrap+28)
            failSave=false; assert(service:retryCheckpoint())
            r=service:execute('host',0,request); assert(r.durable and not r.savePending and data.scrap==scrap+28)
            assert(saved.lastStand.rewardClaimed and Schema.validate(saved))
        ''')

    def test_pause_reclaims_loans_and_can_only_resume_at_origin(self):
        self.stand()
        self.lua.execute('''
            enter(); modal.x=480; modal.y=620; modal.action='exit-backyard'; step('advance',{action='backyard'})
            quest.loanActive=true; quest.loanAmmo=48; modal.x=480; modal.y=605; modal.action='return-stop'; step('withdraw')
            assert(quest.state=='paused' and quest.loanAmmo==0 and not quest.loanActive)
            data.location=13; assert(action('advance',{action='resume'}).reason=='transition_unavailable')
            data.location=12; modal.scoutReady=true; step('advance',{action='resume'})
            assert(quest.state=='backyard' and quest.originStop==12 and Schema.validate(saved))
        ''')

    def test_accept_does_not_restore_previous_window_into_fresh_defense(self):
        self.stand()
        self.lua.execute('''
            quest.lastWindow='tall'; quest.firingPositions={host='tall'}; quest.positionVersion=1
            step('offer'); local r=step('accept')
            assert(r.ok and r.durable and quest.state=='escort' and quest.lastWindow==nil)
            assert(quest.positionVersion==1 and next(quest.firingPositions)==nil and Schema.validate(saved))
        ''')

    def test_decline_keeps_host_save_and_stop_identity(self):
        self.stand()
        self.lua.execute('''
            local identity=quest.lifecycle.entityId; step('offer'); step('decline')
            assert(quest.state=='declined' and quest.declinedStop==12 and quest.lifecycle.mode=='approach')
            step('offer'); step('accept'); assert(quest.originStop==12 and quest.lifecycle.entityId==identity)
        ''')

    def test_marked_lifecycle_rejects_malformed_pairs_and_migrates_legacy(self):
        self.stand()
        self.lua.execute('''
            local old=assert(Schema.copy(data)); old.version=39; old.lastStand.lifecycle=nil; old.lastStand.state='backyard'
            local loaded=assert(Schema.migrate(old)); assert(loaded.version==44 and loaded.lastStand.lifecycle.mode=='backyard')
            assert(Schema.validate(loaded)); loaded.lastStand.lifecycle.mode='shootout'; assert(not Schema.validate(loaded))
            assert(not Schema.migrate(loaded)); loaded.lastStand.lifecycle.mode='backyard'; loaded.lastStand.lifecycle.revision=0
            assert(not Schema.migrate(loaded))
        ''')

    def test_pause_and_other_host_activities_block_progression(self):
        self.stand()
        self.lua.execute('''
            modal.paused=true; assert(action('offer').reason=='quest_unavailable'); modal.paused=false
            state.activeActivity='firstAid'; assert(action('offer').reason=='quest_unavailable'); state.activeActivity=nil
            modal.blocked=true; assert(action('offer').reason=='quest_unavailable'); modal.blocked=false
            state.traveling=true; assert(action('offer').reason=='quest_unavailable'); assert(writes==0)
        ''')


if __name__ == '__main__':
    unittest.main()
