"""Safe flood planning for both authoritative actors without scene progression."""
import unittest
import test_coop_roaming_behavior as field


class FloodPartyTests(unittest.TestCase):
    setUp = field.RoamingCommandTests.setUp

    def flood(self):
        self.lua.execute('''
            setup(); Areas=require('game.expedition_areas'); Hazards=require('game.coop_expedition_hazards')
            data.location=5; data.scene='expedition'; data.activeExpeditionArea=Areas.BADLANDS_BASIN_ID
            Areas.ensure(data); state=data.expeditions[data.activeExpeditionArea]
            state.environmentPhase='flooded'; state.environmentClock=14.01
            actors={{id='host',x=780,y=500},{id='companion',x=806,y=500}}
            function plan() return Hazards.plan(data,data.activeExpeditionArea,actors) end
        ''')

    def test_both_players_reach_separate_safe_walkable_banks(self):
        self.flood()
        self.lua.execute('''
            local epoch=data.coop.sceneEpoch; local health=host.health; local points=assert(plan())
            assert(points.host and points.companion)
            for _,p in pairs(points) do
                assert(Areas.isWalkable(data,data.activeExpeditionArea,p.x,p.y) and not Areas.isInFlood(data,data.activeExpeditionArea,p.x,p.y))
            end
            assert((points.host.x-points.companion.x)^2+(points.host.y-points.companion.y)^2>=24^2)
            assert(data.coop.sceneEpoch==epoch and data.scene=='expedition' and host.health==health)
            assert(actors[1].x==780 and actors[2].x==806)
        ''')

    def test_safe_actor_reserves_the_nearest_bank_for_flooded_companion(self):
        self.flood()
        self.lua.execute('''
            actors[1].x,actors[1].y=690,515
            local points=assert(plan()); assert(not points.host and points.companion)
            assert((points.companion.x-690)^2+(points.companion.y-515)^2>=24^2)
        ''')

    def test_legacy_single_host_lands_at_existing_nearest_bank(self):
        self.flood()
        self.lua.execute('''
            actors[2]=nil; local x,y=Areas.nearestFloodBank(data,data.activeExpeditionArea,actors[1].x,actors[1].y)
            local points=assert(plan()); assert(points.host.x==x and points.host.y==y and not points.companion)
        ''')

    def test_dry_areas_and_safe_party_need_no_relocation(self):
        self.flood()
        self.lua.execute('''
            state.environmentPhase='warning'; assert(next(assert(plan()))==nil)
            assert(next(assert(Hazards.plan(data,Areas.BADLANDS_SURFACE_ID,actors)))==nil)
        ''')

    def test_no_available_bank_does_not_return_partial_corrections(self):
        self.flood()
        self.lua.execute('''
            local original=Areas.isWalkable; Areas.isWalkable=function() return false end
            local points,reason=plan(); Areas.isWalkable=original
            assert(not points and reason=='bank_unavailable' and actors[1].x==780 and actors[2].x==806)
        ''')

    def test_invalid_or_duplicate_actor_claims_are_rejected(self):
        self.flood()
        self.lua.execute('''
            actors[2].id='host'; assert(not plan())
            actors[2].id='companion'; actors[2].x=math.huge; assert(not plan())
            actors[2].x=806; actors[2].id='claimed'; assert(not plan())
        ''')


if __name__ == '__main__':
    unittest.main()
