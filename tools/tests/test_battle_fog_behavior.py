"""Tactical sight, durable exploration, hidden-target authority and local quality."""
import unittest
from tools.tests import test_coop_battles_behavior as fixtures


class BattleFogTests(unittest.TestCase):
    def setUp(self):
        fixture=fixtures.TacticalCommandTests(); fixture.setUp(); self.lua=fixture.lua
        self.lua.execute("Fog=require('game.battle_fog'); Field=require('game.battle_field'); Graphics=require('game.battle_graphics')")

    def test_unseen_enemies_cannot_be_targeted_even_with_a_forged_id(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();local enemy=b.units[3]
            local weapon=host.itemSlots.equipment[2];local ammo=host.ammo['22lr'];local revision=data.tacticalBattle.revision
            assert(not Fog.unitVisible(b,enemy))
            local reply=action('host','battle.attack',{weapon=weapon.id,targetId=enemy.id})
            assert(not reply.ok and reply.reason=='target_hidden')
            assert(host.ammo['22lr']==ammo and data.tacticalBattle.revision==revision)
            enemy.q,enemy.r=2,3;b.obstacles={}
            assert(Fog.unitVisible(b,enemy),'nearby enemy was not revealed')
            assert(action('host','battle.attack',{weapon=weapon.id,targetId=enemy.id}).ok)
        ''')

    def test_march_exploration_persists_and_lost_sight_hides_units(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();b.obstacles={};local enemy=b.units[3];enemy.hp=0
            assert(Fog.explored(b,1,3)and not Fog.explored(b,60,3))
            for q=9,25,8 do
                b.active=1;b.moveUsed=false;b.phase='select';ready()
                assert(action('host','battle.move',{q=q,r=3}).ok)
            end
            local loaded=assert(Schema.migrate(saved));local restored=assert(State.restore(loaded,Catalog))
            assert(Fog.validate(restored)and #restored.fog.explored==720)
            assert(Fog.explored(restored,12,3)and not Fog.visible(restored,12,3))
            enemy.hp=10;enemy.q,enemy.r=12,3;assert(not Fog.unitVisible(b,enemy))
            assert(not Fog.explored(b,60,3),'unvisited eastern terrain leaked')
            restored.fog.explored=restored.fog.explored:sub(2);assert(not Fog.validate(restored))
        ''')

    def test_party_shares_sight_and_terrain_blocks_it(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();b.obstacles={}
            b.units[2].q,b.units[2].r=40,3;b.units[3].q,b.units[3].r=43,3
            assert(Fog.unitVisible(b,b.units[3]),'companion did not share sight')
            b.units[2].hp=0;assert(not Fog.unitVisible(b,b.units[3]),'fallen companion still scouts')
            local elevations={}
            for x=0,b.field.columns do for z=0,b.field.rows do elevations[#elevations+1]=x==4 and '30'or'00' end end
            b.field.elevationData=table.concat(elevations)
            b.units[1].q,b.units[1].r=2,3
            assert(Fog.visible(b,3,3)and not Fog.visible(b,6,3),'ridge did not block scouting')
        ''')

    def test_draw_distance_is_local_persistent_and_does_not_change_sight(self):
        self.lua.execute('''
            local Prefs=require('game.local_preferences');local fs=F.filesystem();local store=Prefs.new(fs)
            store:attach(data,function()return'client'end)
            assert(begin().ok);local b=ready();local remembered=b.fog.explored;local revision=data.coop.revision
            local source=Fog.state(b)
            local wrapper={};for k,v in pairs(b)do wrapper[k]=v end
            assert(Fog.state(wrapper)==source,'guest draw wrapper recalculated sight')
            assert(Graphics.distance(data,true)==10 and Graphics.distance(data,false)==14)
            for _=1,4 do Graphics.adjust(data,1)end
            assert(Graphics.distance(data,true)==28 and store:save(true))
            local restored=Prefs.new(fs);restored:attach(data,function()return'client'end)
            assert(Graphics.distance(data,false)==28 and not data.graphics and not data.players.host.graphics)
            assert(b.fog.explored==remembered and Fog.state(b)==source and data.coop.revision==revision)
            restored.values.graphics.renderDistance=1/0;assert(restored:save())
            assert(Prefs.new(fs).values.graphics.renderDistance==0)
        ''')

    def test_turn_updates_omit_static_geometry_and_rejoin_restores_everything(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();local Net=require('game.net.game_state');local Codec=require('game.net.codec')
            local producer=Net.producer();local replica=Net.replica();local first=assert(producer:capture(data,true))
            assert(replica:apply(first));local geometry=producer.current.encoded.battlefield
            assert(replica.data.tacticalBattle.battle.field.elevationData==b.field.elevationData)
            for q=0,b.field.columns-1 do for r=1,b.field.rows do
                assert(replica.data.tacticalBattle.battle.tiles[q][r]==b.tiles[q][r])
                assert(replica.data.tacticalBattle.battle.tileVariants[q][r]==b.tileVariants[q][r])
            end end
            b.units[3].hp=0;assert(action('host','battle.move',{q=9,r=3}).ok)
            local delta=assert(producer:capture(data));assert(replica:apply(delta))
            for _,domain in ipairs(delta.domains)do assert(domain.id~='battlefield','move resent static terrain')end
            local encoded=assert(Codec.encode(delta,{maxBytes=32768,maxDepth=32,maxEntries=20000,maxStringBytes=8192}))
            assert(#encoded<8192 and producer.current.encoded.battlefield==geometry)
            assert(replica.data.tacticalBattle.battle.fog.explored==b.fog.explored)
            local rejoined=Net.replica();assert(rejoined:apply(assert(producer:baseline())))
            assert(rejoined.data.tacticalBattle.battle.units[1].q==9)
            assert(rejoined.data.tacticalBattle.battle.fog.explored==b.fog.explored)
        ''')

    def test_previous_native_field_remains_valid_at_its_saved_size(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();local f=b.field
            f.version=1;f.columns=36;f.rows=20;f.exitColumn=35;f.elevationData=string.rep('00',37*21)
            b.fog=nil;b.obstacles={}
            for q=0,71 do if q>=36 then b.tiles[q]=nil;b.tileVariants[q]=nil
                else for r=21,40 do b.tiles[q][r]=nil;b.tileVariants[q][r]=nil end end end
            assert(Field.validate(f)and State.validate(data))
            Fog.update(b);assert(#b.fog.explored==180 and State.validate(data))
        ''')


if __name__=='__main__': unittest.main()
