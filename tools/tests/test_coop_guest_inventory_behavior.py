"""Guest item controls produce bounded intents and wait for host state/results."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestInventoryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Players=require('game.coop_players'); Items=require('game.item_instances'); Catalog=require('game.catalog')
            Inventory=require('game.inventory'); Contract=require('game.coop_item_contract')
            data=F.campaign(); assert(F.enroll(data)); data.scene='train'
            own=Players.forActor(data,'companion'); own.health=10
            own.inventory[1]='field-bandage-roll'; own.inventory[2]='food-ration'; own.inventory[3]='patched-canvas-pack'
            assert(Items.ensure(data)); data.coop.revisions['player:companion']=3; data.coop.revisions.resources=7
            runtime={saveData=Players.forActor(Schema.copy(data),'companion'),player={x=300,y=400},scene='train',state='game'}
            neutral=0; requests={}; allowed=true; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},ready=true,epoch=data.coop.sceneEpoch,mobile={enabled=false},
                controller={menuOpen=false,network=network},scene={itemIsHere=function(item) return item.scene=='train' and item.carIndex==1 end},
                neutralize=function() neutral=neutral+1 end,actionsAllowed=function() return allowed end}
            panel=require('game.coop_guest_inventory').new(view,{catalog=Catalog,colors={}})
            love={keyboard={isDown=function() return false end},timer={getTime=function() return 10 end}}
            function select(ref) runtime.draggedSlot=ref; panel:remember() end
            function result(id,details,revision)
                network.lastCommandResult={command=requests[id].name,requestId=id,ok=true,durable=true,revision=revision or data.coop.revision,details=details}
            end
        ''')

    def test_equipment_move_preserves_display_until_matching_projection_arrives(self):
        self.lua.execute('''
            panel:toggle(); select({kind='equipment',index=1})
            local id=runtime.saveData.itemSlots.equipment[1].id
            assert(panel:move(runtime.draggedSlot,{kind='inventory',index=4}))
            local r=requests[1]; assert(r.name=='inventory.swap' and r.args.sourceItem.id==id and r.args.targetItem==false)
            assert(r.expected['player:companion']==3 and not r.expected.resources and r.epoch==view.epoch)
            assert(panel.pending and not runtime.draggedSlot and neutral==2)
            assert(runtime.saveData.itemSlots.equipment[1].id==id and not own.inventory[4])
            result(1,{moved=true},data.coop.revision+1); panel:update(); assert(panel.pending and panel.notice=='Updating items...')
            local next=Schema.copy(data); local actor=Players.forActor(next,'companion')
            assert(Inventory.move(actor,nil,r.args.source,r.args.target,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
            next.coop.revision=next.coop.revision+1; runtime.saveData=actor; panel:update()
            assert(not panel.pending and runtime.saveData.itemSlots.inventory[4].id==id and not runtime.saveData.equipment[1])
            assert(own.itemSlots.equipment[1].id==id) -- Detached client controls never wrote the authority fixture.
        ''')

    def test_battle_backpack_uses_owned_battle_commands_while_world_motion_is_paused(self):
        self.lua.execute('''
            runtime.state='battle'; runtime.battle={active=1,units={{id='player:companion',actorId='companion',hp=10}}}
            allowed=false; canAct=true; battleRequests={}
            view.battles={canAct=function() return canAct end,submit=function(_,name,args)
                battleRequests[#battleRequests+1]={name=name,args=args}; return canAct end}
            assert(panel:toggle() and panel:canEdit()); select({kind='equipment',index=1})
            assert(panel:move(runtime.draggedSlot,{kind='inventory',index=4}))
            assert(battleRequests[1].name=='battle.swap' and battleRequests[1].args.sourceItem.id==runtime.saveData.itemSlots.equipment[1].id)
            select({kind='inventory',index=1}); assert(panel:consume())
            assert(battleRequests[2].name=='battle.item' and battleRequests[2].args.name=='field-bandage-roll' and #requests==0)
            canAct=false; assert(not panel:canEdit() and not panel:consume())
            assert(own.inventory[1]=='field-bandage-roll' and runtime.saveData.inventory[1]=='field-bandage-roll')
        ''')

    def test_battle_backpack_draw_uses_the_private_runtime_and_no_drop_instruction(self):
        self.lua.execute('''
            runtime.battle={}; runtime.inventoryOpen=true; local lines={}
            love.graphics={setColor=function() end,rectangle=function() end}
            require('game.typography').drawText=function(_,text) lines[#lines+1]=text end
            panel.presenter.drawInventory=function() end; panel.frame=function() end
            panel.button=function(_,label,x,y,w,h) return {x=x,y=y,w=w,h=h} end
            panel:draw(); assert(lines[3]:find('Use medicine',1,true) and not lines[3]:find('drop',1,true))
            assert(runtime.saveData~=data and data.players.companion.inventory[1]=='field-bandage-roll')
        ''')

    def test_consumable_scopes_and_feedback_are_derived_from_actual_host_result(self):
        self.lua.execute('''
            select({kind='inventory',index=1}); assert(panel:consume())
            assert(requests[1].name=='inventory.consume' and requests[1].args.sourceItem.id==false)
            assert(not requests[1].expected.resources and runtime.saveData.health==10)
            result(1,{item='field-bandage-roll',gained={health=2}}); panel:update()
            assert(panel.notice:find('Health +2',1,true) and not panel.pending)
            select({kind='inventory',index=2}); assert(panel:consume())
            assert(requests[2].expected.resources==7 and requests[2].expected.train==0)
            assert(runtime.saveData.resources.food==10 and own.inventory[2]=='food-ration')
        ''')

    def test_wearable_equip_and_remove_use_the_same_identity_guarded_transfer(self):
        self.lua.execute('''
            select({kind='inventory',index=3}); assert(panel:consume())
            local r=requests[1]; local slot=Catalog.wearableItems['patched-canvas-pack'].slot
            assert(r.name=='inventory.swap' and r.args.target.kind=='wearable' and r.args.target.slot==slot)
            assert(Inventory.move(runtime.saveData,nil,r.args.source,r.args.target,Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
            result(1,{moved=true}); panel:update(); select({kind='wearable',slot=slot}); assert(panel:consume())
            assert(requests[2].args.target.kind=='inventory' and requests[2].args.target.index==3)
            assert(requests[2].args.sourceItem.id==r.args.sourceItem.id)
        ''')

    def test_changed_selection_is_cleared_and_an_old_identity_is_never_replaced_silently(self):
        self.lua.execute('''
            select({kind='equipment',index=1}); local selected=panel.selection.id
            local ref={kind='equipment',index=1}; Items.assign(runtime.saveData,nil,ref,runtime.saveData.equipment[1])
            assert(runtime.saveData.itemSlots.equipment[1].id~=selected)
            -- A click before the next update still sends the identity the user selected.
            assert(panel:drop(ref)); assert(requests[1].args.sourceItem.id==selected)
            network.lastCommandResult={requestId=1,ok=false,reason='stale_item'}; panel:update()
            select(ref); runtime.saveData.equipment[1]=nil; panel:update()
            assert(not runtime.draggedSlot and not panel.selection and #requests==1)
        ''')

    def test_pending_save_and_scene_changes_never_resubmit_or_predict_items(self):
        self.lua.execute('''
            panel:toggle(); panel:update(); select({kind='inventory',index=1}); assert(panel:consume())
            network.lastCommandResult={requestId=1,ok=true,savePending=true,revision=data.coop.revision,details={item='field-bandage-roll',gained={health=5}}}
            panel:update(); assert(panel.pending and runtime.saveData.inventory[1]=='field-bandage-roll')
            assert(not panel:drop({kind='equipment',index=1}) and #requests==1)
            view.epoch=view.epoch+1; panel:update(); assert(not runtime.inventoryOpen and panel.pending)
            network.lastCommandResult={requestId=2,ok=false,reason='stale_scene'}; panel:update(); assert(panel.pending)
            result(1,{item='field-bandage-roll',gained={health=5}}); panel:update()
            assert(not panel.pending and #requests==1 and runtime.saveData.health==10)
        ''')

    def test_pickup_filters_scene_car_distance_and_occupied_storage(self):
        self.lua.execute('''
            runtime.saveData.droppedItems={
                {entityId='other',name='food-ration',scene='train',carIndex=2,x=300,y=400},
                {entityId='full',name='chest',scene='train',carIndex=1,x=302,y=400,storage={'food-ration'}},
                {entityId='fixed',name='food-ration',scene='train',carIndex=1,x=301,y=400,permanent=true},
                {entityId='near',name='food-ration',scene='train',carIndex=1,x=310,y=400},
                {entityId='far',name='food-ration',scene='train',carIndex=1,x=400,y=400}}
            assert(panel:nearest().entityId=='near'); assert(panel:pickup())
            assert(requests[1].args.entityId=='near' and requests[1].expected['entity:near']==0 and not panel:nearest())
            assert(#runtime.saveData.droppedItems==5); panel.pending=nil; allowed=false
            assert(not panel:pickup() and #requests==1)
        ''')

    def test_keyboard_selection_and_blocked_actions_do_not_modify_slots(self):
        self.lua.execute('''
            panel:toggle(); panel:keypressed('return')
            assert(runtime.draggedSlot and runtime.draggedSlot.index==1 and #requests==0)
            local targets=panel:targets(); local target
            for _,t in ipairs(targets) do if t.id=='inventory:4' then target=t end end
            assert(target); allowed=false; target.action(); assert(#requests==0 and runtime.saveData.inventory[1])
            allowed=true; target.action(); assert(requests[1].name=='inventory.swap')
            panel:keypressed('escape'); assert(not runtime.inventoryOpen and not runtime.draggedSlot)
        ''')

    def add_storage(self, mailbox=False):
        self.lua.globals().mailbox = mailbox
        self.lua.execute('''
            Entities=require('game.coop_entities')
            local campaign=Players.campaignOf(runtime.saveData)
            chest={name=mailbox and 'mailbox-reward' or 'travel-chest',mailbox=mailbox,permanent=mailbox,
                scene='train',carIndex=1,x=315,y=400,storage={[1]='trail-slingshot',[2]='food-ration',[4]='rocks'}}
            campaign.droppedItems={chest}; assert(Entities.ensure(campaign)); assert(Items.ensure(campaign))
            campaign.coop.revisions['entity:'..chest.entityId]=9; chestId=chest.entityId
        ''')

    def test_storage_open_and_rebinding_are_read_only_and_cancel_replaced_selection(self):
        self.add_storage()
        self.lua.execute('''
            assert(panel:nearest()==chest and panel:actionLabel()=='OPEN STORAGE' and panel:pickup())
            assert(runtime.chestOpen and runtime.activeChest==chest and #requests==0 and neutral==1)
            select({kind='chest',index=1}); local id=panel.selection.id
            local next=Schema.copy(Players.campaignOf(runtime.saveData)); runtime.saveData=Players.forActor(next,'companion')
            panel:update(); assert(runtime.activeChest~=chest and runtime.activeChest.entityId==chestId and panel.selection.id==id)
            Items.assign(runtime.saveData,runtime.activeChest,{kind='chest',index=1},'trail-slingshot'); panel:update()
            assert(not runtime.draggedSlot and not panel.selection and chest.storageInstances[1].id==id and #requests==0)
        ''')

    def test_storage_actions_bind_container_identity_and_the_correct_revision_scopes(self):
        self.add_storage()
        self.lua.execute('''
            assert(panel:openContainer(chestId)); select({kind='inventory',index=2})
            assert(panel:move(runtime.draggedSlot,{kind='chest',index=3}))
            local r=requests[1]; assert(r.args.containerId==chestId and r.args.targetItem==false)
            assert(r.expected['entity:'..chestId]==9 and r.expected['player:companion']==3 and not r.expected.resources)
            result(1,{moved=true}); panel:update(); select({kind='chest',index=2}); assert(panel:consume())
            r=requests[2]; assert(r.args.containerId==chestId and r.expected.resources==7 and r.expected.train==0)
            assert(chest.storage[2]=='food-ration' and runtime.saveData.inventory[2]=='food-ration')
            result(2,{item='food-ration',gained={food=3}}); panel:update()
            select({kind='chest',index=4}); panel:keypressed('t'); r=requests[3]
            assert(r.name=='mailbox.collect' and r.args.sourceItem.name=='rocks' and r.args.containerId==chestId)
            result(3,{item='rocks',amount=8}); panel:update(); assert(panel.notice=='Collected 8 Rocks.')
        ''')

    def test_removed_or_unreachable_storage_closes_without_losing_a_pending_receipt(self):
        self.add_storage()
        self.lua.execute('''
            panel:update(); assert(panel:openContainer(chestId)); select({kind='chest',index=1})
            assert(panel:quickTransfer(runtime.draggedSlot)); chest.x=900; panel:update()
            assert(not runtime.chestOpen and not runtime.activeChest and not panel.containerId and panel.pending and runtime.inventoryOpen)
            result(1,{moved=true}); panel:update(); assert(not panel.pending and #requests==1)
            chest.x=315; assert(panel:openContainer(chestId)); select({kind='chest',index=1})
            runtime.saveData.droppedItems={}; panel:update(); assert(not runtime.chestOpen and not runtime.draggedSlot)
        ''')

    def test_mailbox_and_empty_container_controls_send_no_implicit_scene_progression(self):
        self.add_storage(mailbox=True)
        self.lua.execute('''
            assert(panel:actionLabel()=='OPEN MAILBOX' and panel:pickup()); assert(not panel:takeContainer())
            select({kind='chest',index=1}); assert(panel:transferSelected())
            assert(requests[1].name=='storage.transfer' and not requests[1].args.target)
            result(1,{moved=true}); panel:update()
            chest.mailbox=false; chest.permanent=false; chest.storage={}; chest.storageInstances={}
            assert(panel:takeContainer()); assert(requests[2].name=='loot.pickup' and requests[2].args.entityId==chestId)
            assert(runtime.scene=='train' and view.epoch==data.coop.sceneEpoch)
        ''')

    def test_expedition_container_affordances_never_normalize_world_state_or_open_gates(self):
        self.lua.execute('''
            local Areas=require('game.expedition_areas'); local campaign=Players.campaignOf(runtime.saveData)
            Areas.ensure(campaign); campaign.activeExpeditionArea=Areas.BADLANDS_SURFACE_ID; campaign.scene='expedition'
            runtime.scene='expedition'
            for _,interaction in ipairs(Areas.current(campaign).interactions) do
                if interaction.id=='surface-cache' then runtime.player.x,runtime.player.y=interaction.x,interaction.y end
            end
            local area=campaign.expeditions[campaign.activeExpeditionArea]; local chest=area.chests['surface-cache']
            Areas.ensure=function() error('guest attempted normalization') end
            Areas.state=function() error('guest attempted lazy state access') end
            Areas.updateGates=function() error('guest attempted gate update') end
            assert(panel:nearest()==chest and not panel:pickup() and #requests==0)
            assert(not runtime.activeChest and not chest.opened)
            -- Only a host-saved opened flag permits the private panel to open.
            chest.opened=true; assert(panel:pickup() and runtime.activeChest==chest and #requests==0)
            campaign.activeExpeditionArea=Areas.DUNGEON_ID; runtime.player.x=1480; runtime.player.y=150
            area=campaign.expeditions[campaign.activeExpeditionArea]; chest=area.chests['boss-vault']
            area.gates.bossDefeated=false; panel:toggle(); assert(not panel:openContainer(chest.entityId))
            assert(area.gates.bossDefeated==false and #requests==0)
        ''')


if __name__ == '__main__':
    unittest.main()
