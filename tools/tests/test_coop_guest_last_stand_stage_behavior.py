"""Guest passive story stages use checked visuals and reliable saved outcomes."""
import unittest
import test_coop_last_stand_movement_behavior as movement


class GuestLastStandStageTests(unittest.TestCase):
    setUp = movement.LastStandGuestMotionTests.setUp
    farm = movement.LastStandGuestMotionTests.farm

    def passive(self, mode='escort'):
        self.farm()
        self.lua.globals().mode = mode
        self.lua.execute('''
            checked={mode=mode,clock=4,paused=false,offerPage=2,
                hostPose={x=350,y=285,facing=-1},scout={x=600,y=400,walkDistance=16,arrival=1}}
            controller.lastStandStage={get=function() return checked end}
            assert(Life.move(data.lastStand,mode,mode=='offer' and 'waiting' or mode)); Life.ensure(data)
            controller.replica.revision=controller.replica.revision+1; controller.motionFrame=modalFrame(2,4)
            assert(view:update(.05)); parent=view.lastStand
            before=require('game.net.codec').encode(data,{maxBytes=32768,maxDepth=16,maxEntries=2048})
        ''')

    def test_clock_is_checked_and_stale_visual_freezes_without_story_progress(self):
        self.passive()
        self.lua.execute('''
            assert(parent:passiveModel().clock==4 and not parent:passiveModel().paused)
            checked.clock=6; parent:update(.1); assert(parent:passiveModel().clock==6)
            checked=nil; parent:update(20)
            local m=parent:passiveModel(); assert(m.stale and m.paused and m.clock==6)
            assert(view.runtime.saveData.lastStand.lifecycle.mode=='escort')
            assert(require('game.net.codec').encode(data,{maxBytes=32768,maxDepth=16,maxEntries=2048})==before)
        ''')

    def test_private_pause_menu_and_foreign_mode_do_not_advance_picture(self):
        self.passive()
        self.lua.execute('''
            parent:keypressed('p'); checked.clock=8; parent:update(.1)
            assert(parent:passiveModel().clock==4 and parent:passiveModel().paused)
            parent:keypressed('p'); controller.menuOpen=true; parent:update(.1); assert(parent:passiveModel().clock==4)
            controller.menuOpen=false; checked.mode='returning'; parent:update(.1); assert(parent:passiveModel().clock==4)
            checked.mode='escort'; checked.paused=true; parent:update(.1)
            assert(parent:passiveModel().clock==8 and parent:passiveModel().paused)
        ''')

    def test_lifecycle_change_clears_previous_stage_and_stale_pose(self):
        self.passive()
        self.lua.execute('''
            checked=nil; assert(Life.move(data.lastStand,'returning')); Life.ensure(data)
            controller.replica.revision=controller.replica.revision+1; controller.motionFrame=modalFrame(3,5)
            assert(view:update(.05)); local m=parent:passiveModel()
            assert(m.mode=='returning' and m.clock==0 and m.stale and not m.scout)
        ''')

    def test_offer_only_reads_current_host_page_and_returns_detached_model(self):
        self.passive('offer')
        self.lua.execute('''
            local m=parent:passiveModel(); assert(m.page.page==2 and m.page.count==5)
            assert(m.page.text=='Wounded defenders: backyard. Firing positions: two front windows.')
            m.scout.x=1; m.host.x=1; m.page.text='changed'
            local next=parent:passiveModel(); assert(next.scout.x==600 and next.host.x==350 and next.page.text~='changed')
            parent:keypressed('q'); parent:keypressed('f'); parent:keypressed('return')
            assert(parent:passiveModel().page.page==2 and not parent.pending)
        ''')

    def test_aftermath_anchor_is_render_only_and_rewards_require_durable_projection(self):
        self.passive('aftermath')
        self.lua.execute('''
            local x,y=view.runtime.player.x,view.runtime.player.y
            local m=parent:passiveModel(); assert(m.guest.x==505 and m.guest.y==590 and m.host.x==350 and not m.summary)
            view.runtime.saveData.lastStand.rewardClaimed=true; view.runtime.saveData.lastStand.rewardScrap=36
            m=parent:passiveModel(); assert(m.summary.scrap==36 and m.summary.goodwill==3 and m.summary.food==2)
            assert(view.runtime.player.x==x and view.runtime.player.y==y and not data.lastStand.rewardClaimed)
            assert(not parent:action() and not parent:inputAllowed())
        ''')

    def test_story_inputs_do_not_submit_commands_for_any_passive_mode(self):
        self.passive()
        self.lua.execute('''
            local submitted=0; controller.network.submitCommand=function() submitted=submitted+1 end
            for _,mode in ipairs({'offer','escort','aftermath','returning'}) do
                local q=view.runtime.saveData.lastStand; assert(Life.move(q,mode,mode=='offer' and 'waiting' or mode))
                parent:update(.05)
                for _,key in ipairs({'y','n','q','f','e','return','space','t','backspace'}) do assert(parent:keypressed(key)) end
                for _,button in ipairs({'a','x','b'}) do assert(parent:gamepadpressed(button)) end
                parent:pointer(700,602,1,false)
                assert(not parent:action() and not parent:inputAllowed() and not parent.pending)
            end
            assert(submitted==0); parent:keypressed('p'); assert(parent.paused)
            parent:keypressed('escape'); assert(controller.menuOpen)
        ''')

    def test_transition_draw_uses_two_personal_visuals_and_checked_clock(self):
        self.passive('returning')
        self.lua.execute('''
            local drawn,texts=nil,{}
            love={graphics={setColor=function() end,rectangle=function() end}}
            require('game.typography').drawText=function(_,value) texts[#texts+1]=value end
            require('game.last_stand_scene').drawGuestTransition=function(state,w,h,returning,host,guest)
                drawn=state; assert(w==960 and h==720 and returning and host.character and guest.character)
            end
            parent:draw(); assert(drawn.clock==4 and drawn.quest==view.runtime.saveData.lastStand)
            for _,text in ipairs(texts) do assert(not text:find('Skip journey',1,true)) end
        ''')

    def test_offer_draw_uses_passive_art_and_exact_neutral_page_without_buttons(self):
        self.passive('offer')
        self.lua.execute('''
            local texts,drawn={},false
            love={graphics={setColor=function() end,rectangle=function() end}}
            require('game.typography').drawText=function(_,value) texts[#texts+1]=value end
            require('game.last_stand_scene').drawGuestOffer=function(state,w,h)
                drawn=true; assert(state.scout.x==600 and state.clock==4 and w==960 and h==720)
            end
            parent:draw(); assert(drawn)
            local found=false
            for _,text in ipairs(texts) do
                if text=='Wounded defenders: backyard. Firing positions: two front windows.' then found=true end
                assert(not text:find('ACCEPT',1,true) and not text:find('NOT NOW',1,true) and not text:find('[E]',1,true))
            end
            assert(found and not parent.pending)
        ''')

    def test_aftermath_draw_uses_render_anchor_and_never_displays_unsaved_reward(self):
        self.passive('aftermath')
        self.lua.execute('''
            local texts={}; local x,y=view.runtime.player.x,view.runtime.player.y
            love={graphics={setColor=function() end,rectangle=function() end}}
            require('game.typography').drawText=function(_,value) texts[#texts+1]=value end
            require('game.last_stand_scene').draw=function(scene,w,h,visual,loan,touch,pause,others,hide)
                assert(scene.mode=='interior' and scene.player.x==505 and scene.player.y==590)
                assert(others[1].player.x==350 and others[1].player.y==285 and hide and not loan and not touch and not pause)
            end
            parent:draw(); for _,text in ipairs(texts) do assert(not text:find('Reward:',1,true)) end
            assert(view.runtime.player.x==x and view.runtime.player.y==y)
            view.runtime.saveData.lastStand.rewardClaimed=true; view.runtime.saveData.lastStand.rewardScrap=28
            texts={}; parent:draw(); local confirmed=false
            for _,text in ipairs(texts) do if text:find('Reward: 28 scrap, 3 goodwill, and 2 food.',1,true) then confirmed=true end end
            assert(confirmed and not parent:action())
        ''')


if __name__ == '__main__':
    unittest.main()
