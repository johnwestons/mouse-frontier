"""Passive stage rendering reads checked Source state without story controls."""
import unittest
import test_coop_last_stand_source_behavior as source


class LastStandStageSourceTests(unittest.TestCase):
    def setUp(self):
        source.LastStandSourceTests.setUp(self)
        self.lua.execute('''
            QuestModule=require('game.last_stand_quest'); Scene=require('game.last_stand_scene')
            function stage(mode)
                assert(Life.move(quest,mode,mode=='offer' and 'waiting' or mode)); Life.ensure(data)
                runtime.lastStand={mode=mode,capture=true,quest=quest,clock=1.5,offerPage=3,
                    scout={x=400,y=500},walkDistance=24,arrival=.6}
                if mode=='aftermath' then
                    quest.rewardClaimed=true; quest.rewardScrap=36
                    runtime.lastStand.scene=Scene.new('interior',quest)
                    Life.bind(runtime.lastStand.scene.player,data,'host')
                end
            end
            function renderSetup()
                labels={}; travelers={}; stacks=0
                love.graphics={push=function() stacks=stacks+1 end,pop=function() stacks=stacks-1 end,
                    setColor=function() end,ellipse=function() end,rectangle=function() end,newImage=function() return nil end}
                require('game.typography').drawText=function(_,value) labels[#labels+1]=value end
                require('game.window_scene').drawBackground=function(value) background=value end
                require('game.character_animation').draw=function(_,file,action,x,y,w,h,direction,clock,frameClock,motion)
                    travelers[#travelers+1]={file=file,action=action,x=x,y=y,direction=direction,clock=clock,distance=motion.animationDistance}
                    return true
                end
                hostVisual={character='cook-mouse.png',animations={}}; guestVisual={character='scout-frog.png',animations={}}
            end
        ''')

    def test_checked_source_stage_is_detached_and_contains_no_text_or_progression_callbacks(self):
        self.lua.execute('''
            for _,mode in ipairs({'offer','escort','aftermath','returning'}) do
                stage(mode); local before=Schema.copy(data); local state=runtime.lastStand
                local value=assert(Source:stageState())
                assert(value.questId==quest.lifecycle.entityId and value.lifeRevision==quest.lifecycle.revision)
                assert(value.mode==mode and value.clock==1.5 and not value.paused)
                assert(value.scout.x==400 and value.scout.walkDistance==24 and value.scout.arrival==.6)
                assert(not value.quest and not value.text and not value.accept and not value.returning)
                value.scout.x=0
                if mode=='aftermath' then
                    assert(value.hostPose); value.hostPose.x=0; assert(Source:stageState().hostPose.x~=0)
                else assert(value.hostPose==nil) end
                assert(state.scout.x==400)
                local Codec=require('game.net.codec'); assert(Codec.encode(data)==Codec.encode(before))
                assert((mode=='offer' and value.offerPage==3) or (mode~='offer' and value.offerPage==nil))
            end
        ''')

    def test_stale_or_inactive_source_never_publishes_cinematic_stage(self):
        self.lua.execute('''
            stage('escort'); runtime.lastStand.mode='returning'; assert(Source:stageState()==nil)
            runtime.lastStand.mode='escort'; runtime.lastStand.capture=false; assert(Source:stageState()==nil)
            runtime.lastStand.capture=true; runtime.state='slots'; assert(Source:stageState()==nil)
            runtime.state='game'; runtime.session.networkMode='client'; assert(Source:stageState()==nil)
            runtime.session.networkMode='host'; runtime.scene='train'; assert(Source:stageState()==nil)
            runtime.scene='stop'; runtime.lastStand.quest=Schema.copy(data).lastStand; assert(Source:stageState()==nil)
        ''')

    def test_host_private_pause_and_save_barrier_pause_stage_clock(self):
        self.lua.execute('''
            stage('escort'); runtime.lastStand.paused=true; local clock=runtime.lastStand.clock
            sourceTick(.2); assert(Source:stageState().paused and Source:stageState().clock==clock)
            runtime.lastStand.paused=false; privatePaused=true; sourceTick(.2)
            assert(Source:stageState().paused and Source:stageState().clock==clock)
            privatePaused=false; runtime.session.checkpointPending=true
            assert(Source:stageState().paused); sourceTick(.2); assert(Source:stageState().clock==clock)
            runtime.session.checkpointPending=false; sourceTick(.2)
            assert(not Source:stageState().paused and Source:stageState().clock==clock+.2)
        ''')

    def test_offer_objective_accessors_preserve_words_without_exposing_choice_actions(self):
        self.lua.execute('''
            local page=assert(QuestModule.offerPage(1))
            assert(page.title=='A LIGHT IN THE WINDOWS' and page.count==5 and page.page==1)
            assert(page.text=='Objective: defend the farmhouse from the railway gang at the relay depot.')
            assert(not page.accept and not page.decline and not page.next)
            page.text='changed'; assert(QuestModule.offerPage(1).text~='changed')
            assert(not QuestModule.offerPage(0) and not QuestModule.offerPage(1.5) and not QuestModule.offerPage(6))
            stage('offer'); runtime.lastStand.offerPage=6; assert(Source:stageState()==nil)
        ''')

    def test_aftermath_stats_require_confirmed_reward_and_never_invent_pending_benefits(self):
        self.lua.execute('''
            assert(not QuestModule.aftermathSummary({rewardClaimed=false,rewardScrap=36}))
            assert(not QuestModule.aftermathSummary({rewardClaimed=true}))
            assert(not QuestModule.aftermathSummary({rewardClaimed=true,rewardScrap=999}))
            local summary=assert(QuestModule.aftermathSummary({rewardClaimed=true,rewardScrap=36}))
            assert(summary.scrap==36 and summary.goodwill==3 and summary.food==2)
            assert(summary.text=='The gang has withdrawn. The defenders lower their weapons one by one. Reward: 36 scrap, 3 goodwill, and 2 food.')
            assert(not summary.returnAction and not summary.stayAction)
        ''')

    def test_guest_escort_draws_authored_three_travelers_and_existing_narration_without_skip(self):
        self.lua.execute('''
            renderSetup(); local state={quest=quest,clock=4,reducedMotion=false}; local before=Schema.copy(data)
            Scene.drawGuestTransition(state,960,720,false,hostVisual,guestVisual)
            assert(#travelers==3 and travelers[1].file=='otter-scout.png' and travelers[2].file=='cook-mouse.png'
                and travelers[3].file=='scout-frog.png')
            assert(travelers[1].direction==1 and travelers[3].clock==4 and stacks==0)
            assert(labels[1]=='You follow the scout beyond the town limits.' and labels[2]=='Distant rifle cracks roll over the fields.' and #labels==2)
            local Codec=require('game.net.codec'); assert(Codec.encode(data)==Codec.encode(before))
        ''')

    def test_guest_returning_is_passive_reduced_motion_and_source_skip_still_exists(self):
        self.lua.execute('''
            renderSetup(); local state={quest=quest,clock=4,reducedMotion=true}
            Scene.drawGuestTransition(state,960,720,true,hostVisual,guestVisual)
            assert(#travelers==3 and travelers[1].direction==-1 and travelers[3].action=='idle' and travelers[3].distance==0)
            assert(labels[1]=='The relay falls quiet behind you.' and labels[2]=='The survivors can finally leave the windows.' and #labels==2)
            labels={}; travelers={}; Scene.drawTransition(state,960,720,true,hostVisual)
            assert(#travelers==2 and labels[3]=='[SPACE] Skip journey' and stacks==0)
        ''')

    def test_guest_offer_scout_keeps_idle_arrival_without_host_interaction_prompt(self):
        self.lua.execute('''
            renderSetup(); local state={quest=quest,scout={x=400,y=500},arrival=.6,walkDistance=24}
            Scene.drawGuestApproach(state); assert(#labels==0 and state.arrival==.6 and state.walkDistance==24 and stacks==0)
            Scene.drawApproach(state); assert(#labels==1 and labels[1]=='[E] Farmhouse defense' and stacks==0)
        ''')

    def test_guest_offer_draws_existing_landscape_without_ordinary_dialogue_or_actions(self):
        self.lua.execute('''
            renderSetup(); local state={quest=quest,clock=1.5,scout={x=400,y=500},arrival=.6,walkDistance=24}
            Scene.drawGuestOffer(state,960,720)
            assert(background.quest==quest and background.clock==1.5 and #labels==0 and stacks==0)
            assert(state.arrival==.6 and state.walkDistance==24)
        ''')

    def test_paused_guest_transition_keeps_position_and_changes_only_gait_to_idle(self):
        self.lua.execute('''
            renderSetup(); local state={quest=quest,clock=4,reducedMotion=false}
            Scene.drawGuestTransition(state,960,720,false,hostVisual,guestVisual)
            local x=travelers[3].x; assert(travelers[3].action=='walk')
            state.paused=true; travelers={}; Scene.drawGuestTransition(state,960,720,false,hostVisual,guestVisual)
            assert(travelers[3].action=='idle' and travelers[3].x==x and travelers[3].clock==4)
        ''')

    def test_ordinary_world_pose_outside_stage_viewport_is_omitted_without_clamping(self):
        self.lua.execute('''
            local Wire=require('game.net.last_stand_stage'); local Protocol=require('game.net.protocol')
            runtime.player.x=5000; runtime.player.y=1500
            for _,mode in ipairs({'offer','escort','returning','aftermath'}) do
                stage(mode); runtime.lastStand.scout.x=5020; runtime.lastStand.scout.y=1500
                local value=assert(Source:stageState())
                assert(value.scout.x==5020 and value.scout.y==1500)
                assert(runtime.player.x==5000 and runtime.player.y==1500)
                if mode=='aftermath' then assert(value.hostPose.x==480 and value.hostPose.y==590)
                else assert(value.hostPose==nil) end
                local packed=Wire.pack(value); packed.sessionId='stage-world-pose'; packed.sceneEpoch=data.coop.sceneEpoch; packed.serial=1
                assert(Wire.snapshot(Protocol.message('last_stand_stage',packed)))
            end
        ''')
