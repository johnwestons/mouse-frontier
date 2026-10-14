"""Personal Last Stand loans, durable supply and shared host input authority."""
import unittest
import test_coop_last_stand_guns_behavior as guns


class LastStandSupplyTests(unittest.TestCase):
    setUp = guns.LastStandGunCommandsTests.setUp
    stand = guns.LastStandGunCommandsTests.stand

    def loans(self):
        self.stand()
        self.lua.execute('''
            function supply(id,extra)
                local a={mode='lastStand',encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision}
                for key,value in pairs(extra or {}) do a[key]=value end
                return run(id,'lastStand.supply',a)
            end
            function loanArgs(id,extra)
                local a=ga(id,{weaponId='loan:'..id}); for key,value in pairs(extra or {}) do a[key]=value end
                return a
            end
            function loanShot(id)
                local x,y=point(id); return run(id,'gun.fire',loanArgs(id,{x=x,y=y}))
            end
            function selected(id) return id=='host' and quest.weaponSession or quest.shooterSessions[id].weaponSession end
            function pool(id) return id=='host' and quest or quest.shooterSessions[id] end
        ''')

    def test_first_loans_and_shots_have_separate_pools_and_public_owner_identity(self):
        self.loans()
        self.lua.execute('''
            local gh,hg=guest.ammo['22lr'],host.ammo['22lr']
            local r=supply('companion'); assert(r.ok and r.durable,r.reason)
            assert(r.result.weaponId=='loan:companion' and r.result.suppliedRounds==48 and r.result.rounds==48)
            assert(pool('companion').loanAmmo==48 and not quest.loanActive and quest.loanAmmo==0)
            assert(supply('host').ok and quest.loanAmmo==48)
            r=loanShot('companion'); assert(r.ok and r.result.hit,r.reason)
            assert(pool('companion').loanAmmo==47 and quest.loanAmmo==48)
            assert(guest.ammo['22lr']==gh and host.ammo['22lr']==hg)
            assert(selected('host').actorId=='host' and selected('companion').actorId=='companion')
            assert(require('game.net.gun_results').valid('gun.fire',r.result) and Schema.validate(saved))
        ''')

    def test_supply_cannot_refill_loaded_loan_or_bypass_cover_cooldown_reload(self):
        self.loans()
        self.lua.execute('''
            assert(supply('companion').ok)
            assert(supply('companion').reason=='supply_unavailable')
            assert(cover('companion',true).ok); assert(loanShot('companion').reason=='in_cover')
            assert(cover('companion',false).ok); tick(.3); assert(loanShot('companion').ok)
            assert(supply('companion').reason=='weapon_busy')
            assert(run('companion','gun.select',loanArgs('companion')).reason=='weapon_busy')
            tick(1); assert(run('companion','gun.reload',loanArgs('companion')).ok)
            assert(supply('companion').reason=='weapon_busy' and pool('companion').loanAmmo==47)
            assert(guest.ammo['22lr']==9 and not quest.loanActive)
        ''')

    def test_loan_owner_cannot_be_forged_for_fire_reload_selector_or_supply(self):
        self.loans()
        self.lua.execute('''
            assert(supply('host').ok and supply('companion').ok)
            local x,y=point('companion')
            for _,name in ipairs({'gun.fire','gun.reload','gun.select','gun.mode'}) do
                local a=loanArgs('companion',{weaponId='loan:host'})
                if name=='gun.fire' then a.x=x; a.y=y end
                assert(run('companion',name,a).reason=='ownership')
            end
            for _,extra in ipairs({{weaponId='loan:host'},{actorId='host'},{rounds=999},{loanAmmo=999},{suppliedRounds=48}}) do
                assert(supply('companion',extra).reason=='invalid_args')
            end
            assert(quest.loanAmmo==48 and pool('companion').loanAmmo==48 and writes==2)
        ''')

    def test_first_loan_can_be_selected_and_cached_owned_gun_is_not_refilled(self):
        self.loans()
        self.lua.execute('''
            local ownId=ggun.itemId; assert(shoot('companion').ok); tick(1)
            local mag=ggun.magazine
            local r=run('companion','gun.select',loanArgs('companion')); assert(r.ok,r.reason)
            assert(r.result.weaponId=='loan:companion' and pool('companion').loanAmmo==48)
            assert(run('companion','gun.select',ga('companion',{weaponId=ownId})).ok)
            assert(selected('companion').itemId==ownId and selected('companion').magazine==mag)
            assert(supply('companion').ok and pool('companion').loanAmmo==48)
            assert(selected('companion').borrowed and guest.ammo['22lr']==8 and Schema.validate(data))
        ''')

    def test_empty_loan_resupply_grants_twelve_once_and_preserves_host_pool(self):
        self.loans()
        self.lua.execute('''
            assert(supply('host').ok and supply('companion').ok)
            pool('companion').loanAmmo=0; selected('companion').magazine=0
            local request=assert(service:prepareRequest('companion','lastStand.supply',
                {mode='lastStand',encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision}))
            local r=service:execute('companion',1,request); assert(r.ok and r.durable,r.reason)
            assert(r.result.suppliedRounds==12 and selected('companion').magazine==12 and pool('companion').loanAmmo==12)
            assert(service:execute('companion',1,request).durable and pool('companion').loanAmmo==12 and quest.loanAmmo==48)
            assert(supply('companion').reason=='supply_unavailable' and guest.ammo['22lr']==9)
        ''')

    def test_partial_loan_reload_and_exact_history_restore_without_extra_ammo(self):
        self.loans()
        self.lua.execute('''
            assert(supply('companion').ok); assert(loanShot('companion').ok); tick(1)
            assert(run('companion','gun.reload',loanArgs('companion')).ok); tick(.75)
            local mag,timer=selected('companion').magazine,selected('companion').reloadTimer
            local copy=assert(Schema.migrate(data)); local own=Players.forActor(copy,'companion')
            local gun=Shooting.new(own,Catalog,copy.lastStand,960,720)
            assert(gun.borrowed and gun.actorId=='companion' and gun.magazine==mag and gun.reloadTimer==timer)
            assert(copy.lastStand.shooterSessions.companion.loanAmmo==47 and copy.lastStand.loanAmmo==0)
            assert(own.ammo['22lr']==9 and Schema.validate(copy))
        ''')

    def test_failed_supply_save_and_receipt_retry_never_duplicate_allocation(self):
        self.loans()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','lastStand.supply',
                {mode='lastStand',encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision}))
            failSave=true; local r=service:execute('companion',1,request); assert(r.ok and r.savePending)
            assert(service:execute('companion',1,request).ok and pool('companion').loanAmmo==48)
            assert(supply('host').reason=='save_pending'); failSave=false; assert(service:retryCheckpoint())
            assert(service:execute('companion',1,request).durable and pool('companion').loanAmmo==48)
            local copy=assert(Schema.migrate(saved)); local fresh=Authority.new({campaign=copy,sessionId='loan-restarted'})
            fresh:admit('companion',1)
            local fingerprint=assert(require('game.net.codec').encode(request,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
            local receipt=fresh:receipt('companion',1,service.sessionId,request.requestId,fingerprint)
            assert(receipt.ok and receipt.durable and receipt.result.weaponId=='loan:companion')
            assert(copy.lastStand.shooterSessions.companion.loanAmmo==48 and not copy.lastStand.loanActive)
        ''')

    def test_stale_phase_interior_unready_and_downed_supply_are_denied(self):
        self.loans()
        self.lua.execute('''
            local old=quest.combat.phaseRevision; advance()
            assert(supply('companion',{phaseRevision=old}).reason=='stale_phase')
            quest.state='interior'; assert(supply('companion').reason=='shooter_unavailable'); quest.state='shootout'
            ready.active=false; assert(supply('companion').reason=='shooter_unavailable'); ready.active=true
            guest.health=1; assert(supply('companion').reason=='shooter_unavailable')
            assert(not pool('companion').loanActive and writes==0 and guest.ammo['22lr']==9)
        ''')

    def test_no_owned_firearm_still_gets_actor_scoped_house_rifle(self):
        self.loans()
        self.lua.execute('''
            Items.write(guest,nil,{kind='equipment',index=2},nil); guest.ammo['22lr']=0
            local r=supply('companion'); assert(r.ok,r.reason)
            assert(selected('companion').borrowed and pool('companion').loanAmmo==48 and guest.ammo['22lr']==0)
            assert(loanShot('companion').ok and pool('companion').loanAmmo==47 and Schema.validate(data))
        ''')

    def test_public_loan_and_supply_results_reject_foreign_owner_weapon_and_pool_claims(self):
        self.loans()
        self.lua.execute('''
            local r=supply('companion'); assert(r.ok,r.reason)
            local Results=require('game.net.gun_results'); local public=assert(Results.project('lastStand.supply',r.result))
            assert(Results.valid('lastStand.supply',public))
            for _,change in ipairs({{weaponId='loan:host'},{weapon='frontier-9mm-smg'},
                {mode='ambush'},{suppliedRounds=999},{reloading=true},{phaseRevision=0}}) do
                local bad=assert(Schema.copy(public)); for key,value in pairs(change) do bad[key]=value end
                assert(not Results.valid('lastStand.supply',bad))
            end
            public.actorId='host'; public.weaponId='loan:host'; public.mode='ambush'; public.phaseRevision=nil
            public.fired=true; public.hit=false; public.suppliedRounds=nil; public.reloading=nil
            assert(not Results.valid('gun.fire',public))
        ''')

    def hostInput(self):
        self.loans()
        self.lua.execute('''
            reports=0; calls={}
            love.math.random=function() return .5 end
            WorldView.toWorld=function(x,y) return x,y end
            Window.buildingSolid=function() return false end
            Shooting.playReport=function() reports=reports+1; assert(writes>0) end
            Shootout.setCommands(battle,function(name,args)
                calls[#calls+1]={name=name,args=args}; return run('host',name,args)
            end)
            local x,y=Window.slotPosition(Window.layout('wide',960,720),1)
            Shootout.setAim(battle,x,y)
        ''')

    def test_host_fire_reload_cover_mode_and_weapon_controls_use_authority(self):
        self.hostInput()
        self.lua.execute('''
            assert(Shootout.setFireHeld(battle,'keyboard',true,data,960,720,Catalog))
            Shootout.setFireHeld(battle,'keyboard',false); assert(calls[1].name=='gun.fire' and host.ammo['22lr']==19)
            assert(reports==1 and next(battle.targetEffects) and #battle.effects>0 and guest.ammo['22lr']==9)
            assert(Shootout.setCover(battle,true) and calls[2].name=='gun.cover' and battle.ducking)
            assert(Shootout.setCover(battle,false)); tick(1)
            assert(Shootout.reload(battle,data) and calls[#calls].name=='gun.reload'); tick(20)
            assert(Shootout.cycleFireMode(battle)==battle.gun.fireMode and calls[#calls].name=='gun.mode')
            assert(Shootout.cycleWeapon(battle,data,Catalog) and calls[#calls].name=='gun.select')
            assert(battle.gun.borrowed and quest.loanAmmo==48 and calls[#calls].args.weaponId=='loan:host')
            assert(Schema.validate(data) and writes==#calls)
        ''')

    def test_host_supply_and_switch_back_preserve_private_aim_and_owned_magazine(self):
        self.hostInput()
        self.lua.execute('''
            local x,y=battle.gun.aimX,battle.gun.aimY; Shootout.setADS(battle,true)
            assert(Shootout.fire(battle,data,960,720,Catalog)); tick(1)
            local id,mag=battle.gun.itemId,battle.gun.magazine
            assert(Shootout.supply(battle,data,Catalog) and calls[#calls].name=='lastStand.supply')
            assert(battle.gun.borrowed and quest.loanAmmo==48 and battle.gun.ads and battle.gun.aimX==x and battle.gun.aimY==y)
            assert(Shootout.cycleWeapon(battle,data,Catalog))
            assert(battle.gun.itemId==id and battle.gun.magazine==mag and host.ammo['22lr']==19)
            assert(battle.gun.ads and battle.gun.aimX==x and battle.gun.aimY==y)
        ''')

    def test_host_checkpoint_failure_stops_extra_cost_and_plays_no_unconfirmed_report(self):
        self.hostInput()
        self.lua.execute('''
            failSave=true; assert(Shootout.fire(battle,data,960,720,Catalog))
            assert(host.ammo['22lr']==19 and reports==0 and service.pendingSave)
            tick(1); assert(not Shootout.fire(battle,data,960,720,Catalog) and host.ammo['22lr']==19)
            assert(not Shootout.supply(battle,data,Catalog) and not quest.loanActive)
            failSave=false; assert(service:retryCheckpoint())
            assert(Shootout.fire(battle,data,960,720,Catalog) and host.ammo['22lr']==18 and reports==1)
        ''')

    def test_offline_callback_fallback_keeps_existing_local_actions(self):
        self.hostInput()
        self.lua.execute('''
            calls={}; Shootout.setCommands(battle,function() return nil end)
            Shooting.playReport=function() reports=reports+1 end
            assert(Shootout.fire(battle,data,960,720,Catalog) and host.ammo['22lr']==19 and writes==0 and #calls==0)
            tick(1); assert(Shootout.supply(battle,data,Catalog) and quest.loanAmmo==48 and writes==0)
            assert(Shootout.setCover(battle,true) and battle.ducking and writes==0)
        ''')

    def test_automatic_held_fire_uses_commands_once_per_authored_cooldown(self):
        self.hostInput()
        self.lua.execute('''
            Items.write(host,nil,{kind='inventory',index=1},'frontier-9mm-smg'); host.ammo['9mm']=30
            local item=host.itemSlots.inventory[1]
            assert(run('host','gun.select',ga('host',{weaponId=item.id})).ok)
            -- Source controls rebind their private gun after an authority switch.
            assert(Shootout.setCover(battle,false)); calls={}; writes=0
            assert(battle.gun.itemId==item.id)
            assert(Shootout.cycleFireMode(battle)=='auto'); calls={}; writes=0
            for _,t in ipairs(quest.targets) do t.status='hidden'; t.timer=999 end
            assert(Shootout.setFireHeld(battle,'controller',true,data,960,720,Catalog))
            Shootout.update(battle,.02,data,Catalog,960,720); assert(host.ammo['9mm']==29 and #calls==1)
            Shootout.update(battle,.1,data,Catalog,960,720); assert(host.ammo['9mm']==28 and #calls==2)
            Shootout.setFireHeld(battle,'controller',false)
            Shootout.update(battle,.2,data,Catalog,960,720); assert(host.ammo['9mm']==28 and writes==2)
        ''')

    def test_mode_and_gun_changes_release_host_held_inputs_after_authority_commit(self):
        self.hostInput()
        self.lua.execute('''
            Items.write(host,nil,{kind='inventory',index=1},'frontier-9mm-smg'); host.ammo['9mm']=30
            assert(run('host','gun.select',ga('host',{weaponId=host.itemSlots.inventory[1].id})).ok)
            assert(Shootout.setCover(battle,false))
            for _,t in ipairs(quest.targets) do t.status='hidden'; t.timer=999 end
            assert(Shootout.setFireHeld(battle,'keyboard',true,data,960,720,Catalog)); tick(1)
            assert(battle.gun.fireHeld and host.ammo['9mm']==29)
            assert(Shootout.cycleFireMode(battle)=='auto')
            assert(not battle.gun.fireHeld and next(battle.fireHeldSources)==nil)
            Shootout.update(battle,.3,data,Catalog,960,720); assert(host.ammo['9mm']==29)
            battle.gun.fireHeld=true; battle.fireHeldSources={touch=true}
            assert(Shootout.supply(battle,data,Catalog))
            assert(not battle.gun.fireHeld and next(battle.fireHeldSources)==nil and quest.loanAmmo==48)
            battle.gun.fireHeld=true; battle.fireHeldSources={controller=true}
            assert(Shootout.cycleWeapon(battle,data,Catalog))
            assert(not battle.gun.fireHeld and next(battle.fireHeldSources)==nil and quest.loanAmmo==48)
        ''')


if __name__ == '__main__':
    unittest.main()
