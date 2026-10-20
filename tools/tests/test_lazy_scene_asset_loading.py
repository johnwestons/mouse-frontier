"""Execute production loaders/renderers with source asset dimensions by default.

Graphics objects are allocation/identity instrumentation, not a GPU emulator.
Pixel byte totals are nominal RGBA and are not Android PSS measurements.
"""
from collections import Counter
from functools import lru_cache
from pathlib import Path
import json
import hashlib
import os
import sys
import unittest
from unittest import mock
import tempfile

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / 'output/mobile/stage'
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime
from PIL import Image


@lru_cache(maxsize=4)
def dimensions(asset_root):
    result = {}
    for path in (asset_root / 'assets').rglob('*.png'):
        with Image.open(path) as image:
            result[path.relative_to(asset_root).as_posix()] = image.size
    return result


class AllocationProbe:
    def __init__(self, code_root=ROOT, asset_root=ROOT):
        self.events = []
        self.asset_root = Path(asset_root)
        asset_root = self.asset_root
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.codeRoot = code_root.as_posix()
        g.pyDimensions = lambda p: dimensions(asset_root)[str(p)]
        g.pyExists = lambda p: (asset_root / str(p)).exists()
        g.pyIsDirectory = lambda p: (asset_root / str(p)).is_dir()
        g.pyDirectory = lambda p: self.lua.table_from(sorted(a.name for a in (asset_root / str(p)).iterdir()))
        g.record = lambda kind, path: self.events.append((kind, str(path)))
        self.lua.execute('''
            package.path=codeRoot..'/?.lua;'..package.path
            local noop=function()end
            love={math={random=math.random},filesystem={},graphics={},image={},mouse={getPosition=function()return 0,0 end}}
            love.filesystem.getInfo=function(p)if pyExists(p)then return {type=pyIsDirectory(p)and'directory'or'file'}end end
            love.filesystem.getDirectoryItems=function(p)return pyDirectory(p)end
            function object(path,kind)
                local w,h=pyDimensions(path)
                return {path=path,kind=kind,releases=0,getDimensions=function(self)assert(self.releases==0);return w,h end,
                    getWidth=function(self)assert(self.releases==0);return w end,getHeight=function(self)assert(self.releases==0);return h end,
                    setFilter=noop,setWrap=noop,mapPixel=noop,
                    release=function(self)assert(self.releases==0,'double release '..path);self.releases=1;record('release-'..kind,path)end}
            end
            love.graphics.newImage=function(path)
                if type(path)=='table'then path=path.path end
                local value=object(path,'texture');record('texture',path);return value
            end
            love.image.newImageData=function(path)local value=object(path,'pixels');record('pixels',path);return value end
            love.graphics.newQuad=function(x,y,w,h)return {getViewport=function()return x,y,w,h end,setViewport=noop,release=noop}end
            love.graphics.newShader=function()return {send=noop,release=noop}end
            love.graphics.getDimensions=function()return 2340,1080 end
            love.graphics.transformPoint=function(x,y)return x,y end
            love.graphics.inverseTransformPoint=function(x,y)return x/1.5-300,y/1.5 end
            local font={getWidth=function(_,value)return #tostring(value)*10 end,getHeight=function()return 20 end,
                getLineHeight=function()return 1.08 end,getWrap=function(_,value,width)
                    local lines={};for i=1,math.max(1,math.ceil(#tostring(value)*10/width))do lines[i]='line'end
                    return math.min(width,#tostring(value)*10),lines end}
            love.graphics.getFont=function()return font end
            love.graphics.draw=function(image)assert(image.releases==0,'renderer used released '..image.path);record('draw',image.path)end
            setmetatable(love.graphics,{__index=function()return noop end})
            Assets=require('game.assets');targets={}
            for _,name in ipairs({'ui','scenery','characters','characterImages','npcImages','mobImages','mobFiles',
                'characterWalkImages','npcWalkImages','characterActionImages','mobAttackImages','mobIdleImages',
                'mobHitImages','mobDeathImages','mobWalkImages','mobRangedImages','backgroundImages','familyImages','itemIdleImages'})do targets[name]={}end
            animations=Assets.load(targets);scenery=targets.scenery
            Settlements=require('game.settlements');scenery.settlements=Settlements.load(love.graphics.newImage)
            streamer=require('game.asset_streamer').new({scenery=scenery,settlements=scenery.settlements,
                characterAnimations=animations,legacyAnimationTables={},interiorFiles=scenery.interiorFiles})
            data={character='scavenger-mouse.png',location=1,trainCars={'living-car'},passengers={},droppedItems={},currentNPC=nil}
            runtime={state='game',scene='train',saveData=data,player={x=300,y=480,facing=1},animationClock=0,sceneryOffset=0,landscapeOffset=0}
            function retain(scene,state)
                runtime.scene=scene;runtime.state=state or 'game'
                Assets.releaseIntroImages(scenery,runtime)
                streamer:update(runtime.state,scene,data,runtime.battle,runtime.npcActor,nil,'engineer-frog.png')
            end
            function renderer()
                local context={runtime=runtime,width=960,height=720,backgroundImages=targets.backgroundImages,scenery=scenery,
                    car={x=445,y=246,w=455,h=310},colors={cream={1,1,1}},landscape={},getCharacterAnimations=function()return {}end,
                    ensureStopLayout=function()return {interior=1}end,ui={propImages={},assetStreamer=streamer},
                    settlements=Settlements,train=require('game.train'),characterAnimation=require('game.character_animation'),
                    family=require('game.family'),catalog=require('game.catalog'),stops=require('game.stops'),util=require('game.util')}
                for _,name in ipairs({'characterImages','characterWalkImages','characterActionImages','itemIdleImages','npcImages',
                    'npcWalkImages','familyImages','mobImages','mobIdleImages','mobWalkImages','mobHitImages','mobDeathImages'})do context[name]=targets[name]end
                for _,name in ipairs({'drawStopSludges','drawShootingRangeSpot','drawWildlife','drawExpedition','drawExpeditionTrailhead',
                    'drawCaravanRuntime','drawCaravanGate','itemIsHere','pendingMailHere'})do context[name]=noop end
                return require('game.world_renderer').new(context)
            end
            function screens()
                local context={runtime=runtime,width=960,height=720,ui=targets.ui,colors={cream={1,1,1}},scenery=scenery,
                    characters=targets.characters,characterImages=targets.characterImages,npcImages=targets.npcImages,
                    util=require('game.util'),catalog=require('game.catalog'),screenToGame=function(x,y)return x,y end,
                    mobileEnabled=function()return true end,getCharacterAnimations=function()return {}end}
                for _,name in ipairs({'inventory','eventUI','engineUpgrades','trainUpgradeBalance','playerProgression',
                    'stopHelpProgression','npcRelationships','merchantTrade','finaleProgression','maintenance'})do context[name]={}end
                for _,name in ipairs({'readSave','canChooseEvent','writeSave','ensureStopLayout','currentTradeSource','drawLandscape',
                    'drawTracks','drawLocomotive','drawTrainCar','drawAnimatedCharacter','isWeapon','travelCost','repairStatus','questSummary'})do context[name]=noop end
                require('game.screen_ui').new(context);return targets.ui
            end
            function gameplay()
                local context={runtime=runtime,width=960,holdPickupSeconds=1,ui=targets.ui,car={},landscape={},scenery=scenery,
                    cloudLayer=require('game.clouds').new(scenery.cloudImages),catalog=require('game.catalog'),settlements=Settlements,clouds=require('game.clouds'),
                    screens={is=function(_,s)return runtime.state==s end,update=function()return true end}}
                for _,name in ipairs({'maintenanceSession','interactionRouter','inventoryActions','journeyRules','interiorDoors','interactions',
                    'engineUpgrades','trainUpgradeBalance','maintenance','family','util','passengers','firstAid','shootingRange','controlBindings'})do context[name]={}end
                for _,name in ipairs({'mobileEnabled','mobileMovement','mobileHeld','mobileSprinting','updatePersistence','screenToGame','updateAudio',
                    'ensureStopLayout','updateWorldScene','currentShootingRange','handleShootingRange','clampToTrainFloor','itemIsHere','setupNPC',
                    'trainFloorBounds','moveExpedition','currentExpeditionInteraction','moveCaravan','currentCaravanInteraction','updateCarTransition','writeSave'})do context[name]=noop end
                return require('game.gameplay_update').new(context)
            end
        ''')

    def profile(self):
        allocations = []
        for kind, path in self.events:
            if kind not in ('texture', 'pixels'):
                continue
            w, h = dimensions(self.asset_root)[path]
            allocations.append({'kind': kind, 'path': path, 'width': w, 'height': h, 'nominalRGBABytes': w * h * 4})
        return {'allocations': allocations,
                'textureCount': sum(a['kind'] == 'texture' for a in allocations),
                'textureNominalRGBABytes': sum(a['nominalRGBABytes'] for a in allocations if a['kind'] == 'texture'),
                'cpuImageDataNominalRGBABytes': sum(a['nominalRGBABytes'] for a in allocations if a['kind'] == 'pixels'),
                'explicitPixelReleaseCount': sum(k == 'release-pixels' for k, _ in self.events)}


class LazySceneAssetTests(unittest.TestCase):
    def setUp(self):
        self.p = AllocationProbe()
        self.lua = self.p.lua

    def test_production_startup_does_not_decode_unrelated_scenes_or_portraits(self):
        loads = [path for kind, path in self.p.events if kind == 'texture']
        forbidden = ('/MainCharacters/', '/NPCS/families/', '/train/', '/stop-wildlife/', '/ui/title/', '/Mobs/atlases/')
        self.assertFalse([p for p in loads if any(s in p for s in forbidden)])
        self.assertEqual(len(loads), 19)
        self.lua.execute("assert(#targets.characters==47 and Assets.assertHealthy())")

    def test_default_source_probe_works_without_an_ignored_mobile_package(self):
        missing_stage = ROOT / 'output/mobile-package-not-present-for-source-test'
        self.assertFalse(missing_stage.exists())
        with mock.patch(__name__ + '.STAGE', missing_stage):
            probe = AllocationProbe()
        self.assertEqual(probe.asset_root, ROOT)
        self.assertEqual(probe.profile()['textureCount'], 19)
        self.assertEqual(dimensions(ROOT)['assets/sprites/MainCharacters/engineer-frog.png'], (512, 512))

    def test_late_assets_and_guest_view_import_never_consumes_combat_rng(self):
        for module in ('game.assets', 'game.coop_guest_view'):
            lua = LuaRuntime(unpack_returned_tuples=True)
            lua.globals().root = ROOT.as_posix()
            lua.globals().moduleName = module
            lua.execute('''
                package.path=root..'/?.lua;'..package.path
                local function combatRNG()error('late renderer import consumed combat RNG')end
                math.random=combatRNG;math.randomseed=combatRNG
                love={math={random=combatRNG}}
                local loaded=require(moduleName);assert(loaded)
                assert(package.loaded['game.title_snapshots']==nil,'title shuffle imported during combat')
            ''')

    def test_real_train_and_stop_renderers_keep_aliases_and_release_before_new_upload(self):
        self.lua.execute('''
            retain('train');local draw=renderer();draw.drawTracks();draw.drawLocomotive();draw.drawTrainCar(1)
            engine=scenery.worldTrainBody;gear=scenery.worldTrainRunningGear.image
            marker=scenery.redTrain;assert(scenery.worldTrain==marker)
            retain('train');draw.drawLocomotive();assert(scenery.worldTrainBody==engine and engine.releases==0)
            retain('stop');assert(engine.releases==1 and gear.releases==1 and marker.releases==0)
            draw.drawStop();assert(marker.releases==0 and scenery.redTrain==marker)
            stopIdle=scenery.sludgeAnimations.idle.image
            assert(scenery.sludgeAnimations.idle==scenery.sludgeAnimations.walk)
            retain('train');assert(stopIdle.releases==1 and marker.releases==0)
            draw.drawLocomotive();assert(scenery.worldTrainBody~=engine)
        ''')
        release = self.p.events.index(('release-texture', 'assets/sprites/train/animations/locomotive-red-body-v2.png'))
        load = self.p.events.index(('texture', 'assets/sprites/stops/settlement-wide-01.png'))
        self.assertLess(release, load)

    def test_title_cache_is_stable_each_frame_and_bounded_across_complete_cycle(self):
        self.lua.execute('''
            runtime.state='slots'
            local Snapshots=require('game.title_snapshots')
            for step=0,600 do
                runtime.animationClock=step
                Assets.releaseIntroImages(scenery,runtime)
                local header=scenery.titleHeaderBackdrop;local footer=scenery.titleFooterBackdrop;local logo=scenery.titleImage
                for side=0,1 do local playback=Snapshots.playback(step,side);assert(scenery.titleSnapshotSprites[playback.id])end
                local count=0;for key in pairs(scenery)do if tostring(key):match('^titleSnapshot_')then count=count+1 end end
                assert(count==2)
                Assets.releaseIntroImages(scenery,runtime)
                assert(header==scenery.titleHeaderBackdrop and footer==scenery.titleFooterBackdrop and logo==scenery.titleImage)
                assert(header.releases==0 and footer.releases==0 and logo.releases==0)
            end
            local logo=scenery.titleImage;runtime.state='characters';Assets.releaseIntroImages(scenery,runtime)
            assert(logo.releases==1 and rawget(scenery,'titleImage')==nil)
        ''')
        counts = Counter(p for k, p in self.p.events if k == 'texture')
        for name in ('title-header-backdrop-v1.png', 'title-footer-backdrop-v1.png', 'title-option-3.png'):
            self.assertEqual(counts['assets/sprites/ui/title/' + name], 1)

    def test_actual_gameplay_update_and_title_intro_character_renderers_do_not_churn(self):
        self.lua.execute('''
            local Intro=require('game.intro_cinematic');runtime.state='intro';runtime.saveData=nil
            local intro=Intro.new(10);intro.timer=2;Intro.draw(intro,scenery,{cream={1,1,1}},960,720)
            local background=scenery.introBackground
            local ui=screens();local update=gameplay();runtime.walkingSoundTimer=0;runtime.actionTimer=0
            targets.ui.assetStreamer=streamer;runtime.state='slots'
            for frame=1,180 do update.update(1/60);ui.drawSlots()end
            assert(background.releases==0,'the save windows share the intro scenery')
            runtime.state='characters';runtime.characterScroll=0;ui.drawCharacterSelect()
            local first=targets.characterImages[targets.characters[1]];assert(first.releases==0)
            for frame=1,120 do update.update(1/60);ui.drawCharacterSelect()end
            assert(background.releases==1,'intro scenery is released after leaving the title')
            assert(first.releases==0)
            runtime.state='slots';update.update(1/60);ui.drawSlots();assert(first.releases==1)
        ''')
        counts = Counter(p for k, p in self.p.events if k == 'texture')
        self.assertEqual(counts['assets/sprites/ui/title/title-header-backdrop-v1.png'], 2)
        self.assertEqual(counts['assets/sprites/ui/title/title-footer-backdrop-v1.png'], 2)
        self.assertEqual(counts['assets/sprites/MainCharacters/' + str(self.lua.globals().targets.characters[1])], 1)

    def test_actual_item_atlas_consumers_are_lazy_enumerable_shared_and_reload_after_title(self):
        self.lua.execute('''
            local before=0;for _ in pairs(targets.ui.atlasItems)do before=before+1 end;assert(before==40)
            local model=require('game.player_tools_model').build(love.filesystem,targets.ui.atlasItems)
            assert(#model>40)
            local ui=targets.ui;local record=ui.atlasItems['trail-beans-can'];assert(rawget(record,'image')==nil)
            local image=record.image;assert(image==ui.atlasItems['dried-berry-pouch'].image)
            require('game.inventory_ui').drawItem({ui=ui,Catalog=require('game.catalog'),colors={}},'trail-beans-can',{x=0,y=0,w=64,h=64})
            local weapon=require('game.weapon_attachment').itemSprite(ui,'compact-scrap-pistol')
            assert(weapon.image==ui.atlasItems['machine-pistol'].image)
            retain('train');assert(image.releases==0 and weapon.image.releases==0)
            streamer:update('slots','train',nil);assert(image.releases==1 and weapon.image.releases==1)
            assert(rawget(record,'image')==nil and record.image~=image)
            assert(ui.atlasItems['trail-beans-can']==record)
        ''')
        self.assertEqual(sum(k == 'texture' and p.endswith('/food-water-v1.png') for k, p in self.p.events), 2)

    def test_intro_guest_join_and_character_selection_keep_exact_live_portraits(self):
        self.lua.execute('''
            local intro=scenery.introBackground
            Assets.releaseIntroImages(scenery);assert(intro.releases==1)
            local host=targets.characterImages['engineer-frog.png'];local guest=targets.characterImages[data.character]
            local old=targets.characterImages['medic-cat.png']
            retain('train');assert(host.releases==0 and guest.releases==0 and old.releases==1)
            runtime.state='characters'
            streamer:update('characters','train',nil,nil,nil,'engineer-frog.png')
            local preview=targets.characterImages['medic-cat.png'];streamer:update('characters','train',nil,nil,nil,'medic-cat.png')
            assert(preview.releases==0 and host.releases==0)
            streamer:update('slots','train',nil);assert(preview.releases==1 and host.releases==1 and guest.releases==1)
            retain('train');assert(targets.characterImages[data.character]~=guest)
        ''')

    def test_real_wildlife_and_family_paths_are_lazy_and_shared_mouse_releases_once(self):
        self.lua.execute('''
            retain('stop')
            local Wildlife=require('game.wildlife');local Mice=require('game.mice');local Family=require('game.family')
            Wildlife.draw({{kind='hen',x=100,y=500,facing=1,moving=true}},scenery.stopWildlife,2)
            Mice.draw({{x=200,y=500,facing=1,moving=true,phase=0}},scenery.stopWildlife,2)
            local mouse=scenery.stopWildlife['field-mouse-walk.png'];assert(mouse==scenery.stopWildlife['field-mouse-walk'])
            local kind
            for _,file in ipairs(love.filesystem.getDirectoryItems('assets/sprites/NPCS/families'))do
                kind=file:match('^(.-)%-idle%-1%.png$');if kind then break end
            end
            local actor={family={{kind=kind,x=300,y=500,facing=1,moving=false}}}
            Family.draw(actor,targets.familyImages,0);local first=targets.familyImages[kind..'-idle-1']
            runtime.npcActor=actor;retain('stop');Family.draw(actor,targets.familyImages,0);assert(first.releases==0)
            retain('train');assert(mouse.releases==1 and first.releases==1)
            retain('stop');Mice.draw({{x=200,y=500,facing=1,moving=false,phase=0}},scenery.stopWildlife,2)
            assert(scenery.stopWildlife['field-mouse-walk.png']~=mouse)
        ''')
        self.assertEqual(sum(k == 'texture' and p.endswith('field-mouse-walk.png') for k, p in self.p.events), 2)

    def test_all_visible_resident_families_stay_loaded_and_release_by_scene_and_door(self):
        self.lua.execute('''
            local SceneNPCs=require('game.scene_npcs');local Family=require('game.family')
            local first={file='hedgehog-botanist.png',scene='stop',homeDoor=1,
                family={{kind='hedgehog-child',x=300,y=500,facing=1}}}
            local second={file='opossum-medic.png',scene='stop',homeDoor=2,
                family={{kind='opossum-child',x=500,y=500,facing=1}}}
            local inside={file='signal-hedgehog.png',scene='house',homeDoor=1,
                family={{kind='hedgehog-baby',x=400,y=480,facing=1}}}
            data.stopLayouts={['1']={residentVersion=1,residentKeys={'first','second','inside'}}}
            data.npcStates={first=first,second=second,inside=inside}
            data.currentNPC=first.file;runtime.npcActor=first
            local function drawFamilies()
                for _,actor in ipairs(SceneNPCs.list(data,runtime.scene,data.activeHouseDoor))do
                    for _,pose in ipairs({'walk','lay','idle'})do
                        for _,child in ipairs(actor.family)do child.moving=pose=='walk';child.sleeping=pose=='lay'end
                        Family.draw(actor,targets.familyImages,0)
                        Family.draw(actor,targets.familyImages,pose=='walk' and 1 or 2)
                    end
                end
            end
            local function images(kind)
                local result={}
                for _,pose in ipairs({'walk','lay','idle'})do for frame=1,2 do
                    local key=kind..'-'..pose..'-'..frame
                    result[key]=assert(rawget(targets.familyImages,key),'family renderer did not load '..key)
                end end
                return result
            end
            local function check(objects,released)
                for key,image in pairs(objects)do
                    assert(image.releases==released,'incorrect family retention for '..key)
                    if released==0 then assert(rawget(targets.familyImages,key)==image,'family image replaced '..key)end
                end
            end
            retain('stop');drawFamilies()
            local firstImages=images('hedgehog-child');local secondImages=images('opossum-child')
            for frame=1,120 do retain('stop');drawFamilies();check(firstImages,0);check(secondImages,0)end
            assert(rawget(targets.familyImages,'hedgehog-baby-idle-1')==nil,'hidden household loaded')
            second.scene='house'
            retain('stop');drawFamilies();check(firstImages,0);check(secondImages,1)
            data.activeHouseDoor=2;retain('house');drawFamilies()
            check(firstImages,1);check(secondImages,1)
            local returnedImages=images('opossum-child');check(returnedImages,0)
            assert(rawget(targets.familyImages,'hedgehog-baby-idle-1')==nil,'wrong household loaded')
            data.activeHouseDoor=1;retain('house');drawFamilies();check(returnedImages,1)
            local babyImages=images('hedgehog-baby');check(babyImages,0)
            retain('train');check(babyImages,1)
        ''')
        family_loads = Counter(p for k, p in self.p.events if k == 'texture' and '/NPCS/families/' in p)
        for kind, count in (('hedgehog-child', 1), ('opossum-child', 2), ('hedgehog-baby', 1)):
            for pose in ('walk', 'lay', 'idle'):
                for frame in (1, 2):
                    self.assertEqual(family_loads[f'assets/sprites/NPCS/families/{kind}-{pose}-{frame}.png'], count)
        self.assertEqual(sum(family_loads.values()), 24)

    def test_generated_pixel_buffers_release_on_success_and_failed_upload(self):
        self.lua.execute('''
            local sludges=scenery.sludgeAnimations;local obstacles=scenery.battleObstacles
            assert(sludges.idle.image.releases==0 and obstacles.image.releases==0)
            Assets.releaseDormantSceneArt(scenery,{state='slots',scene='train'})
            local old=love.graphics.newImage
            love.graphics.newImage=function(path)if type(path)=='table'then error('simulated upload failure')end;return old(path)end
            local failed=scenery.sludgeAnimations;assert(failed.idle==nil and failed.attack==nil)
        ''')
        counts = Counter((k, p) for k, p in self.p.events)
        for (kind, path), count in counts.items():
            if kind == 'pixels' and '/walkmask-' not in path:
                self.assertEqual(counts[('release-pixels', path)], count)

    def test_alias_in_kept_group_and_external_owner_are_never_released(self):
        self.lua.execute('''
            local destination={};local Groups=require('game.lazy_asset_groups');local groups=Groups.new(destination)
            local shared=object('assets/sprites/MainCharacters/engineer-frog.png','texture')
            groups:add('old','old',function()return {image=shared}end);groups:add('live','live',function()return shared end)
            assert(destination.old and destination.live);groups:retain({live=true});assert(shared.releases==0)
            groups:retain({}, {borrowed=shared});assert(shared.releases==0)
        ''')

    def test_private_shooter_and_checked_modal_facts_drop_hidden_train_without_loading_replacements(self):
        self.lua.execute('''
            retain('train');renderer().drawLocomotive();local engine=scenery.worldTrainBody
            Assets.releaseDormantSceneArt(scenery,runtime,{firstAid=true})
            assert(engine.releases==0,'ordinary aid overlays keep their world underlay')
            Assets.releaseDormantSceneArt(scenery,runtime,{shootingRange=true})
            assert(engine.releases==1 and rawget(scenery,'worldTrainBody')==nil)
            retain('train');renderer().drawLocomotive();engine=scenery.worldTrainBody
            data.trainAmbush={active=true};retain('train');assert(engine.releases==1)
            data.trainAmbush=nil;retain('train');renderer().drawLocomotive();engine=scenery.worldTrainBody
            data.lastStand={lifecycle={mode='escort'}};retain('train');assert(engine.releases==1)
            data.lastStand=nil;retain('train');renderer().drawLocomotive();engine=scenery.worldTrainBody
            runtime.battle={};retain('train','battle');assert(engine.releases==1)
            local obstacles=scenery.battleObstacles.image;local projectiles=scenery.projectiles.image
            retain('train','battle');assert(obstacles.releases==0 and projectiles.releases==0)
            runtime.battle=nil;retain('train');assert(obstacles.releases==1 and projectiles.releases==1)
        ''')


class ImmutableBaselineProfileTests(unittest.TestCase):
    def test_newer_baseline_rejected_before_allocating_or_overwriting_report(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            baseline = Path(directory)
            (baseline/'mobile-build.json').write_text(json.dumps({'versionCode': 32}), encoding='utf-8')
            output = baseline/'historical-report.json'
            output.write_text('original report', encoding='utf-8')
            with mock.patch(__name__ + '.AllocationProbe') as allocation:
                with self.assertRaisesRegex(ValueError, 'version 31.*32'):
                    write_profile(output, baseline)
                allocation.assert_not_called()
            self.assertEqual(output.read_text(encoding='utf-8'), 'original report')

    def test_explicit_version31_baseline_is_used_for_both_code_comparisons(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            baseline = Path(directory)
            network = {'protocol': 29, 'build': 'immutable31'}
            (baseline/'mobile-build.json').write_text(json.dumps({'versionCode': 31, 'network': network}), encoding='utf-8')
            output = baseline/'report.json'
            fake = mock.Mock()
            fake.profile.return_value = {'textureCount': 0, 'textureNominalRGBABytes': 0}
            with mock.patch(__name__ + '.AllocationProbe', return_value=fake) as allocation:
                write_profile(output, baseline)
            self.assertEqual(allocation.call_args_list, [mock.call(baseline, asset_root=baseline), mock.call(ROOT, asset_root=baseline)])
            self.assertEqual(json.loads(output.read_text(encoding='utf-8'))['immutableStageNetwork'], network)


def write_profile(path, baseline_root):
    baseline_root = Path(baseline_root).resolve()
    metadata = json.loads((baseline_root/'mobile-build.json').read_text(encoding='utf-8'))
    if metadata.get('versionCode') != 31:
        raise ValueError('Profiling requires an explicit version 31 baseline; supplied versionCode is '
                         + str(metadata.get('versionCode')) + '. The historical report was not changed.')
    def capture(code_root):
        probe = AllocationProbe(code_root, asset_root=baseline_root)
        startup = probe.profile()
        probe.lua.execute('''
            local ui=screens();local update=gameplay();runtime.state='slots';runtime.saveData=nil
            runtime.walkingSoundTimer=0;runtime.actionTimer=0;targets.ui.assetStreamer=streamer
            for frame=1,180 do update.update(1/60);ui.drawSlots()end
        ''')
        total = probe.profile()
        return startup, {'frames': 180, 'seconds': 3,
                         'cumulativeTextureAllocationsAfterStartup': total['textureCount'] - startup['textureCount'],
                         'cumulativeNominalRGBAUploadBytesAfterStartup': total['textureNominalRGBABytes'] - startup['textureNominalRGBABytes']}
    baseline, baseline_title = capture(baseline_root)
    candidate, candidate_title = capture(ROOT)
    files = ['game/assets.lua', 'game/lazy_asset_groups.lua', 'game/asset_streamer.lua', 'game/startup_runtime.lua', 'game/gameplay_update.lua']
    path.write_text(json.dumps({'method': 'Actual Assets.load, Settlements.load, GameplayUpdate and ScreenUI drawSlots with instrumented allocation API; exact mobile31 PNG dimensions. No GPU/native/ADB. Nominal RGBA bytes and cumulative uploads are not resident PSS/RSS. Title frame instrumentation uses the same authored virtual-stage transform on both versions.',
                                'immutableStageNetwork': metadata['network'],
                                'candidateSourceFileSHA256': {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in files},
                                'immutableMobile31Startup': baseline, 'candidateSourceStartupAgainstMobile31Assets': candidate,
                                'immutableMobile31Title180Frames': baseline_title, 'candidateSourceTitle180Frames': candidate_title}, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    if '--profile' in sys.argv:
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument('--profile', type=Path, required=True)
        parser.add_argument('--baseline', type=Path, required=True, help='Explicit immutable version31 mobile stage')
        args = parser.parse_args()
        write_profile(args.profile, args.baseline)
    else:
        unittest.main()
