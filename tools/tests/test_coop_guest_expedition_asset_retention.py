"""Exercise private SceneView ownership and production expedition cache cleanup."""
import unittest
import test_coop_guest_view_behavior as scene_harness


class GuestExpeditionAssetRetentionTests(unittest.TestCase):
    def setUp(self):
        harness = scene_harness.SceneViewTests()
        harness.setUp()
        self.lua = harness.lua
        self.lua.execute('''
            Areas=require('game.expedition_areas');data.location=6;Areas.ensure(data)
            created={};sets={};loads=0;loadedBackgrounds={}
            function tracked(kind,name)
                local i=image();i.kind=kind;i.name=name;i.releases=0
                i.release=function(self)self.releases=self.releases+1;assert(self.releases==1,'image released twice')end
                created[#created+1]=i;return i
            end
            sourceBandit=tracked('borrowed','source-bandit');sourceNPC=tracked('borrowed','source-npc')
            ordinary=tracked('borrowed','ordinary');content.mobImages['sludge-bandit.png']=sourceBandit
            content.mobImages['dust-beetle.png']=ordinary;content.npcImages={['test-npc.png']=sourceNPC}
            love.graphics.newImage=function(path)
                if loadGuard then loadGuard(path)end
                loads=loads+1;local i=tracked('background',path);loadedBackgrounds[path]=i;return i
            end
            package.loaded['game.expedition_sprites'].load=function(spec)
                if loadGuard then loadGuard(spec.actionPath)end
                loads=loads+1;local frames={walkFrames={}}
                for n=1,6 do
                    frames[n]=aliasBoss and spec.boss and n==1 and sets.bandit[1] or tracked('atlas',spec.actionPath..':'..n)
                end
                for n=1,8 do frames.walkFrames[n]=tracked('atlas',spec.walkPath..':'..n)end
                sets[spec.boss and 'boss' or 'bandit']=frames;return frames
            end
            runtime.scene='expedition';data.scene='expedition';data.activeExpeditionArea=Areas.SURFACE_ID
            runtime.battle=nil
            scene=require('game.coop_scene_view').new({runtime=runtime,ui={playSfx=function()end},content=content,catalog=require('game.catalog')})
            function frameImages(frames)
                local all={};for _,i in ipairs(frames)do all[#all+1]=i end
                for _,i in ipairs(frames.walkFrames)do all[#all+1]=i end;return all
            end
            function live(frames)
                for _,i in ipairs(frameImages(frames))do assert(i.releases==0,'live frame discarded')end
            end
            function released(frames)
                for _,i in ipairs(frameImages(frames))do assert(i.releases==1,'dormant frame not released')end
            end
            function background(id)return loadedBackgrounds[Areas.definition(id).background]end
            function battleContext()
                local noop=function()end
                local v={runtime=runtime,ui={},mobile={enabled=false},scene=scene,renderer={drawLandscape=noop,drawGround=noop,drawAnimatedCharacter=noop},
                    camera={apply=noop,toWorld=noop,zoom=1,panX=0,panY=0},inventory={}}
                return require('game.coop_guest_battles').new(v,{content=content,colors={}}):context()
            end
            function aliases(ctx,frames)
                for name,index in pairs({mobImages=1,mobIdleImages=1,mobWalkImages=2,mobAttackImages=3,
                    mobHitImages=4,mobDeathImages=5,mobRangedImages=3})do
                    assert(ctx[name]['sludge-bandit.png']==frames[index],name..' lost current battle alias')
                end
            end
        ''')

    def test_surface_to_dungeon_prunes_old_background_before_load_and_keeps_common_frames(self):
        self.lua.execute('''
            assert(scene.prepare());local old=background(Areas.SURFACE_ID);local bandit=sets.bandit
            assert(loads==2 and old.releases==0);live(bandit)
            data.activeExpeditionArea=Areas.DUNGEON_ID;local before=Schema.copy(data)
            local count=loads;scene.prepareAssetRetention({range=false})
            assert(old.releases==1 and loads==count,'release preflight allocated new art');live(bandit)
            loadGuard=function()assert(old.releases==1,'new scene loaded before old background released');live(bandit)end
            assert(scene.prepare());assert(sets.bandit==bandit and sets.boss and loads==4)
            assert(background(Areas.DUNGEON_ID).releases==0 and identical(data,before));live(sets.boss)
            loadGuard=nil;scene.release();scene.release()
            assert(sourceBandit.releases==0 and sourceNPC.releases==0 and ordinary.releases==0)
        ''')

    def test_actual_battle_unit_aliases_survive_field_battle_result_and_return_without_hidden_field_background(self):
        self.lua.execute('''
            data.activeExpeditionArea=Areas.DUNGEON_ID;assert(scene.prepare())
            local bandit,boss=sets.bandit,sets.boss;local old=background(Areas.DUNGEON_ID)
            runtime.battle={units={{file='sludge-bandit.png'},{file=data.character}},finished=false}
            local before=Schema.copy(data);scene.prepareAssetRetention({range=false})
            assert(old.releases==1 and loads==3);live(bandit);released(boss)
            assert(rawget(scene.battleImages.mobImages,'sludge-badger-boss.png')==nil)
            assert(scene.prepare());assert(loads==3);aliases(battleContext(),bandit)
            runtime.battle.finished=true;scene.prepareAssetRetention({range=false});assert(scene.prepare())
            aliases(battleContext(),bandit);live(bandit);assert(loads==3 and identical(data,before))
            runtime.battle=nil;assert(scene.prepare())
            assert(loads==5 and sets.bandit==bandit and sets.boss~=boss)
            assert(background(Areas.DUNGEON_ID)~=old);aliases({mobImages=scene.battleImages.mobImages,
                mobIdleImages=scene.battleImages.mobIdleImages,mobWalkImages=scene.battleImages.mobWalkImages,
                mobAttackImages=scene.battleImages.mobAttackImages,mobHitImages=scene.battleImages.mobHitImages,
                mobDeathImages=scene.battleImages.mobDeathImages,mobRangedImages=scene.battleImages.mobRangedImages},bandit)
        ''')

    def test_late_join_in_battle_loads_only_actual_enemy_atlas_not_field_background_or_unrelated_boss(self):
        self.lua.execute('''
            data.activeExpeditionArea=Areas.DUNGEON_ID
            runtime.battle={units={{file='sludge-bandit.png'},{file=data.character}},finished=false}
            local before=Schema.copy(data);assert(scene.prepare())
            assert(loads==1 and sets.bandit and not sets.boss and background(Areas.DUNGEON_ID)==nil)
            aliases(battleContext(),sets.bandit);live(sets.bandit);assert(identical(data,before))
            runtime.scene='train';data.scene='train';runtime.battle=nil;local count=loads
            scene.prepareAssetRetention({range=false});released(sets.bandit);assert(loads==count)
            assert(scene.battleImages.mobImages['sludge-bandit.png']==sourceBandit and sourceBandit.releases==0)
            assert(scene.prepare() and loads==count);scene.release();scene.release()
        ''')

    def test_private_range_active_last_stand_and_ambush_release_only_private_owned_caches(self):
        self.lua.execute('''
            assert(scene.prepare());local bandit=sets.bandit;local bg=background(Areas.SURFACE_ID);local count=loads
            scene.prepareAssetRetention({range=true});assert(bg.releases==1);released(bandit);assert(loads==count)
            assert(scene.prepare() and loads==count,'hidden range reloaded field art')
            scene.prepareAssetRetention({range=false});assert(scene.prepare());live(sets.bandit)
            bandit=sets.bandit;bg=background(Areas.SURFACE_ID);count=loads
            data.lastStand={lifecycle={mode='offer'}}
            scene.prepareAssetRetention({range=false});assert(bg.releases==1);released(bandit);assert(loads==count)
            data.lastStand=nil;assert(scene.prepare());bandit=sets.bandit;bg=background(Areas.SURFACE_ID)
            runtime.scene='train';data.scene='train';data.trainAmbush={active=true}
            scene.prepareAssetRetention({range=false});assert(bg.releases==1);released(bandit)
            assert(sourceBandit.releases==0 and sourceNPC.releases==0 and ordinary.releases==0)
        ''')

    def test_pruning_alias_owned_by_kept_battle_mob_never_releases_it_and_final_release_is_once(self):
        self.lua.execute('''
            assert(scene.prepare());local bandit=sets.bandit
            data.activeExpeditionArea=Areas.DUNGEON_ID;aliasBoss=true;assert(scene.prepare())
            local boss=sets.boss;assert(boss[1]==bandit[1])
            runtime.battle={units={{file='sludge-bandit.png'}}};scene.prepareAssetRetention({range=false})
            live(bandit);assert(boss[1].releases==0)
            for i=2,6 do assert(boss[i].releases==1)end
            for _,i in ipairs(boss.walkFrames)do assert(i.releases==1)end
            aliases(battleContext(),bandit)
            scene.release();released(bandit);scene.release()
            assert(sourceBandit.releases==0)
        ''')

    def test_borrowed_ordinary_enemy_images_remain_owned_by_original_content(self):
        self.lua.execute('''
            data.activeExpeditionArea=Areas.BADLANDS_SURFACE_ID;assert(scene.prepare())
            assert(scene.battleImages.mobImages['dust-beetle.png']==ordinary and ordinary.releases==0)
            runtime.battle={units={{file='dust-beetle.png'}}};scene.prepareAssetRetention({range=false});assert(scene.prepare())
            assert(scene.battleImages.mobImages['dust-beetle.png']==ordinary and ordinary.releases==0)
            runtime.scene='train';data.scene='train';runtime.battle=nil;scene.prepareAssetRetention({range=false})
            assert(ordinary.releases==0);scene.release();scene.release();assert(ordinary.releases==0)
        ''')

    def test_original_runtime_ensure_defaults_do_not_implicitly_prune_offline_assets(self):
        self.lua.execute('''
            local expedition
            for i=1,100 do local name,value=debug.getupvalue(scene.prepare,i)
                if name=='expedition'then expedition=value end
            end
            assert(expedition)
            expedition.ensureAssets(Areas.definition(Areas.SURFACE_ID))
            local old=background(Areas.SURFACE_ID);local bandit=sets.bandit
            expedition.ensureAssets(Areas.definition(Areas.DUNGEON_ID))
            assert(old.releases==0 and loads==4 and sets.bandit==bandit)
            live(bandit);live(sets.boss)
            expedition.release();expedition.release()
            assert(old.releases==1 and background(Areas.DUNGEON_ID).releases==1)
            released(bandit);released(sets.boss);assert(sourceBandit.releases==0)
        ''')


if __name__ == '__main__':
    unittest.main()
