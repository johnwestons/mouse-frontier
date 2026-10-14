"""Canonical range rules preserve Source geometry without device side effects."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class RangeSourceRulesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=function() return .5 end}}
            F=require('tools.tests.lua.coop_fixtures'); Players=require('game.coop_players')
            Items=require('game.item_instances'); Catalog=require('game.catalog'); Range=require('game.shooting_range')
            Codec=require('game.net.codec')
            data=F.campaign(2); assert(F.enroll(data)); actor=Players.forActor(data,'host')
            Items.write(actor,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); actor.ammo['22lr']=30
            spot={preferences={motion='stationary',material='paper',targetPattern='stay-up',stageLength=30,distance=50},highScores={},rewardTier=0}
            function fresh(name)
                if name then Items.write(actor,nil,{kind='equipment',index=2},name) end
                s=assert(Range.serverNew(actor,spot,Catalog)); assert(Range.serverStart(s,actor,Catalog)); return s
            end
            calls=0
            function rng(a,b) calls=calls+1; return a and a or .4 end
            function tick(dt) return Range.serverUpdate(s,dt,actor,Catalog,rng) end
            function first() for i=1,3 do tick(.08) end; return assert(s.targets[1]) end
        ''')

    def test_canonical_shot_never_uses_camera_global_rng_or_audio_and_preserves_cost(self):
        self.lua.execute('''
            fresh(); local target=first(); local before=actor.ammo['22lr']
            require('game.world_view').toWorld=function() error('camera called') end
            math.random=function() error('global RNG called') end
            local loaded=s.loaded
            assert(Range.serverFire(s,actor,Catalog,target.x,target.y,rng))
            assert(actor.ammo['22lr']==before-1 and s.loaded==loaded-1 and s.hits==1 and s.score>0)
            assert(not s.aimX and not s.aimMode and not s.spot and not s.fireHeld)
            assert(Codec.encode(s))
        ''')

    def test_permanent_target_is_finite_and_same_source_geometry_at_all_distances(self):
        self.lua.execute('''
            for _,distance in ipairs(Range.targetDistances) do
                spot.preferences.distance=distance; fresh(); local target=first()
                local offline=assert(Range.new(actor,spot,Catalog)); assert(Range.keypressed(offline,'return',actor,Catalog)=='start')
                for i=1,3 do Range.update(offline,.08,actor,Catalog) end
                local old=offline.targets[1]
                assert(target.x==old.x and target.y==old.y and target.scale==old.scale and target.radius==old.radius)
                assert(target.permanent and target.life==0 and old.life==math.huge and Codec.encode(s))
                for i=1,50 do tick(.08) end; assert(s.targets[1].id==target.id and s.targets[1].permanent)
            end
        ''')

    def test_start_setup_weapon_switch_and_new_venue_do_not_refill_cached_owned_gun(self):
        self.lua.execute('''
            fresh(); local target=first(); assert(Range.serverFire(s,actor,Catalog,target.x,target.y,rng))
            local loaded,cooldown=s.loaded,s.cooldown
            assert(Range.serverSetup(s)); assert(Range.serverStart(s,actor,Catalog))
            assert(s.loaded==loaded and s.cooldown==cooldown)
            Items.write(actor,nil,{kind='inventory',index=1},'frontier-9mm-glock'); actor.ammo['9mm']=12
            assert(Range.serverSetup(s)); assert(Range.serverConfigure(s,actor,Catalog,'weapon',1))
            assert(Range.serverConfigure(s,actor,Catalog,'weapon',-1)); assert(s.loaded==loaded and s.cooldown==cooldown)
            local nextSession=assert(Range.serverNew(actor,spot,Catalog,{previous=s}))
            assert(nextSession.itemId==s.itemId and nextSession.loaded==loaded and nextSession.cooldown==cooldown)
        ''')

    def test_restore_rejects_foreign_cache_and_clamps_only_real_ammo_without_resetting_cooldown(self):
        self.lua.execute('''
            fresh(); s.cooldown=.7; Range.serverCache(s); actor.ammo['22lr']=2
            assert(Range.serverRestore(s,actor,Catalog)); assert(s.loaded==2 and s.cooldown==.7)
            s.weaponSessions[s.itemId].weapon='frontier-9mm-glock'
            local ok,why=Range.serverRestore(s,actor,Catalog); assert(not ok and why=='invalid_gun_cache')
        ''')

    def test_sectioned_scoring_breaks_only_hit_section_then_replaces_all_broken_target(self):
        self.lua.execute('''
            spot.preferences.material='sectioned'; fresh(); local target=first()
            assert(Range.serverFire(s,actor,Catalog,target.x,target.y,rng))
            assert(s.sectionsHit==1 and target.sections[13].hit and not target.sections[1])
            for i=1,7 do tick(.08) end; assert(target.sections[13].broken)
            for i=1,13 do target.sections[i]={hit=true,broken=true} end
            tick(.08); assert(target.clearing and not target.permanent)
            for i=1,9 do tick(.08) end
            assert(#s.targets==0 or s.targets[1].id~=target.id)
        ''')

    def test_shotgun_spread_uses_supplied_rng_and_bounded_holes_and_dirt(self):
        self.lua.execute('''
            actor.ammo['12-gauge']=100; fresh('sawed-off-shotgun'); first()
            math.random=function() error('global RNG') end
            for i=1,20 do
                s.loaded=s.capacity; s.cooldown=0; s.reloadTimer=0
                assert(Range.serverFire(s,actor,Catalog,30,55,rng))
            end
            assert(calls>40 and #s.dirtImpacts<=8)
            local t=s.targets[1]
            for i=1,20 do s.loaded=s.capacity;s.cooldown=0;assert(Range.serverFire(s,actor,Catalog,t.x,t.y,rng)) end
            assert(#t.impacts<=16 and Codec.encode(s,{maxBytes=65536,maxEntries=4096}))
        ''')

    def test_tube_reload_and_boomerang_return_keep_authored_timers_and_no_client_refill(self):
        self.lua.execute('''
            fresh(); first(); s.loaded=2; Range.serverCache(s); assert(Range.serverReload(s,actor,Catalog))
            assert(s.tubeReloadTotalRounds and s.weaponAction=='reload')
            local duration=s.reloadTimer
            for i=1,math.ceil(duration/.08)+1 do tick(.08) end
            assert(s.loaded==s.capacity and s.reloadTimer==0)
            fresh('scrap-boomerang'); first(); assert(Range.serverFire(s,actor,Catalog,30,55,rng))
            assert(s.loaded==0 and s.weaponViewSequence and not s.weaponViewSequence.definition)
            local p=Range.presentation(s,{aimX=300,aimY=200})
            for i=1,100 do Range.updatePresentation(p,.08) end
            assert(p.loaded==0 and s.loaded==0 and s.weaponViewSequence.index==1)
            for i=1,100 do tick(.08) end; assert(s.loaded==s.capacity and not s.weaponViewSequence)
        ''')

    def test_input_mapper_covers_all_original_options_and_never_mutates_record(self):
        self.lua.execute('''
            s=assert(Range.serverNew(actor,spot,Catalog)); local before=Codec.encode(s)
            for i,kind in ipairs({'weapon','motion','material','pattern','distance','length'}) do
                local p=Range.presentation(s,{menuRow=i})
                local v=assert(Range.inputIntent(p,'keypressed','right'))
                assert(v.action=='configure' and v.kind==kind and v.direction==1)
                local mouse=Range.inputIntent(p,'mousepressed',700,205+(i-1)*50,1)
                assert(mouse.kind==kind and mouse.row==i)
            end
            assert(before==Codec.encode(s)); assert(Range.inputIntent(s,'keypressed','return').action=='start')
        ''')

    def test_round_clock_requires_authoritative_tick_and_completion_reward_is_once_shared_tier(self):
        self.lua.execute('''
            fresh(); s.score=1200;s.shots=10;s.hits=8;s.time=.04
            local p=Range.presentation(s); Range.updatePresentation(p,.08)
            assert(s.time==.04 and p.time==.04); assert(tick(.08)=='complete')
            local gained=0; local helper={add=function(_,n) gained=gained+n end}
            local result=Range.serverComplete(s,actor,spot,helper); assert(result.gained==3 and gained==3)
            assert(Range.serverComplete(s,actor,spot,helper)==result and gained==3)
            assert(Range.serverStart(s,actor,Catalog)); s.score=1200;s.shots=10;s.hits=8
            assert(Range.serverComplete(s,actor,spot,helper).gained==0 and gained==3)
        ''')

    def test_original_offline_range_audit_preserves_original_configuration_rewards_and_calibration(self):
        self.lua.execute('assert(Range.audit(Catalog).ready)')

    def test_canonical_draw_and_fire_keep_target_coordinates_under_source_camera_zoom_and_pan(self):
        self.lua.execute('''
            fresh();local target=first(); cameras=0;zoom=1;pan=0;stack={};drawn={}
            local g={};love.graphics=g
            g.push=function() stack[#stack+1]={zoom,pan} end
            g.pop=function() local v=table.remove(stack);zoom,pan=v[1],v[2] end
            for _,key in ipairs({'setColor','rectangle','circle','line','translate','scale','setLineWidth'}) do g[key]=function() end end
            g.newQuad=function() return {} end
            local image={getDimensions=function() return 400,300 end}
            g.draw=function(img,quad,x,y) if img==image then drawn[#drawn+1]={x=x*zoom+pan,y=y*zoom+pan} end end
            require('game.typography').drawText=function() end
            require('game.world_view').configure({apply=function() cameras=cameras+1;zoom=2;pan=100 end,
                toWorld=function(x,y) return (x-100)/2,(y-100)/2 end})
            local p=Range.presentation(s,{aimX=target.x,aimY=target.y})
            Range.draw(p,actor,{targets=image},{},Catalog,false)
            assert(cameras==0 and drawn[1].x==target.x and drawn[1].y==target.y and #stack==0)
            assert(Range.serverFire(s,actor,Catalog,p.aimX,p.aimY,rng) and s.hits==1)
            drawn={};p.canonicalView=nil;Range.draw(p,actor,{targets=image},{},Catalog,false)
            assert(cameras==1 and drawn[1].x==target.x*2+100 and #stack==0)
            assert(not s.canonicalView)
        ''')

    def test_finite_permanent_targets_render_full_alpha_and_pop_up_targets_keep_original_fade(self):
        self.lua.execute('''
            local g={};love.graphics=g;alpha=1;rendered={}
            for _,key in ipairs({'push','pop','rectangle','circle','line','translate','scale','rotate','setLineWidth','print'}) do g[key]=function() end end
            g.setColor=function(_,_,_,a) alpha=a or 1 end
            g.newQuad=function() return {} end
            g.getFont=function() return {getWidth=function() return 8 end,getHeight=function() return 14 end} end
            local atlas={getDimensions=function() return 400,300 end}
            local sectioned={getDimensions=function() return 528,712 end}
            local frame={getWidth=function() return 128 end,getHeight=function() return 174 end}
            g.draw=function(image,quad,x,y)
                if image==atlas or image==sectioned or image==frame then rendered[#rendered+1]={alpha=alpha,x=x,y=y,image=image} end
            end
            require('game.typography').drawText=function() end
            local assets={targets=atlas,sectionedTarget=sectioned,sectionedFrame=frame}
            for _,material in ipairs({'paper','steel','clay','sectioned'}) do
                spot.preferences.material=material;spot.preferences.targetPattern='stay-up';fresh();first();tick(.08)
                local t=s.targets[1];assert(t.permanent and t.life==0)
                rendered={};Range.draw(Range.presentation(s),actor,assets,{},Catalog,false)
                assert(#rendered>0)
                for _,r in ipairs(rendered) do assert(r.alpha==1,'invisible permanent '..material) end
                assert(t.life==0 and t.permanent)
            end
            spot.preferences.material='paper';spot.preferences.targetPattern='pop-up';fresh();local t=first()
            assert(not t.permanent);t.age=.075;t.life=.075;rendered={}
            Range.draw(Range.presentation(s),actor,assets,{},Catalog,false)
            assert(rendered[1].alpha==.5 and rendered[1].y==t.y+9)
            spot.preferences.material='sectioned';fresh();t=first();assert(t.permanent and t.life==0);rendered={}
            Range.draw(Range.presentation(s),actor,assets,{},Catalog,false)
            assert(rendered[1].image==frame and rendered[1].alpha==1)
            t.clearing=true;t.permanent=false;t.life=.275;rendered={}
            Range.draw(Range.presentation(s),actor,assets,{},Catalog,false)
            assert(rendered[1].image==frame and rendered[1].alpha==.5)
        ''')

    def test_actual_guest_replica_start_and_replay_render_readiness_from_exact_owned_instance(self):
        self.lua.execute('''
            Entities=require('game.coop_entities');GameState=require('game.net.game_state')
            local guest=Players.forActor(data,'companion')
            Items.write(guest,nil,{kind='equipment',index=2},'frontier-22-lever-rifle');guest.ammo['22lr']=54
            data.scene='stop';data.stopped=true;spot.version=Range.version;spot.x=760;spot.y=565
            data.stopLayouts['2']={shootingRange=spot};assert(Entities.ensure(data))
            local lane=assert(Range.serverNew(guest,spot,Catalog));lane.version=1;lane.spotId=spot.entityId;lane.roundRevision=1
            data.rangeSessions={version=1,companion=lane};assert(Entities.ensure(data))
            local g={};love.graphics=g
            for _,key in ipairs({'push','pop','rectangle','circle','line','translate','scale','setLineWidth'}) do g[key]=function() end end
            g.setColor=function(r,b,c,a) color={r,b,c,a} end
            g.rectangle=function(mode,x,y) if mode=='fill' and ((x==500 and y==542) or (x==238 and y==548)) then readyColor=color[1] end end
            local labels={};require('game.typography').drawText=function(_,value) labels[value]=true end
            local function projected()
                local producer=GameState.producer();local message=assert(producer:capture(data,true))
                local replica=GameState.replica();assert(replica:apply(message));local own=replica:actor('companion')
                assert(not own.itemIdentity and not Items.enabled(own) and Items.identified(own))
                return own,own.rangeSessions.companion
            end
            local function draw(own,s,enabled,label)
                readyColor=nil;labels={};Range.draw(Range.presentation(s),own,nil,{},Catalog,false)
                assert(readyColor==(enabled and .28 or .16) and labels[label])
            end
            local own,s=projected();draw(own,s,true,'START COURSE')
            local available=Range.ownedWeapons(own,Catalog);assert(available[#available]==lane.itemId or available[1]==lane.itemId)
            assert(Range.serverStart(lane,guest,Catalog));lane.score=125;lane.shots=1;lane.hits=1
            Range.serverComplete(lane,data,spot,{add=function() end});own,s=projected();draw(own,s,true,'REPLAY')
            guest.ammo['22lr']=0;own,s=projected();draw(own,s,false,'REPLAY')
            guest.ammo['22lr']=54;Items.owned(guest,lane.itemId).durability=0
            own,s=projected();draw(own,s,false,'REPLAY')
            Items.owned(guest,lane.itemId).durability=100;own,s=projected()
            s.itemId='i999999';s.weapons[s.selected]=s.itemId;draw(own,s,false,'REPLAY')
            local legacy={location=2,equipment={[2]='frontier-22-lever-rifle'},inventory={},ammo={['22lr']=54}}
            local old=assert(Range.new(legacy,{preferences={},highScores={}},Catalog))
            draw(legacy,old,true,'START COURSE');assert(Range.ownedWeapons(legacy,Catalog)[1]=='frontier-22-lever-rifle')
        ''')


class RangeHostAdapterTests(unittest.TestCase):
    def setUp(self):
        RangeSourceRulesTests.setUp(self)
        self.lua.execute('''
            spot.version=Range.version; spot.x=760;spot.y=565;spot.entityId='e123'
            data.scene='stop';data.stopped=true
            layout={shootingRange=spot}; submits={}; saved=0;sounds=0;active=false;pending=false
            runtime={state='game',scene='stop',saveData=data,player={x=760,y=565},session={networkMode='host'}}
            ui={playSfx=function() sounds=sounds+1 end}
            local tables={'scenery','util','house','family','wildlife','mice','events','stopHelpProgression',
                'crowCaravans','crowCaravanArea','expeditionAreas','roamingMobs','mobImages','mobIdleImages',
                'mobWalkImages','mobAttackImages','mobHitImages','mobDeathImages','mobRangedImages'}
            context={runtime=runtime,ui=ui,catalog=Catalog,shootingRange=Range,width=960,height=720,
                clock=function() return clock or 0 end,
                stops={ensure=function() return layout end},settlements={clamp=function(x,y) return x,y end},
                stopSludges={new=function() return {} end},expeditionRuntime={new=function() return {} end},
                getBeginEncounter=function() return function() end end,getIsWeapon=function() return function() return true end end,
                isFurnitureItem=function() return false end,writeSave=function() saved=saved+1 end,
                rangeView=function() if active then local view=Range.presentation(s);view.leaseId='l1';view.roundRevision=1;view.spotId=spot.entityId;return view end end,
                rangeCommands=function(name,args)
                    submits[#submits+1]={name=name,args=args}
                    if denied then return {ok=false,reason='denied'} end
                    if name=='range.acquire' then s=assert(Range.serverNew(actor,spot,Catalog));active=true
                    elseif name=='range.configure' then
                        if args.action=='start' then assert(Range.serverStart(s,actor,Catalog))
                        elseif args.action=='change' then assert(Range.serverConfigure(s,actor,Catalog,args.kind,args.direction)) end
                    elseif name=='range.fire' then assert(Range.serverFire(s,actor,Catalog,args.x/1000000*960,args.y/1000000*720,rng))
                    elseif name=='range.ammo' then assert(Range.serverBuyAmmo(s,actor,Catalog))
                    elseif name=='range.release' then active=false end
                    if pending then runtime.session.checkpointPending=true end
                    return {ok=true,savePending=pending,result={leaseId='l1'}}
                end}
            for _,key in ipairs(tables) do context[key]={} end
            world=require('game.world_scene').new(context)
        ''')

    def test_actual_host_controls_submit_checked_commands_without_direct_save_or_spending(self):
        self.lua.execute('''
            assert(world.beginShootingRange()); assert(submits[1].name=='range.acquire')
            local before=actor.ammo['22lr']; assert(world.rangeInput('keypressed','return')=='start')
            assert(submits[2].name=='range.configure' and submits[2].args.action=='start')
            first(); world.rangeUpdate(.01); local target=s.targets[1]
            assert(world.rangeInput('mousepressed',target.x,target.y,1)=='shot')
            local request=submits[#submits]; assert(request.name=='range.fire' and request.args.weaponId==s.itemId)
            assert(actor.ammo['22lr']==before-1 and saved==0 and s.hits==1)
            assert(runtime.shootingRange.aimX==target.x and not s.aimX)
            assert(world.rangeInput('keypressed','escape')=='close' and not runtime.shootingRange and saved==0)
        ''')

    def test_pending_acquisition_and_result_are_hidden_until_durable_and_private_menu_stops_inputs(self):
        self.lua.execute('''
            pending=true; assert(world.beginShootingRange()); assert(not runtime.shootingRange)
            world.rangeUpdate(.1); assert(not runtime.shootingRange)
            runtime.session.checkpointPending=false;pending=false;world.rangeUpdate(.1); assert(runtime.shootingRange)
            ui.escMenuOpen=true; local count=#submits; assert(not world.rangeInput('keypressed','return'));world.rangeUpdate(.1)
            assert(#submits==count and s.phase=='lobby')
            ui.escMenuOpen=false;denied=true;assert(world.rangeInput('keypressed','return')=='dry');assert(s.phase=='lobby')
        ''')

    def test_real_runtime_authority_checkpoints_host_controls_release_and_delayed_sound_once(self):
        self.lua.execute('''
            Schema=require('game.save_schema'); Entities=require('game.coop_entities')
            data.scene='stop';data.stopped=true;data.coop.randomState=12345;data.stopLayouts['2']=layout;spot.entityId=nil;assert(Entities.ensure(data))
            local session=require('game.game_session').new(); session:activate(data,runtime.player);session:setScreen('game')
            session.networkMode='host'; runtime.session=session;clock=0;writes=0;failSave=false
            commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog,
                clock=function() return clock end,
                rangeState=function() return world.rangeCommandState() end,
                checkpoint=function(value) writes=writes+1;if failSave then return false end;savedCampaign=assert(Schema.copy(value));return true end})
            context.rangeCommands=function(name,args) return commands.submit(name,args) end
            context.rangeView=commands.rangeView;world=require('game.world_scene').new(context)
            assert(world.beginShootingRange());assert(runtime.shootingRange and savedCampaign.rangeSessions.host)
            assert(world.rangeInput('keypressed','right')=='select');assert(data.rangeSessions.host.weapon)
            assert(world.rangeInput('keypressed','return')=='start');clock=.2;commands.advanceRange(.08);clock=.28;commands.advanceRange(.08)
            world.rangeUpdate(0);s=data.rangeSessions.host;local target=assert(s.targets[1]);local ammo=actor.ammo['22lr'];local audio=sounds
            failSave=true;local outcome=world.rangeInput('mousepressed',target.x,target.y,1)
            assert(outcome~='shot' and session.checkpointPending and actor.ammo['22lr']==ammo-1 and sounds==audio)
            world.rangeUpdate(.08);assert(sounds==audio)
            failSave=false;assert(commands.retryCheckpoint());world.rangeUpdate(0)
            assert(sounds==audio+1 and savedCampaign.players.host.ammo['22lr']==ammo-1)
            world.rangeUpdate(0);assert(sounds==audio+1)
            failSave=true;assert(world.rangeInput('keypressed','escape')~='close' and runtime.shootingRange and session.checkpointPending)
            world.rangeUpdate(.08);assert(runtime.shootingRange)
            failSave=false;assert(commands.retryCheckpoint());world.rangeUpdate(0)
            assert(not runtime.shootingRange and saved==0 and Schema.validate(savedCampaign))
        ''')

    def test_host_startup_closes_legacy_offline_overlay_without_undoing_spent_ammo(self):
        self.lua.execute('''
            runtime.session.networkMode='offline';assert(world.beginShootingRange())
            Range.keypressed(runtime.shootingRange,'return',data,Catalog)
            Range.keypressed(runtime.shootingRange,'space',data,Catalog)
            local ammo=actor.ammo['22lr'];runtime.session.networkMode='host';world.rangeUpdate(.08)
            assert(not runtime.shootingRange and actor.ammo['22lr']==ammo and #submits==0)
            assert(not world.rangeCommandState().active and not world.rangeCommandState().ready)
            assert(world.beginShootingRange() and submits[1].name=='range.acquire')
        ''')

    def test_shared_network_stop_closes_owned_view_and_rehost_restores_exact_saved_cache(self):
        self.lua.execute('''
            local session=require('game.game_session').new();session:activate(data,runtime.player);session:setScreen('game')
            session.networkMode='host';runtime.session=session
            local fs=F.filesystem();closed=0
            local lp=require('game.coop_local_play').new({runtime=runtime,session=session,commands={},filesystem=fs,
                clock=function() return 0 end,discovery={stop=function() end},onStop=world.closeSharedRange})
            lp.network={close=function() closed=closed+1 end}
            assert(world.beginShootingRange());assert(world.rangeInput('keypressed','return')=='start');first();world.rangeUpdate(0)
            local target=s.targets[1];assert(world.rangeInput('mousepressed',target.x,target.y,1)=='shot')
            local ammo,loaded,cooldown=actor.ammo['22lr'],s.loaded,s.cooldown
            assert(lp:stop());assert(closed==1 and session.networkMode=='offline' and not runtime.shootingRange)
            world.rangeUpdate(.08)
            assert(not runtime.shootingRange and not world.rangeCommandState().ready)
            assert(actor.ammo['22lr']==ammo and s.loaded==loaded and s.cooldown==cooldown)
            local previous=s
            context.rangeCommands=function(name,args)
                assert(name=='range.acquire');s=assert(Range.serverNew(actor,spot,Catalog,{previous=previous}));active=true
                return {ok=true,result={leaseId='l1'}}
            end
            runtime.session.networkMode='host';assert(world.beginShootingRange())
            assert(runtime.shootingRange.loaded==loaded and s.loaded==loaded and s.cooldown==cooldown and actor.ammo['22lr']==ammo)
            assert(world.closeSharedRange() and not world.closeSharedRange())
            runtime.session.networkMode='offline';assert(world.beginShootingRange());local offline=runtime.shootingRange
            world.rangeUpdate(.08);assert(runtime.shootingRange==offline and not world.closeSharedRange())
        ''')

    def test_real_checkpoint_wrapper_reacquires_exact_lane_after_failed_host_shot_and_reload(self):
        self.lua.execute('''
            Schema=require('game.save_schema');Entities=require('game.coop_entities')
            Items.write(actor,nil,{kind='equipment',index=2},'frontier-9mm-smg');actor.ammo['9mm']=50
            data.coop.randomState=12345;data.stopLayouts['2']=layout;spot.entityId=nil;assert(Entities.ensure(data))
            local session=require('game.game_session').new();session:activate(data,runtime.player);session:setScreen('game')
            session.networkMode='host';runtime.session=session;clock=0;failSave=false
            commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog,
                clock=function() return clock end,rangeState=function() return world.rangeCommandState() end,
                checkpoint=function(value) if failSave then return false end;savedCampaign=assert(Schema.copy(value));return true end})
            context.rangeCommands=commands.submit;context.rangeView=commands.rangeView;world=require('game.world_scene').new(context)
            local app={update=function(dt) world.rangeUpdate(dt) end,draw=function() end,
                keypressed=function(key) return world.rangeInput('keypressed',key) end,
                keyreleased=function(key) return world.rangeInput('keyreleased',key) end}
            require('game.coop_checkpoint_host').wrap(app,{runtime=runtime,ui=ui,commands=commands,
                screenToGame=function(x,y) return x,y end,audio={update=function() end},requestQuit=function() end,
                neutralize=function() world.rangeInput('keyreleased','space') end,
                serviceSession=function(dt) commands.advanceRange(dt) end})
            assert(world.beginShootingRange());assert(world.rangeInput('keypressed','return')=='start')
            assert(world.rangeInput('keypressed','v')=='mode');assert(data.rangeSessions.host.fireMode=='auto')
            clock=.16;commands.advanceRange(.08);clock=.24;commands.advanceRange(.08);world.rangeUpdate(0)
            local s=data.rangeSessions.host;local t=assert(s.targets[1]);local old=runtime.shootingRange.leaseId
            local identity=s.entityId;local round=s.roundRevision;local audio=sounds
            failSave=true;assert(world.rangeInput('mousepressed',t.x,t.y,1)~='shot')
            s=data.rangeSessions.host;local expected=assert(Schema.copy(s));local ammo=actor.ammo['9mm']
            app.update(.08);assert(session.checkpointPending and not commands.rangeView('host'))
            failSave=false;app.keypressed('r');assert(not session.checkpointPending and not commands.rangeView('host'))
            local stale=commands.submit('range.fire',{leaseId=old,roundRevision=round,weaponId=s.itemId,x=1,y=1})
            assert(not stale.ok and stale.reason=='lease_expired')
            app.update(0);s=data.rangeSessions.host;local resumed=assert(runtime.shootingRange)
            assert(resumed.leaseId~=old and s.entityId==identity and s.roundRevision==round)
            for _,field in ipairs({'phase','time','clock','loaded','cooldown','reloadTimer','weaponAction','weaponActionElapsed','shots','hits','score'}) do
                assert(s[field]==expected[field],'resume changed '..field)
            end
            assert(actor.ammo['9mm']==ammo and sounds==audio+1)
            app.update(0);assert(data.rangeSessions.host.shots==expected.shots and actor.ammo['9mm']==ammo and sounds==audio+1)
            failSave=true;assert(world.rangeInput('keypressed','r')=='reload')
            expected=assert(Schema.copy(data.rangeSessions.host));assert(expected.reloadTimer>0 and expected.weaponAction=='reload')
            old=runtime.shootingRange.leaseId;app.update(.08);failSave=false;app.keypressed('r');app.update(0)
            s=data.rangeSessions.host;assert(runtime.shootingRange.leaseId~=old and s.entityId==identity)
            for _,field in ipairs({'phase','time','clock','loaded','cooldown','reloadTimer','weaponAction','weaponActionElapsed','shots','hits','score'}) do assert(s[field]==expected[field]) end
            assert(actor.ammo['9mm']==ammo and sounds==audio+1 and Schema.validate(savedCampaign))
        ''')

    def test_reacquire_keeps_transient_failure_neutral_and_closes_after_permanent_context_change(self):
        self.lua.execute('''
            assert(world.beginShootingRange());local model=runtime.shootingRange;active=false
            context.rangeCommands=function(name,args) submits[#submits+1]={name=name,args=args};return {ok=false,reason='busy'} end
            world.rangeUpdate(0);assert(runtime.shootingRange==model and not world.rangeCommandState().ready)
            local count=#submits;world.rangeUpdate(.08);assert(#submits==count)
            assert(not world.rangeInput('keypressed','return') and model.phase=='lobby')
            runtime.player.x=spot.x+67;world.rangeUpdate(0);assert(not runtime.shootingRange and #submits==count)
        ''')

    def test_reacquire_never_reopens_after_death_story_scene_epoch_or_slot_change(self):
        for change in ['data.health=0', "runtime.scene='train'", "runtime.state='event'",
                       'runtime.lastStand={capture=true}', 'data.coop.sceneEpoch=data.coop.sceneEpoch+1',
                       "runtime.saveData=F.campaign(3)"]:
            with self.subTest(change=change):
                self.setUp()
                self.lua.execute('''
                    assert(world.beginShootingRange());active=false;local count=#submits
                ''' + change + '''
                    world.rangeUpdate(0);assert(not runtime.shootingRange and #submits==count)
                    assert(not world.rangeCommandState().ready)
                ''')

    def test_carried_touch_ads_weapon_switch_draws_and_sends_the_same_checked_shot_point(self):
        self.lua.execute('''
            Schema=require('game.save_schema');Entities=require('game.coop_entities');Aim=require('game.mobile_weapon_aim')
            Items.write(actor,nil,{kind='inventory',index=1},'frontier-9mm-smg');actor.ammo['9mm']=50
            data.coop.randomState=12345;data.stopLayouts['2']=layout;spot.entityId=nil;assert(Entities.ensure(data))
            local session=require('game.game_session').new();session:activate(data,runtime.player);session:setScreen('game')
            session.networkMode='host';runtime.session=session;clock=0
            local commands=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog,
                clock=function() return clock end,rangeState=function() return world.rangeCommandState() end,
                checkpoint=function(value) return Schema.validate(value) end})
            context.rangeCommands=function(name,args) lastRequest={name=name,args=args};return commands.submit(name,args) end
            context.rangeView=commands.rangeView;world=require('game.world_scene').new(context)
            assert(world.beginShootingRange());assert(world.rangeInput('keypressed','return')=='start')
            world.rangeInput('mousemoved',500,400,true);world.rangeInput('keypressed','lshift')
            local old=runtime.shootingRange.aimX;assert(runtime.shootingRange.aimMode=='sights')
            assert(world.rangeInput('keypressed','tab')=='setup');assert(world.rangeInput('keypressed','right')=='select')
            assert(runtime.shootingRange.weapon=='frontier-9mm-smg');assert(world.rangeInput('keypressed','return')=='start')
            local model=runtime.shootingRange;local calibrated={}
            Aim.set(calibrated,500,400,model.weapon,'sights',960,720,{left=30,top=55,right=930,bottom=625})
            assert(math.abs(model.aimX-calibrated.aimX)<1e-9 and model.aimX~=old)
            world.rangeUpdate(0);model=runtime.shootingRange;assert(model.aimX==calibrated.aimX)
            local g={};love.graphics=g
            for _,key in ipairs({'push','pop','setColor','rectangle','circle','line','translate','scale','setLineWidth'}) do g[key]=function() end end
            require('game.typography').drawText=function() end
            local image={getWidth=function() return 256 end,getHeight=function() return 512 end,getDimensions=function() return 256,512 end}
            local views={get=function() return image end,anchor=function(_,weapon) return require('game.first_person_weapon_manifest').anchorFor(weapon) end}
            g.draw=function(img,x,y,rotation,scale)
                if img==image then local anchor=views:anchor(model.weapon);drawPoint={x=x+anchor.x*256*scale,y=y+anchor.y*512*scale} end
            end
            Range.draw(model,actor,{weaponViews=views},{},Catalog,true)
            assert(drawPoint and math.abs(drawPoint.x-calibrated.aimX)<1e-9 and math.abs(drawPoint.y-calibrated.aimY)<1e-9)
            local ammo=actor.ammo['9mm'];assert(world.rangeInput('keypressed','space')=='shot')
            assert(lastRequest.name=='range.fire' and lastRequest.args.weaponId==model.itemId)
            assert(math.abs(lastRequest.args.x/1000000*960-drawPoint.x)<.001)
            assert(math.abs(lastRequest.args.y/1000000*720-drawPoint.y)<.001 and actor.ammo['9mm']==ammo-1)
        ''')


if __name__ == '__main__':
    unittest.main()
