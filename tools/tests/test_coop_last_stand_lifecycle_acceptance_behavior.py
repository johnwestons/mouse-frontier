"""Authority lifecycle evidence; process/device acceptance remains native work."""
import unittest
import test_coop_last_stand_positions_behavior as position_tests


class LastStandLifecycleAcceptanceTests(unittest.TestCase):
    setUp = position_tests.LastStandPositionTests.setUp
    stand = position_tests.LastStandPositionTests.stand
    positions = position_tests.LastStandPositionTests.positions
    firing = position_tests.LastStandPositionTests.firing

    def lifecycle(self):
        self.firing()
        self.lua.execute('''
            assert(readyPosition().ok)
            function refreshPeer()
                refresh(); states.companion.movementReady=true; states.companion.modalDomain=Life.key(data)
            end
            function nextDefense()
                local pose=Life.pose(data,'host'); pose.x,pose.y=350,310
                modal.x,modal.y=350,310; modal.action='window-wide'; modal.handoffWindow='wide'; modal.handoffElapsed=1
                step('start',{window='wide'}); refreshPeer()
            end
            function supply(id)
                return run(id,'lastStand.supply',{mode='lastStand',encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision})
            end
            function selected(id)
                return id=='host' and quest.weaponSession or quest.shooterSessions[id].weaponSession
            end
            function shot(id)
                local gun=selected(id); local window=quest.combat.defenders[id].windowId
                local x,y=Window.slotPosition(Window.layout(window,960,720),1)
                return {mode='lastStand',encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision,
                    weaponId=gun.borrowed and 'loan:'..id or gun.itemId,
                    x=math.floor(x/960*1000000+.5),y=math.floor(y/720*1000000+.5)}
            end
            function restartAuthority(admit)
                data=assert(Schema.migrate(saved)); quest=data.lastStand
                host=Players.forActor(data,'host'); guest=Players.forActor(data,'companion')
                modal.questId=quest.lifecycle.entityId; refreshPeer()
                service=Authority.new({campaign=data,sessionId='lifecycle-restart',clock=function() return 100 end,
                    checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
                if admit~=false then service:admit('companion',1) end
                require('game.coop_last_stand_progression').install(service,positionContext)
                Positions.install(service,positionContext); require('game.coop_guns').install(service,positionContext)
            end
            writes=0
        ''')

    def test_intermission_requires_fresh_guest_readiness_and_retains_partial_loan(self):
        self.lifecycle()
        self.lua.execute('''
            local ownId=selected('companion').itemId; assert(supply('companion').ok)
            quest.shooterSessions.companion.weaponSessions[ownId].magazine=2
            local gun=selected('companion'); gun.magazine=4; gun.cooldown=.3; quest.shooterSessions.companion.loanAmmo=47
            local ammo=guest.ammo['22lr']; local oldPhase=quest.combat.phaseRevision
            quest.combat.result='intermission'; quest.combat.stage=2; step('advance',{action='result'})
            assert(quest.lifecycle.mode=='interior' and quest.intermission==2 and not occupied('companion'))
            assert(selected('companion').magazine==4 and selected('companion').cooldown==.3 and quest.shooterSessions.companion.loanAmmo==47)
            nextDefense(); assert(quest.combat.phaseRevision>oldPhase and not occupied('companion'))
            assert(gunCover('companion',true).reason=='position_expired')
            assert(readyPosition().ok and selected('companion').borrowed and selected('companion').magazine==4)
            assert(selected('companion').cooldown==.3 and guest.ammo['22lr']==ammo and quest.shooterSessions.companion.loanAmmo==47)
            assert(quest.shooterSessions.companion.weaponSessions[ownId].magazine==2)
            assert(Schema.validate(saved))
        ''')

    def test_retreat_retry_changes_phase_without_restoring_actor_health_or_ammo(self):
        self.lifecycle()
        self.lua.execute('''
            host.health=7; guest.health=9; selected('host').magazine=3; selected('companion').magazine=2
            local hostAmmo,guestAmmo=host.ammo['22lr'],guest.ammo['22lr']; local phase=quest.combat.phaseRevision
            quest.combat.result='retreat'; quest.combat.retreatReason='wounded'; quest.phaseCheckpoint=60; quest.holdElapsed=77
            local old=args({action='ready',window='tall',phaseRevision=phase})
            assert(run('companion','lastStand.retry',args()).reason=='host_only')
            local r=step('retry'); refreshPeer(); assert(r.ok and quest.lifecycle.mode=='shootout')
            assert(quest.combat.phaseRevision==phase+1 and quest.holdElapsed==60 and quest.recoveries==1)
            assert(host.health==7 and guest.health==9 and selected('host').magazine==3 and selected('companion').magazine==2)
            assert(host.ammo['22lr']==hostAmmo and guest.ammo['22lr']==guestAmmo and not occupied('companion'))
            assert(run('companion','lastStand.position',old).reason=='stale_phase')
            assert(readyPosition('host','wide').ok and readyPosition().ok)
            assert(selected('companion').magazine==2 and guest.health==9 and Schema.validate(saved))
        ''')

    def test_retreat_result_to_interior_and_restart_keep_both_personal_sessions(self):
        self.lifecycle()
        self.lua.execute('''
            assert(supply('companion').ok); selected('companion').magazine=5; selected('companion').reloadTimer=.4
            quest.shooterSessions.companion.loanAmmo=43; selected('host').magazine=2
            local hostId=selected('host').itemId; local phase=quest.combat.phaseRevision
            quest.combat.result='retreat'; quest.phaseCheckpoint=60; quest.holdElapsed=79
            step('advance',{action='result'}); assert(quest.lifecycle.mode=='interior' and quest.combat.phaseRevision==phase+2)
            restartAuthority(); assert(not occupied('host') and not occupied('companion'))
            assert(quest.firingPositions.host=='wide' and quest.firingPositions.companion=='tall')
            nextDefense(); assert(readyPosition().ok)
            assert(selected('host').itemId==hostId and selected('host').magazine==2)
            assert(selected('companion').borrowed and selected('companion').magazine==5 and selected('companion').reloadTimer==.4)
            assert(quest.shooterSessions.companion.loanAmmo==43 and guest.ammo['22lr']==9 and Schema.validate(saved))
        ''')

    def test_host_restart_reacquires_without_persisting_occupancy_or_granting_ammo(self):
        self.lifecycle()
        self.lua.execute('''
            selected('companion').magazine=3; selected('companion').reloadTimer=.7; selected('host').magazine=2
            local hostId,guestId=selected('host').itemId,selected('companion').itemId
            assert(service:checkpointNow()); restartAuthority()
            assert(next(service.activityState.positionOccupancy.windows)==nil)
            assert(gunCover('companion',true).reason=='position_expired')
            states.companion.movementReady=false; assert(readyPosition().reason=='position_unavailable')
            states.companion.movementReady=true
            assert(readyPosition('host','wide').ok and readyPosition().ok)
            assert(selected('host').itemId==hostId and selected('host').magazine==2)
            assert(selected('companion').itemId==guestId and selected('companion').magazine==3 and selected('companion').reloadTimer==.7)
            assert(host.ammo['22lr']==20 and guest.ammo['22lr']==9 and Schema.validate(saved))
        ''')

    def test_paused_quest_loan_reclaim_restores_exact_cached_owned_magazines(self):
        self.lifecycle()
        self.lua.execute('''
            local hostId,guestId=selected('host').itemId,selected('companion').itemId
            selected('host').magazine=2; selected('companion').magazine=3
            assert(supply('host').ok and supply('companion').ok)
            quest.weaponSessions[hostId].cooldown=.2; quest.shooterSessions.companion.weaponSessions[guestId].reloadTimer=.7
            step('withdraw'); modal.x,modal.y=480,620; modal.action='exit-backyard'; step('advance',{action='backyard'})
            modal.x,modal.y=480,605; modal.action='return-stop'; step('withdraw')
            assert(quest.state=='paused' and quest.weaponSession==nil and quest.shooterSessions.companion.weaponSession==nil)
            assert(quest.loanAmmo==0 and quest.shooterSessions.companion.loanAmmo==0)
            assert(quest.weaponSessions[hostId].magazine==2 and quest.shooterSessions.companion.weaponSessions[guestId].magazine==3)
            modal.scoutReady=true; step('advance',{action='resume'})
            modal.x,modal.y=480,360; modal.action='enter-interior'; step('advance',{action='interior'})
            nextDefense(); assert(readyPosition().ok)
            assert(selected('host').itemId==hostId and selected('host').magazine==2 and selected('host').cooldown==.2,'host cached gun reset')
            assert(selected('companion').itemId==guestId and selected('companion').magazine==3 and selected('companion').reloadTimer==.7,'guest cached gun reset')
            assert(host.ammo['22lr']==20 and guest.ammo['22lr']==9 and Schema.validate(saved))
        ''')

    def test_shared_finishing_shots_and_restored_receipt_settle_one_kill_once(self):
        self.lifecycle()
        self.lua.execute('''
            for _,target in ipairs(quest.targets) do target.status='hidden' end
            local target=quest.targets[1]; target.status='exposed'; target.health=.01
            local hostRequest=assert(service:prepareRequest('host','gun.fire',shot('host')))
            local guestRequest=assert(service:prepareRequest('companion','gun.fire',shot('companion')))
            local r=service:execute('companion',1,guestRequest); assert(r.ok and r.durable and r.result.hit,r.reason)
            assert(quest.kills==1 and target.status=='dying' and guest.ammo['22lr']==8)
            assert(service:execute('host',0,hostRequest).reason=='stale_revision' and host.ammo['22lr']==20)
            local morale,integrity=quest.enemyMorale,quest.positionIntegrity
            local fingerprint=assert(require('game.net.codec').encode(guestRequest,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
            restartAuthority()
            assert(quest.kills==1 and quest.enemyMorale==morale and quest.positionIntegrity==integrity)
            local receipt=service:receipt('companion',1,guestRequest.sessionId,guestRequest.requestId,fingerprint)
            assert(receipt.ok and receipt.durable and receipt.result.hit and quest.kills==1 and guest.ammo['22lr']==8)
            assert(service:execute('companion',1,guestRequest).reason=='wrong_session')
            assert(readyPosition('host','wide').ok and readyPosition().ok)
            local after=run('host','gun.fire',shot('host')); assert(after.ok and not after.result.hit)
            assert(quest.kills==1 and guest.ammo['22lr']==8 and host.ammo['22lr']==19 and Schema.validate(saved))
        ''')

    def test_victory_reward_and_joined_return_remain_host_owned_and_once_only(self):
        self.lifecycle()
        self.lua.execute('''
            local cx,cy=guest.playerX,guest.playerY; local hostReturnX,hostReturnY=quest.returnX,quest.returnY
            assert(supply('host').ok and supply('companion').ok)
            quest.combat.result='victory'; step('advance',{action='result'}); refreshPeer()
            assert(quest.victory and not occupied('companion') and not quest.weaponSession and not quest.shooterSessions.companion.weaponSession)
            assert(quest.loanAmmo==0 and quest.shooterSessions.companion.loanAmmo==0)
            quest.residentChecked=true; quest.woundedTreated=true; quest.positionIntegrity=70
            modal.x,modal.y=300,335; modal.action='talk-fox'
            assert(run('companion','lastStand.advance',args({action='reward'})).reason=='host_only')
            local scrap=data.scrap; failSave=true
            local request=assert(service:prepareRequest('host','lastStand.advance',args({action='reward'})))
            local r=service:execute('host',0,request); assert(r.ok and r.savePending and data.scrap==scrap+36)
            assert(service:execute('host',0,request).savePending and data.scrap==scrap+36)
            failSave=false; assert(service:retryCheckpoint()); assert(service:execute('host',0,request).durable)
            refreshPeer(); step('advance',{action='returning'})
            assert(run('companion','lastStand.advance',args({action='complete'})).reason=='host_only')
            step('advance',{action='complete'}); assert(quest.completed and quest.lifecycle.mode=='complete')
            assert(host.playerX==hostReturnX and host.playerY==hostReturnY and guest.playerX==cx and guest.playerY==cy)
            assert(not Life.active(data) and not occupied('companion') and data.scrap==scrap+36)
            restartAuthority(); assert(quest.completed and quest.rewardClaimed and data.scrap==scrap+36 and not Life.active(data))
            assert(Schema.validate(saved))
        ''')

    def test_resident_check_is_host_owned_durable_and_does_not_progress_scene(self):
        self.lifecycle()
        self.lua.execute('''
            quest.combat.result='victory'; step('advance',{action='result'}); refreshPeer()
            local pose=Life.pose(data,'host'); pose.x,pose.y=710,335
            modal.x,modal.y=710,335; modal.action='talk-gecko'
            local revision=quest.lifecycle.revision; local scrap=data.scrap
            assert(run('companion','lastStand.advance',args({action='resident'})).reason=='host_only')
            failSave=true; writes=0
            local request=assert(service:prepareRequest('host','lastStand.advance',args({action='resident'})))
            local r=service:execute('host',0,request)
            assert(r.ok and r.savePending and not r.durable and r.result.action=='resident')
            assert(quest.residentChecked and quest.conversations['talk-gecko'] and not quest.rewardClaimed)
            assert(service:execute('host',0,request).savePending and writes==1)
            failSave=false; assert(service:retryCheckpoint()); assert(service:execute('host',0,request).durable)
            assert(saved.lastStand.residentChecked and saved.lastStand.conversations['talk-gecko'])
            assert(quest.lifecycle.revision==revision and quest.lifecycle.mode=='interior' and data.scrap==scrap)
            assert(action('advance',{action='resident'}).durable and data.scrap==scrap and quest.lifecycle.revision==revision)
        ''')

    def test_scout_resident_check_uses_saved_backyard_proximity(self):
        self.lifecycle()
        self.lua.execute('''
            quest.combat.result='victory'; step('advance',{action='result'}); refreshPeer()
            modal.x,modal.y=480,620; modal.action='exit-backyard'; step('advance',{action='backyard'}); refreshPeer()
            modal.x,modal.y=370,410; modal.action='talk-scout'
            assert(action('advance',{action='resident'}).reason=='resident_unavailable')
            local pose=Life.pose(data,'host'); pose.x,pose.y=370,410
            local revision=quest.lifecycle.revision; local r=step('advance',{action='resident'})
            assert(r.ok and r.durable and quest.residentChecked and quest.conversations['talk-scout'])
            assert(quest.lifecycle.revision==revision and quest.lifecycle.mode=='backyard' and not quest.rewardClaimed)
        ''')

    def test_resident_check_rejects_pre_victory_wrong_npc_and_forged_arguments(self):
        self.lifecycle()
        self.lua.execute('''
            assert(action('advance',{action='resident'}).reason=='transition_unavailable')
            quest.combat.result='victory'; step('advance',{action='result'}); refreshPeer()
            modal.x,modal.y=710,335; modal.action='talk-gecko'
            assert(action('advance',{action='resident',resident='talk-gecko'}).reason=='invalid_args')
            assert(action('advance',{action='resident'}).reason=='resident_unavailable')
            local pose=Life.pose(data,'host'); pose.x,pose.y=710,335
            modal.action='talk-fox'; assert(action('advance',{action='resident'}).reason=='resident_unavailable')
            assert(not quest.residentChecked and not quest.rewardClaimed and Schema.validate(saved))
        ''')


if __name__ == '__main__':
    unittest.main()
