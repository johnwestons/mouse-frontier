"""Local visits preserve the other traveler; shared travel reunites both."""
import unittest
import test_coop_scenes_behavior as scenes


class PresenceTests(unittest.TestCase):
    def setUp(self):
        scenes.CoopSceneTests.setUp(self)
        self.lua.execute('''
            Presence=require('game.coop_presence')
            context.actorState=function(id)
                local own=Players.forActor(data,id)
                return {screen='game',scene=own.scene,x=own.playerX,y=own.playerY,travelTime=travelTime}
            end
            function visit(id,name,args)
                local request,reason=service:prepareRequest(id,name,args or {})
                assert(request,name..': '..tostring(reason))
                local reply=service:execute(id,id=='host' and 0 or 1,request)
                assert(reply.ok,name..': '..tostring(reply.reason)); return reply
            end
            function own(id) return Players.forActor(data,id) end
        ''')

    def test_guest_enters_home_while_host_stays_on_train_and_save_restores_visit(self):
        self.lua.execute('''
            local hx,hy=data.playerX,data.playerY; local epoch=data.coop.sceneEpoch
            visit('companion','scene.leaveTrain')
            assert(data.scene=='train' and own('companion').scene=='stop' and data.coop.sceneEpoch==epoch)
            own('companion').playerX,own('companion').playerY=Settlements.doorPoint(2,1)
            local reply=visit('companion','scene.enterHouse',{door=1})
            assert(reply.result.localTransition and reply.result.actorId=='companion')
            assert(data.playerX==hx and data.playerY==hy and data.scene=='train')
            assert(own('companion').scene=='house' and own('companion').activeHouseDoor==1)
            assert(not Presence.same(data,'host','companion') and Presence.revision(data,'companion')==2)
            local restored=assert(Schema.migrate(assert(Schema.copy(data))))
            assert(Players.forActor(restored,'companion').scene=='house' and restored.scene=='train')
            assert(require('game.net.game_state').project(data))
            visit('companion','scene.exitHouse'); assert(own('companion').scene=='stop' and data.scene=='train')
        ''')

    def test_host_local_visits_do_not_drag_guest_or_end_guests_activity(self):
        self.lua.execute('''
            local guest=own('companion'); local gx,gy=guest.playerX,guest.playerY; local epoch=data.coop.sceneEpoch
            assert(require('game.coop_leases').acquire(service.activityState,'other','companion',1,epoch,service.clock(),{kind='range'}))
            visit('host','scene.leaveTrain'); approachDoor(1); visit('host','scene.enterHouse',{door=1})
            assert(data.scene=='house' and own('companion').scene=='train')
            assert(guest.playerX==gx and guest.playerY==gy and data.coop.sceneEpoch==epoch)
            assert(service.activityState.resources.other and Presence.validate(data))
        ''')

    def test_guest_caravan_transactions_keep_camp_stock_and_host_presence(self):
        self.lua.execute('''
            local gate=caravanStop()
            data.players.companion.presence=Presence.capture(data)
            own('companion').playerX,own('companion').playerY=gate.x,gate.y
            visit('companion','scene.caravan',{action='enter',stop=9})
            assert(data.scene=='stop' and own('companion').scene=='caravan')
            local saved=assert(Schema.copy(data))
            assert(saved.crowCaravans.camps and saved.crowCaravans.camps['9'],'guest entry lost shared camp data')
            assert(saved.crowCaravans.activeCampId==nil)
            local camp=saved.crowCaravans.camps['9']
            assert(Players.forActor(saved,'companion').crowCaravans.activeCampId==camp.id)
            assert(#camp.merchants==3 and saved.crowCaravans.meetings==1)
            local remaining=#camp.merchants[1].listings
            visit('companion','scene.caravan',{action='return'})
            assert(own('companion').scene=='stop' and data.scene=='stop')
            visit('companion','scene.caravan',{action='enter',stop=9})
            saved=assert(Schema.copy(data))
            assert(saved.crowCaravans.meetings==1 and #saved.crowCaravans.camps['9'].merchants[1].listings==remaining)
            assert(require('game.net.game_state').project(saved))
        ''')

    def test_guest_caravan_exit_query_keeps_world_data_unchanged(self):
        self.lua.execute('''
            caravanStop(); run('scene.caravan',{action='enter',stop=9})
            data.players.companion.presence=Presence.capture(data)
            own('companion').playerX,own('companion').playerY=480,660
            run('scene.caravan',{action='return'})
            assert(data.scene=='stop' and own('companion').scene=='caravan')
            local root=data.crowCaravans
            local camp=root.camps['9']; local actors=camp.actorStates
            local view={runtime={saveData=own('companion'),scene='caravan',player={x=480,y=660}}}
            local visits=require('game.coop_guest_visits').new(view,{})
            for i=1,30 do
                local target=assert(visits:nearest())
                assert(target.command=='scene.caravan' and target.args.action=='return')
                assert(data.crowCaravans==root,'entrance query replaced the shared caravan root')
                assert(root.camps['9']==camp and camp.actorStates==actors)
                assert(root.activeCampId==nil and own('companion').crowCaravans.activeCampId==camp.id)
            end
            view.runtime.player={x=480,y=500}; assert(visits:nearest()==nil)
        ''')

    def test_departure_reunites_guest_from_home_and_keeps_story_host_only(self):
        self.lua.execute('''
            visit('companion','scene.leaveTrain')
            own('companion').playerX,own('companion').playerY=Settlements.doorPoint(2,1)
            visit('companion','scene.enterHouse',{door=1})
            local request,reason=service:prepareRequest('companion','travel.depart',{})
            assert(not request and reason=='host_only')
            local epoch=data.coop.sceneEpoch
            visit('host','travel.depart')
            assert(data.coop.sceneEpoch==epoch+1 and own('companion').scene=='train')
            assert(data.players.companion.presence==nil and own('companion').playerY>=400 and own('companion').playerY<=450)
        ''')

    def test_wire_local_scene_result_is_small_and_checked(self):
        self.lua.execute('''
            local reply=visit('companion','scene.leaveTrain')
            local R=require('game.net.item_results'); local public=assert(R.project('scene.leaveTrain',reply.result))
            assert(R.valid('scene.leaveTrain',public) and public.actorId=='companion' and public.actors==nil)
            public.sceneRevision=-1; assert(not R.valid('scene.leaveTrain',public))
            local broken=assert(Schema.copy(data)); broken.players.companion.presence.scene='unknown'
            assert(not Schema.validate(broken))
        ''')


if __name__ == '__main__':
    unittest.main()
