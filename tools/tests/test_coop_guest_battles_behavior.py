"""Guest battle controls quote owned turns and never simulate the campaign."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestBattleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={keyboard={isDown=function() return false end},mouse={getPosition=function() return -1000,-1000 end}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Catalog=require('game.catalog')
            Players=require('game.coop_players'); Commands=require('game.coop_battles'); Items=require('game.item_instances')
            data=F.campaign(2); assert(F.enroll(data)); data.scene='train'; data.passengers={}
            data.encounters['2']={rolled=true,hasMob=true,resolved=false,tier='easy',mobFiles={Catalog.mobTiers.easy[1]}}
            assert(require('game.coop_entities').ensure(data))
            authority=require('game.coop_authority').new({campaign=data,sessionId='guest-battle',randomSeed=24})
            authority:admit('companion',1)
            Commands.install(authority,{catalog=Catalog,actorState=function() return {screen='game',scene='train'} end})
            local request=assert(authority:prepareRequest('host','battle.begin',{encounterId=data.encounters['2'].entityId}))
            assert(authority:execute('host',0,request).ok)
            copy=assert(Schema.copy(data)); own=Players.forActor(copy,'companion'); b=copy.tacticalBattle.battle
            b.active=2; b.intro=nil; b.obstacles={}; b.tiles[1][4]=1; b.units[3].q,b.units[3].r=2,5
            runtime={saveData=own,battle=b,state='battle',scene='train'}; requests={}
            network={submitCommand=function(self,name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests end}
            camera=setmetatable({zoom=1,panX=0,panY=0,scopes={},scope='guest'},{__index=require('game.camera')})
            view={runtime=runtime,ui={playSfx=function() end},ready=true,focused=true,paused=true,epoch=copy.coop.sceneEpoch,
                camera=camera,mobile={enabled=false},controller={network=network,menuOpen=false},renderer={}}
            view.inventory={toggle=function() runtime.inventoryOpen=not runtime.inventoryOpen end,
                button=function(self,label,x,y,w,h,enabled) return {x=x,y=y,w=w,h=h,enabled=enabled} end,cancelDrag=function() end}
            function view.controller:open() self.menuOpen=true end
            panel=require('game.coop_guest_battles').new(view,{catalog=Catalog,content={},colors={}})
        ''')

    def test_owned_turn_carries_scene_turn_unit_and_every_conflict_scope(self):
        self.lua.execute('''
            assert(panel:submit('battle.guard'))
            local r=requests[1]; assert(r.name=='battle.guard' and r.epoch==view.epoch)
            assert(r.args.unitId=='player:companion' and r.args.turnRevision==copy.tacticalBattle.revision)
            assert(r.args.encounterId==copy.encounters['2'].entityId and r.expected['combat:tactical']==copy.coop.revisions['combat:tactical'])
            for _,scope in ipairs(Commands.scopes(copy)) do assert(r.expected[scope]==(copy.coop.revisions[scope] or 0)) end
            assert(panel.pending and not panel:submit('battle.endTurn') and not b.units[2].guarding)
            assert(data.players.companion.health==own.health and data.tacticalBattle.revision==0)
        ''')

    def test_animation_advances_between_packets_without_changing_the_host(self):
        self.lua.execute('''
            b.intro=1.5; b.introDuration=1.65; b.attackTimer=.4
            b.units[2].moveAnim={fromQ=1,fromR=4,toQ=1,toR=5,t=0,duration=.5}
            local hostIntro=data.tacticalBattle.battle.intro
            panel:update(.2)
            assert(not b.intro and math.abs(b.attackTimer-.2)<.001)
            assert(math.abs(b.units[2].moveAnim.t-.2)<.001)
            assert(data.tacticalBattle.battle.intro==hostIntro)
            local fresh=Schema.copy(copy); fresh.tacticalBattle.battle.attackTimer=.35
            fresh.tacticalBattle.battle.units[2].moveAnim.t=.05
            runtime.saveData=Players.forActor(fresh,'companion'); runtime.battle=fresh.tacticalBattle.battle
            panel:update(.1)
            assert(math.abs(runtime.battle.attackTimer-.1)<.001)
            assert(math.abs(runtime.battle.units[2].moveAnim.t-.3)<.001)
        ''')

    def test_one_press_waits_out_host_animation_and_never_repeats_success(self):
        self.lua.execute('''
            assert(panel:submit('battle.guard'))
            network.lastCommandResult={requestId=1,ok=false,reason='battle_busy'}
            panel:update(.1); assert(panel.pending and #requests==1)
            panel:update(.25); assert(#requests==2 and requests[2].name=='battle.guard')
            assert(not panel:submit('battle.guard'))
            network.lastCommandResult={requestId=2,ok=true,durable=true,revision=copy.coop.revision}
            panel:update(.1); panel:update(1)
            assert(not panel.pending and #requests==2 and panel.lastOutcome.ok)
        ''')

    def test_busy_retry_cannot_cross_turn_focus_or_connection(self):
        self.lua.execute('''
            for _,change in ipairs({function() copy.tacticalBattle.revision=1 end,
                function() view.focused=false end,function() view.controller.network={} end}) do
                copy.tacticalBattle.revision=0; view.focused=true; view.controller.network=network
                panel.pending=nil; network.lastCommandResult=nil
                assert(panel:submit('battle.endTurn'))
                local count=#requests
                network.lastCommandResult={requestId=count,ok=false,reason='battle_busy'}
                panel:update(.01); change(); panel:update(.5)
                assert(#requests==count and not panel.pending)
            end
        ''')

    def test_save_retry_and_replica_revision_hold_pending_without_resubmit(self):
        self.lua.execute('''
            assert(panel:submit('battle.guard')); panel.mode='move'
            network.lastCommandResult={requestId=1,ok=true,savePending=true,revision=copy.coop.revision+1}; panel:update()
            assert(panel.pending and #requests==1)
            network.lastCommandResult.savePending=nil; panel:update(); assert(panel.pending)
            copy.coop.revision=copy.coop.revision+1; panel:update(); assert(panel.pending)
            network.lastCommandResult.durable=true; panel:update()
            assert(not panel.pending and panel.lastOutcome.ok and #requests==1)
        ''')

    def test_actual_owned_heal_checkpoint_retries_once_before_reliable_projection(self):
        self.lua.execute('''
            local live=assert(Schema.copy(copy)); local actor=Players.forActor(live,'companion')
            actor.health=8; live.tacticalBattle.battle.units[2].hp=8
            Items.write(actor,nil,{kind='inventory',index=1},'field-bandage-roll')
            local host=Players.forActor(live,'host')
            Items.write(host,nil,{kind='inventory',index=1},'field-bandage-roll')
            local item=actor.itemSlots.equipment[1].id; local hostItem=host.itemSlots.equipment[1].id
            local saved; local writable=true; local writes=0
            local service=require('game.coop_authority').new({campaign=live,sessionId='battle-ui-retry',
                checkpoint=function(value)
                    writes=writes+1; if not writable then return false end
                    saved=assert(Schema.copy(value)); return true
                end})
            service:admit('companion',3)
            Commands.install(service,{catalog=Catalog,actorState=function() return {screen='battle',scene='train'} end})
            local sent
            network.submitCommand=function(_,name,args,epoch,expected)
                sent={sessionId=service.sessionId,requestId=1,sceneEpoch=epoch,command=name,args=args,expected=expected}
                network.lastCommandResult=service:execute('companion',3,sent); return 1
            end
            local function publish()
                copy=assert(Schema.copy(live)); own=Players.forActor(copy,'companion')
                runtime.saveData=own; runtime.battle=copy.tacticalBattle.battle; b=runtime.battle
            end
            publish(); writable=false; writes=0
            assert(panel:submit('battle.heal')); panel:update()
            assert(service.pendingSave and panel.pending and network.lastCommandResult.savePending)
            assert(runtime.saveData.inventory[1]=='field-bandage-roll' and runtime.saveData.health==8)
            assert(live.players.companion.health==13 and not live.players.companion.inventory[1])
            assert(live.players.host.inventory[1]=='field-bandage-roll' and live.players.host.itemSlots.equipment[1].id==hostItem)
            assert(not panel:submit('battle.heal'))
            writable=true; assert(service:retryCheckpoint())
            network.lastCommandResult=service:execute('companion',3,sent)
            assert(network.lastCommandResult.durable and not service.pendingSave)
            panel:update(); assert(panel.pending) -- Receipt alone does not expose unsynchronized health.
            publish(); panel:update()
            assert(not panel.pending and panel.lastOutcome.ok and runtime.saveData.health==13)
            assert(saved.players.companion.health==13 and not saved.players.companion.inventory[1])
            assert(saved.players.host.inventory[1]=='field-bandage-roll' and saved.players.host.itemSlots.equipment[1].id==hostItem)
            assert(item~=hostItem and writes==2 and saved.tacticalBattle.revision==live.tacticalBattle.revision)
        ''')

    def test_native_checkpoint_comparison_uses_actual_public_projection_and_client_identity(self):
        self.lua.execute('''
            local Checkpoint=require('tools.guest-battle-actions-smoke.checkpoint')
            copy.coop.network={version=1,campaignId=string.rep('a',32),companionId=string.rep('b',32),
                credentialHash=string.rep('c',64),bindingVersion=1}
            copy.coop.randomState=9834567
            local projection=assert(require('game.net.game_state').project(copy)); local public=projection.view
            assert(public.coop.network==nil and public.coop.randomState==nil)
            local expected=Checkpoint.publicSignature(copy); assert(Checkpoint.publicSignature(public)==expected)
            local private=Checkpoint.privateSignature(copy)
            copy.coop.randomState=copy.coop.randomState+1
            assert(Checkpoint.privateSignature(copy)~=private and Checkpoint.publicSignature(copy)==expected)
            local client={campaignId=copy.coop.network.campaignId,
                credential={campaignId=copy.coop.network.campaignId,companionId=copy.coop.network.companionId}}
            assert(Checkpoint.clientIdentity(client,copy.coop.network.campaignId,copy.coop.network.companionId,public))
            client.credential.companionId=string.rep('d',32)
            assert(not Checkpoint.clientIdentity(client,copy.coop.network.campaignId,copy.coop.network.companionId,public))
            assert(not Checkpoint.clientIdentity(nil,copy.coop.network.campaignId,copy.coop.network.companionId,public))
            public.players.companion.ammo['22lr']=1; assert(Checkpoint.publicSignature(public)~=expected)
            public.players.companion.ammo['22lr']=copy.players.companion.ammo['22lr']
            public.tacticalBattle.battle.units[2].hp=public.tacticalBattle.battle.units[2].hp-1
            assert(Checkpoint.publicSignature(public)~=expected)
            public.tacticalBattle.battle.units[2].hp=copy.tacticalBattle.battle.units[2].hp
            public.tacticalBattle.battle.obstacles['4:3']={q=4,r=3,kind='boulders'}
            assert(Checkpoint.publicSignature(public)~=expected)
        ''')

    def test_epoch_or_turn_change_discards_local_preview(self):
        self.lua.execute('''
            panel:update(); panel.mode='move'; panel.selected='player'
            copy.tacticalBattle.revision=1; panel:update(); assert(not panel.mode)
            panel.mode='move'; view.epoch=view.epoch+1; panel:update(); assert(not panel.mode and not panel.selected)
        ''')

    def test_keyboard_never_grants_host_enemy_or_finished_turns(self):
        self.lua.execute('''
            for _,active in ipairs({1,3}) do b.active=active; panel:keypressed('g'); panel:keypressed('space'); assert(#requests==0) end
            b.active=2; b.finished='win'; panel:keypressed('return'); panel:keypressed('g'); assert(#requests==0)
            b.finished=nil; view.focused=false; assert(not panel:submit('battle.guard'))
            view.focused=true; view.controller.menuOpen=true; assert(not panel:submit('battle.guard'))
            view.controller.menuOpen=false; panel:keypressed('g'); assert(requests[1].name=='battle.guard')
        ''')

    def test_move_keyboard_and_pointer_keep_preview_local_and_send_board_intent(self):
        self.lua.execute('''
            panel:update(); panel:keypressed('m'); assert(panel.mode=='move' and b.phase=='select')
            local Grid=require('game.battle_grid'); local x,y=Grid.boardToScreen(1,1,4)
            panel:pointer(x,y,false); assert(requests[1].name=='battle.move' and requests[1].args.q==1 and requests[1].args.r==4)
            assert(b.units[2].q==1 and b.units[2].r==5 and data.tacticalBattle.battle.units[2].r==5)
        ''')

    def test_guest_camera_hit_test_and_focus_targets_are_isolated_from_host(self):
        self.lua.execute('''
            camera:setZoom(2); camera.panX=12; camera.panY=-8
            local Grid=require('game.battle_grid'); local UI=require('game.battle_ui')
            local x,y=Grid.boardToScreen(1,2,5); local sx,sy=panel.worldView.toScreen(x,y)
            local q,r=UI.screenToBoardSpace(panel:context(),sx,sy); assert(q==2 and r==5)
            b.phase='target'; local targets=panel:targets(); assert(#targets==1 and targets[1].id=='cell2:5')
            assert(math.abs(targets[1].rect.x+20-sx)<.001 and require('game.camera').zoom==1)
            panel:keypressed('i'); assert(runtime.inventoryOpen); panel:keypressed('escape'); assert(view.controller.menuOpen)
        ''')

    def test_drawing_uses_disposable_inspection_and_move_state(self):
        self.lua.execute('''
            local UI=require('game.battle_ui'); panel.mode='move'; panel.selected='player'; panel.logScroll=2
            UI.draw=function(ctx)
                assert(ctx.battle~=b and ctx.battle.phase=='move' and ctx.hostControls==false and ctx.worldView==panel.worldView)
                ctx.battle.selected='enemy1'; ctx.battle.phase='select'; ctx.battle.options={'scratch'}
            end
            love.graphics={setColor=function() end,printf=function() end}; panel:draw()
            assert(b.phase=='select' and b.selected~='enemy1' and b.options[1]=='scratch' and data.tacticalBattle.battle.options==nil)
        ''')

    def test_tactical_renderer_uses_private_expedition_frames_and_live_ordinary_art(self):
        self.lua.execute('''
            package.loaded['game.expedition_runtime']={new=function(options)
                atlasOptions=options; return {}
            end}
            local content={scenery={},mobImages={},characterImages={cook={}}}
            view.scene=require('game.coop_scene_view').new({runtime=runtime,ui=view.ui,content=content,catalog=Catalog})
            panel.c.content=content
            local keys={'mobImages','mobIdleImages','mobWalkImages','mobAttackImages','mobHitImages','mobDeathImages','mobRangedImages'}
            for i,key in ipairs(keys) do
                atlasOptions[key]['sludge-badger-boss.png']={frame=i}
            end
            local late={ordinary=true}; content.mobImages['dust-beetle.png']=late
            local ctx=panel:context()
            for i,key in ipairs(keys) do
                assert(ctx[key]['sludge-badger-boss.png'].frame==i and ctx[key]==atlasOptions[key])
                assert(not (content[key] or {})['sludge-badger-boss.png'])
            end
            assert(ctx.mobImages['dust-beetle.png']==late and ctx.characterImages==content.characterImages)
            content.mobImages['dust-beetle.png']=nil; assert(not panel:context().mobImages['dust-beetle.png'])
            assert(#requests==0 and copy.tacticalBattle.battle==b and not data.tacticalBattle.battle.units[3].frame)
        ''')

    def test_visible_potion_buttons_are_keyboard_and_controller_focus_targets(self):
        self.lua.execute('''
            local r={x=135,y=642,w=92,h=30,enabled=true}
            -- Match BattleUI.draw's actual named record rather than an
            -- artificial array; pointer and focus must send that owned name.
            view.ui.battlePotionButtons={{r,name='green-regeneration-vial'}}
            local targets=panel:targets(); assert(#targets==1 and targets[1].id=='potion1')
            panel:keypressed('tab'); panel:keypressed('return')
            assert(requests[1].name=='battle.item' and requests[1].args.name=='green-regeneration-vial')
            assert(requests[1].args.unitId=='player:companion' and panel.pending)
            panel.pending=nil; r.enabled=false; assert(#panel:targets()==0)
        ''')

    def test_real_battle_draw_quick_potion_click_sends_named_owned_item(self):
        self.lua.execute('''
            Items.write(own,nil,{kind='inventory',index=2},'green-regeneration-vial')
            local UI=require('game.battle_ui'); local Style=require('game.ui_layout')
            Style.scope=function(_,_,callback) return callback() end
            require('game.typography').drawText=function() end
            love.graphics={setColor=function() end,rectangle=function() end,setLineWidth=function() end}
            local ctx=panel:context(); ctx.animationClock=0; ctx.scenery={}
            for _,key in ipairs({'characterImages','npcImages','mobImages','characterWalkImages','npcWalkImages',
                'mobAttackImages','mobIdleImages','mobHitImages','mobDeathImages','mobWalkImages','mobRangedImages'}) do ctx[key]={} end
            ctx.colors={cream={},brass={},red={},green={}}
            ctx.worldView={begin=function() end,finish=function() end,toWorld=function(x,y) return x,y end}
            ctx.screenToGame=function(x,y) return x,y end
            ctx.drawLandscape=function() end; ctx.drawGround=function() end; ctx.drawAnimatedCharacter=function() end
            UI.draw(ctx)
            local entry=view.ui.battlePotionButtons[1]
            assert(entry and entry.name=='green-regeneration-vial' and entry[2]==nil)
            UI.handleMouse(ctx,entry[1].x+entry[1].w/2,entry[1].y+entry[1].h/2,false)
            assert(requests[1].name=='battle.item' and requests[1].args.name=='green-regeneration-vial')
            assert(own.inventory[2]=='green-regeneration-vial' and data.players.companion.inventory[2]~='green-regeneration-vial')
            assert(panel.pending and requests[1].args.unitId=='player:companion')
        ''')

    def test_old_encounter_epoch_and_network_pending_cannot_block_or_act_in_a_new_battle(self):
        self.lua.execute('''
            assert(panel:submit('battle.guard')); local oldId=panel.pending.id
            copy.tacticalBattle.encounterId='e999'; panel:update(); assert(not panel.pending and not panel.notice)
            network.lastCommandResult={requestId=oldId,ok=true,durable=true,revision=0}; panel:update()
            assert(not panel.lastOutcome)
            assert(panel:submit('battle.guard')); view.epoch=view.epoch+1; panel:update(); assert(not panel.pending)
            assert(panel:submit('battle.guard')); view.controller.network={submitCommand=network.submitCommand}; panel:update(); assert(not panel.pending)
            view.controller.network.pendingCommand={}; assert(not panel:canAct(b.units[2]) and not panel:submit('battle.endTurn'))
        ''')


if __name__ == '__main__':
    unittest.main()
