"""Production session/authority/UI over delayed transport at a 10 FPS host.

This simulates Wi-Fi delay; it is not physical Android performance acceptance.
"""
import unittest
import test_coop_local_play_behavior as application


class CombatLatencyTests(unittest.TestCase):
    def setUp(self):
        self.harness = application.LocalPlayTests()
        self.harness.setUp()
        self.lua = self.harness.lua
        self.lua.execute('''
            Catalog=require('game.catalog'); Players=require('game.coop_players')
            Battle=require('game.battle_controller'); Commands=require('game.coop_battles')
            hostContext.commands.remote=function(generation,request) return service:execute('companion',generation,request) end
            Commands.install(service,{catalog=Catalog,actorState=function() return {screen=hostRuntime.state,scene='train'} end})
            ready(); host.menuOpen=false; guest.menuOpen=false
            data.encounters['2']={rolled=true,hasMob=true,resolved=false,tier='easy',mobFiles={Catalog.mobTiers.easy[1]}}
            assert(require('game.coop_entities').ensure(data))
            assert(service:submitLocal('battle.begin',{encounterId=data.encounters['2'].entityId}).ok)
            hostRuntime.state='battle'; local b=data.tacticalBattle.battle; b.intro=nil; b.active=2
            step(30)
            local runtime={saveData=Players.forActor(assert(Schema.copy(guest.replica.data)),'companion')}
            runtime.battle=runtime.saveData.tacticalBattle.battle
            view={runtime=runtime,ui={},ready=true,focused=true,epoch=data.coop.sceneEpoch,controller=guest,camera={}}
            panel=require('game.coop_guest_battles').new(view,{catalog=Catalog})
            local seen=guest.replica.revision
            -- Delay every reliable packet 100 ms each way, including replies
            -- and state chunks.
            for _,entry in ipairs({{guest.network.transport,'client_to_host'},{host.network.transport,'host_to_client'}}) do
                local transport,direction=entry[1],entry[2]; local send=transport.send
                transport.send=function(self,peer,bytes,channel,reliable)
                    lab:delayNext(direction,1,2)
                    return send(self,peer,bytes,channel,reliable)
                end
            end
            function slowStep(count)
                for tick=1,count do
                    clock=clock+.05; lab:advanceSteps(1)
                    if tick%2==0 then
                        host:beginFrame(.1)
                        Battle.animate({battle=data.tacticalBattle.battle},.1)
                        host:finishFrame()
                    end
                    guest:update(.05)
                    if seen~=guest.replica.revision then
                        runtime.saveData=Players.forActor(assert(Schema.copy(guest.replica.data)),'companion')
                        runtime.battle=runtime.saveData.tacticalBattle.battle; seen=guest.replica.revision
                    end
                    panel:update(.05)
                    assert(not host.network.closed and not guest.network.closed)
                end
            end
        ''')

    def tearDown(self):
        self.harness.tearDown()

    def test_single_guard_press_during_host_animation_completes_without_double_turn(self):
        self.lua.execute('''
            data.tacticalBattle.battle.attackTimer=.6
            local revision=data.tacticalBattle.revision; local before=writes
            assert(panel:submit('battle.guard')) -- The only input in this test.
            slowStep(60)
            assert(not panel.pending and panel.lastOutcome and panel.lastOutcome.ok)
            assert(data.tacticalBattle.revision==revision+1 and writes==before+1)
            assert(data.tacticalBattle.battle.units[2].guarding)
            assert(view.runtime.saveData.tacticalBattle.revision==data.tacticalBattle.revision)
            slowStep(20); assert(data.tacticalBattle.revision==revision+1)
        ''')

    def test_single_end_turn_press_and_retransmission_cannot_skip_another_turn(self):
        self.lua.execute('''
            local transport=host.network.transport; local send=transport.send; local delayed=false
            transport.send=function(self,peer,bytes,channel,reliable)
                local message=require('game.net.protocol').decode(bytes,channel)
                if not delayed and message and message.type=='command_result' then
                    lab:delayNext('host_to_client',1,20); delayed=true
                end
                return send(self,peer,bytes,channel,reliable)
            end
            local revision=data.tacticalBattle.revision; local before=writes
            assert(panel:submit('battle.endTurn'))
            slowStep(70)
            assert(delayed and not panel.pending and panel.lastOutcome.ok)
            assert(data.tacticalBattle.revision==revision+1 and writes==before+1)
            assert(data.tacticalBattle.battle.active==3)
        ''')

    def test_single_move_press_after_previous_animation_uses_the_original_cell(self):
        self.lua.execute('''
            local b=data.tacticalBattle.battle; local u=b.units[b.active]
            local reachable=require('game.battle_rules').reachable(b,u,u.move); local target
            for _,cell in pairs(reachable) do if cell.q~=u.q or cell.r~=u.r then target=cell; break end end
            assert(target)
            b.attackTimer=.6; local revision=data.tacticalBattle.revision
            assert(panel:submit('battle.move',{q=target.q,r=target.r}))
            slowStep(60)
            assert(not panel.pending and panel.lastOutcome.ok)
            assert(data.tacticalBattle.revision==revision+1 and b.units[2].q==target.q and b.units[2].r==target.r)
            assert(not view.runtime.battle.units[2].moveAnim)
        ''')


if __name__ == '__main__':
    unittest.main()
