"""Opening-yard progression, acknowledged story, checkpoints and departure."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class HomeStopTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Home=require('game.home_stop'); Catalog=require('game.catalog')
            Authority=require('game.coop_authority'); Scenes=require('game.coop_scenes')
            Players=require('game.coop_players'); State=require('game.net.game_state')
            data=F.campaign(1,{scene='stop',homeStop=Home.newState(),resources={food=0,water=0,coal=0,oil=0},
                maintenance={condition=72,lastServicedStop=0,totalServices=0,totalWear=0}})
            assert(F.enroll(data)); failSave=false; writes=0; travelTime=0
            states={host={screen='game',scene='stop',x=465,y=455},companion={screen='game',scene='stop',x=465,y=455}}
            function create()
                service=Authority.new{campaign=data,sessionId='home-test',randomSeed=123,
                    checkpoint=function(value)
                        writes=writes+1
                        if failSave then return false end
                        saved=assert(Schema.copy(value)); return true
                    end}
                service:admit('companion',1)
                Scenes.install(service,{catalog=Catalog,actorState=function(id) return states[id] end,
                    trainSpawn=function() return 430,430 end,
                    trainClamp=function(d,id,x,y) return math.max(150,math.min(800,x)),math.max(400,math.min(450,y)) end})
            end
            create()
            function advance(action)
                if action=='talk' and not Home.isOffice(data) then
                    states.host.x,states.host.y=Home.points.officeDoor.x,Home.points.officeDoor.y
                    local entered=service:submitLocal('home.advance',{action='enterOffice'})
                    if not entered.ok then return entered end
                elseif (action=='supplies' or action=='repair') and Home.isOffice(data) then
                    states.host.x,states.host.y=Home.points.officeExit.x,Home.points.officeExit.y
                    assert(service:submitLocal('home.advance',{action='exitOffice'}).ok)
                end
                local point=Home.points[action=='talk' and 'conductor' or action=='enterOffice' and 'officeDoor' or action=='exitOffice' and 'officeExit' or action]
                states.host.x,states.host.y=point.x,point.y
                return service:submitLocal('home.advance',{action=action})
            end
            function briefing()
                for line=1,5 do
                    local reply=advance('talk'); assert(reply.ok,reply.reason)
                    assert(reply.result.line==line and data.homeStop.dialogueLine==line)
                    assert(data.homeStop.stage=='briefing')
                end
                assert(advance('talk').ok and data.homeStop.stage=='supplies' and data.homeStop.dialogueLine==nil)
                assert(advance('exitOffice').ok)
            end
            function ready()
                briefing(); assert(advance('supplies').ok); assert(advance('repair').ok)
                assert(advance('talk').result.line==6 and data.homeStop.stage=='farewell')
                assert(advance('talk').ok and data.homeStop.stage=='ready')
                assert(advance('exitOffice').ok)
            end
        ''')

    def test_every_displayed_line_survives_reload_until_acknowledged(self):
        self.lua.execute(r'''
            assert(advance('talk').result.line==1)
            data=assert(Schema.migrate(saved)); create()
            assert(data.homeStop.dialogueLine==1 and Home.action(data)=='talk')
            assert(advance('talk').result.line==2)
            for line=3,5 do assert(advance('talk').result.line==line) end
            data=assert(Schema.migrate(saved)); create()
            assert(data.homeStop.stage=='briefing' and data.homeStop.dialogueLine==5)
            assert(advance('talk').ok and data.homeStop.stage=='supplies')
            assert(advance('supplies').ok and advance('repair').ok)
            assert(advance('talk').result.line==6)
            data=assert(Schema.migrate(saved)); create()
            assert(data.homeStop.dialogueLine==6 and data.homeStop.stage=='farewell')
            assert(advance('talk').ok and data.homeStop.stage=='ready' and not data.homeStop.dialogueLine)
        ''')

    def test_steps_require_order_reach_host_and_ordinary_gameplay(self):
        self.lua.execute(r'''
            assert(advance('supplies').reason=='home_step_unavailable')
            states.host.x,states.host.y=100,100
            assert(service:submitLocal('home.advance',{action='talk'}).reason=='home_target_unavailable')
            states.host.x=0/0
            assert(service:submitLocal('home.advance',{action='talk'}).reason=='home_target_unavailable')
            local req={sessionId=service.sessionId,requestId=1,sceneEpoch=data.coop.sceneEpoch,
                command='home.advance',args={action='talk'},expected={}}
            assert(service:execute('companion',1,req).reason=='host_only')
            states.host.x,states.host.y=465,455; states.host.activityBlocked=true
            assert(advance('talk').reason=='home_step_unavailable')
            states.host.activityBlocked=false; states.host.screen='battle'
            assert(advance('talk').reason=='scene_unavailable')
            assert(data.homeStop.dialogueLine==nil and data.resources.food==0)
        ''')

    def test_checkpoint_retry_cannot_duplicate_supplies_or_repair(self):
        self.lua.execute(r'''
            briefing(); states.host.x,states.host.y=310,500
            local request=assert(service:prepareRequest('host','home.advance',{action='supplies'}))
            failSave=true
            local reply=service:execute('host',0,request)
            assert(reply.ok and reply.savePending and data.resources.food==10)
            assert(service:execute('host',0,request).savePending and data.resources.food==10)
            failSave=false; assert(service:retryCheckpoint())
            data=assert(Schema.migrate(saved)); create()
            assert(advance('supplies').reason=='home_step_unavailable' and data.resources.food==10)
            assert(advance('repair').ok and data.maintenance.condition==100)
            data.maintenance.condition=91
            assert(advance('repair').reason=='home_step_unavailable' and data.maintenance.condition==91)
            assert(data.resources.oil==10 and data.homeStop.repairComplete)
        ''')

    def test_board_and_depart_require_completed_preparation(self):
        self.lua.execute(r'''
            assert(service:submitLocal('scene.returnTrain',{}).reason=='home_preparation_incomplete')
            assert(service:submitLocal('scene.enterHouse',{door=1}).reason=='home_preparation_incomplete')
            data.scene='train'; states.host.scene='train'
            assert(service:submitLocal('travel.depart',{}).reason=='home_preparation_incomplete')
            data.scene='stop'; states.host.scene='stop'; ready()
            assert(service:submitLocal('scene.returnTrain',{}).reason=='home_target_unavailable')
            states.host.x,states.host.y=Home.points.train.x,Home.points.train.y
            assert(service:submitLocal('scene.returnTrain',{}).ok and data.scene=='train')
            states.host.scene='train'
            local req=assert(service:prepareRequest('host','travel.depart',{}))
            assert(service:execute('host',0,req).ok and data.homeStop.stage=='departed')
            local coal=data.resources.coal
            assert(service:execute('host',0,req).ok and data.resources.coal==coal)
            data=assert(Schema.migrate(saved))
            assert(data.coop.journey.from==1 and data.coop.journey.to==2 and not Home.isHome(data))
            assert(data.homeStop.stage=='departed' and not Home.objective(data))
        ''')

    def test_home_train_exit_is_safe_without_random_encounters(self):
        self.lua.execute(r'''
            ready(); states.host.x,states.host.y=Home.points.train.x,Home.points.train.y
            assert(service:submitLocal('scene.returnTrain',{}).ok)
            states.host.scene='train'
            assert(not data.events['1'] and not data.encounters['1'])
            assert(service:submitLocal('scene.leaveTrain',{}).ok and data.scene=='stop')
            assert(data.playerX==Home.points.train.x and data.playerY==Home.points.train.y and data.currentNPC==Home.CONDUCTOR)
            assert(not data.events['1'] and not data.encounters['1'])
        ''')

    def test_old_campaigns_never_gain_an_active_home_stop(self):
        self.lua.execute(r'''
            local old=F.campaign(1,{scene='train'})
            assert(not Home.isHome(old) and not Home.objective(old) and Home.canDepart(old))
            local reloaded=assert(Schema.migrate(old))
            assert(not Home.isHome(reloaded) and next(reloaded.homeStop)==nil)
            local invalid=assert(Schema.copy(data)); invalid.homeStop.stage='repair'
            assert(not Schema.validate(invalid))
            invalid=assert(Schema.copy(data)); invalid.homeStop.dialogueLine=6
            assert(not Schema.validate(invalid))
            invalid=assert(Schema.copy(data)); invalid.location=2
            assert(not Schema.validate(invalid))
        ''')

    def test_story_state_projects_to_guest_and_fixed_home_has_no_random_quests(self):
        self.lua.execute(r'''
            assert(advance('talk').ok)
            local layout=require('game.stops').ensure(data,Catalog,'stop',function() error('home used random generation') end)
            assert(layout.npcOutside==Home.CONDUCTOR and layout.offer=='none' and not layout.npcWeapon)
            assert(not layout.conversation and #layout.decorations==0)
            assert(require('game.coop_entities').ensure(data))
            local producer=State.producer(); local replica=State.replica()
            local message,reason=producer:capture(data); assert(message,reason)
            assert(replica:apply(message))
            assert(Home.isHome(replica.data) and replica.data.homeStop.dialogueLine==1)
            local x,y=Home.clamp(10,800); assert(x==150 and y==650)
            x,y=Home.move(200,450,1000,300); assert(x<=780 and y>=280,tostring(x)..','..tostring(y))
        ''')

    def test_new_campaign_bootstrap_starts_in_yard_and_resumes_acknowledged_story(self):
        self.lua.execute(r'''
            local noop=function() end
            local image={getHeight=function() return 100 end}
            local session=require('game.game_session').new()
            local runtime=require('game.runtime_state').new{session=session,transition=function(value) session:setScreen(value) end}
            local context={saveSchema=Schema,characters={'scout-frog.png'},characterImages={['scout-frog.png']=image},
                npcImages={[Home.CONDUCTOR]=image},car={x=0,y=0,w=960,h=720},ui={},maintenanceSession={},runtime=runtime,
                filesystem={getDirectoryItems=function() return {Home.CONDUCTOR} end},
                roster=require('game.roster'),house={storeLoot=noop},catalog=Catalog,
                maintenance={close=noop,ensure=noop},engineUpgrades={tiers={{}}},passengers={},
                events={storyStops={},ensure=noop},settlements={clamp=function() error('home spawn used settlement 1 mask') end},
                playerProgression=require('game.player_progression'),stopHelpProgression={ensure=noop},
                crowCaravans={version=1,ensureSchedule=function(value)
                    value.crowCaravans.scheduleVersion=1; return value.crowCaravans,nil,false
                end},crowCaravanArea={hasStopGate=function() return true end},shootingRange={hostStops={}},
                trainObjectBounds=function() return 0,960,0,720 end,trainFloorBounds=function() return 0,960,0,720 end,
                clampToTrainFloor=function(x,y) return x,y end,isFurnitureItem=function() return false end,
                resetStopSludges=noop,expeditionAreas=require('game.expedition_areas'),resetExpedition=noop,
                prepareExpeditionBattleAssets=noop,writeSave=noop}
            local bootstrap=require('game.session_bootstrap').new(context)
            local fresh=bootstrap.newSave('scout-frog.png')
            assert(Schema.validate(fresh) and fresh.scene=='stop' and fresh.location==1 and Home.isHome(fresh))
            assert(fresh.playerX==420 and fresh.playerY==565 and fresh.resources.food==0 and fresh.resources.oil==0)
            assert(fresh.currentNPC==Home.CONDUCTOR and fresh.stopLayouts['1'].homeStop and fresh.maintenance.condition==72)
            assert(bootstrap.enterGame(fresh) and runtime.scene=='stop' and runtime.state=='game')
            assert(runtime.player.x==420 and runtime.player.y==565)
            local active=runtime.saveData
            assert(Home.advance(active,'enterOffice'))
            assert(Home.advance(active,'talk').line==1)
            local suspended=assert(Schema.copy(active)); suspended.playerX=999; suspended.playerY=999
            assert(bootstrap.enterGame(suspended))
            assert(Home.officeWalkable(runtime.player.x,runtime.player.y) and runtime.saveData.homeStop.dialogueLine==1)
            assert(runtime.saveData.currentNPC==Home.CONDUCTOR and runtime.saveData.resources.food==0)
            local rear=assert(Schema.copy(runtime.saveData))
            rear.playerX,rear.playerY=Home.officeStandingPoint(430,295)
            assert(bootstrap.enterGame(rear))
            assert(runtime.player.x==rear.playerX and runtime.player.y==rear.playerY,'reload moved player out of rear office floor')
        ''')


if __name__ == '__main__':
    unittest.main()
