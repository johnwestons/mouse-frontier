"""Two authoritative roaming targets and a committed attack that cannot switch."""
import unittest
import test_expedition_combat_behavior as expedition


class RoamingTargetTests(unittest.TestCase):
    setUp = expedition.ExpeditionCombatBehaviorTests.setUp

    def targets(self):
        self.lua.execute('''
            sys,ctx=fixture({{id='a',x=60,y=0,packId='pack'},{id='b',x=180,y=0,packId='pack'}})
            ctx.actors={{id='host',x=400,y=0},{id='companion',x=0,y=0}}
            contacts=0; ctx.onContact=function(mob,target) contacts=contacts+1; contacted=target.id; return true end
            function tick(dt) return R.update(sys,ctx,dt or .1) end
            function transient() return sys.transient.test.a end
        ''')

    def test_closer_companion_alerts_pack_and_contact_never_begins_host_scene(self):
        self.targets()
        self.lua.execute('''
            tick(); assert(transient().state=='alert' and transient().targetId=='companion')
            assert(sys.transient.test.b.state=='alert' and sys.transient.test.b.targetId=='companion')
            tick(.4); tick(.1); assert(transient().state=='windup')
            assert(tick(.5)=='pressure' and contacts==1 and contacted=='companion' and #ctx.encounters==0)
        ''')

    def test_locked_companion_dodge_cannot_redirect_the_strike_onto_host(self):
        self.targets()
        self.lua.execute('''
            tick(); tick(.4); tick(.1); assert(transient().targetId=='companion')
            ctx.actors[2].x=400; ctx.actors[1].x=60
            tick(.5); assert(contacts==0 and #ctx.encounters==0 and transient().state=='recover')
        ''')

    def test_disconnected_target_recovers_then_retargets_living_host(self):
        self.targets()
        self.lua.execute('''
            tick(); tick(.4); tick(.1); ctx.actors={{id='host',x=60,y=0}}
            tick(.5); assert(transient().state=='recover' and contacts==0 and #ctx.encounters==0)
            tick(.6); tick(.1); assert(transient().state=='windup' and transient().targetId=='host')
            assert(tick(.5)=='battle' and #ctx.encounters==1)
        ''')

    def test_unreachable_invalid_absent_or_distant_targets_cannot_alert(self):
        self.targets()
        self.lua.execute('''
            ctx.canReach=function() return false end; tick(); assert(transient().state=='patrol')
            ctx.canReach=function() return true end; ctx.actors={{id='intruder',x=60,y=0},{id='companion',x=0/0,y=0}}
            tick(); assert(transient().state=='patrol')
            ctx.actors={}; tick(); assert(transient().state=='patrol')
            ctx.actors={{id='companion',x=60,y=0,ready=false}}; tick(); assert(transient().state=='patrol')
            ctx.actors={{id='companion',x=1000,y=0}}; tick(); assert(transient().state=='patrol')
        ''')

    def test_tie_chooses_host_and_failed_pressure_does_not_replay_or_progress(self):
        self.targets()
        self.lua.execute('''
            ctx.actors={{id='companion',x=0,y=0},{id='host',x=120,y=0}}; tick(); assert(transient().targetId=='host')
            sys=R.new(); ctx.actors={{id='companion',x=0,y=0}}
            ctx.onContact=function() contacts=contacts+1; return false end
            tick(); tick(.4); tick(.1); tick(.5); assert(transient().state=='recover' and contacts==1 and #ctx.encounters==0)
            tick(.1); assert(contacts==1)
        ''')

    def test_tracked_target_keeps_authored_chase_path_when_line_of_sight_is_temporarily_lost(self):
        self.targets()
        self.lua.execute('''
            ctx.actors={{id='companion',x=0,y=0}}; tick(); tick(.4)
            local before=ctx.areaState.mobs.a.x; ctx.actors[1].x=-180
            ctx.canReach=function() return false end
            tick(.1); assert(transient().state=='chase' and transient().targetId=='companion')
            assert(ctx.areaState.mobs.a.x<before)
            ctx.actors[1].x=ctx.areaState.mobs.a.x-20
            before=ctx.areaState.mobs.a.x; tick(.1)
            assert(transient().state=='chase' and ctx.areaState.mobs.a.x<before)
        ''')


if __name__ == '__main__':
    unittest.main()
