"""Actual panel/typography draws retain readable text and correct input hints."""
import unittest
import test_coop_guest_inventory_behavior as inventory
import test_coop_guest_view_behavior as guest


DRAW_SETUP = '''
    printed={}; currentColor={0,0,0,1}
    local font={getWidth=function(_,text) return #text*8 end,
        getHeight=function() return 20 end,getLineHeight=function() return 1 end,
        getWrap=function(_,text,width) return math.min(#text*8,width),{text} end}
    love=love or {};love.graphics={
        setColor=function(r,g,b,a) currentColor=type(r)=='table' and r or {r,g,b,a or 1} end,
        rectangle=function() end,getFont=function() return font end,setFont=function() end,
        printf=function(text) printed[#printed+1]={text=text,color=currentColor} end,
        print=function(text) printed[#printed+1]={text=text,color=currentColor} end}
    function textContaining(value)
        for _,line in ipairs(printed) do if line.text:find(value,1,true) then return line.text end end
    end
'''


class PoseVisualTests(unittest.TestCase):
    setUp = guest.GuestViewTests.setUp

    def test_actual_typography_draws_all_pose_choices_and_pending_notice_in_foreground_color(self):
        self.lua.execute(DRAW_SETUP + '''
            view.poses.opened=true;view.poses.notice='Waiting for the host...'
            view.poses:draw()
            assert(#printed==7 and printed[1].text=='CHARACTER POSE')
            for _,value in ipairs({'STAND','SIT','LAY DOWN','USE / ACTION','DONE','Waiting for the host...'}) do
                assert(textContaining(value),'missing pose label '..value)
            end
            for _,line in ipairs(printed) do
                local c=line.color
                assert(c[1]>=.9 and c[2]>=.8 and c[3]>=.7 and c[4]==1,'dark pose text '..line.text)
            end
        ''')


class InventoryHintTests(unittest.TestCase):
    setUp = inventory.GuestInventoryTests.setUp

    def draw(self):
        self.lua.execute(DRAW_SETUP + '''
            bindings=require('game.control_bindings').new(F.filesystem());panel.c.bindings=bindings
            panel.c.colors.cream={1,.93,.78,1};runtime.inventoryOpen=true
            panel.presenter.drawInventory=function() end;panel.frame=function() end
            panel.button=function(_,label,x,y,w,h) return {x=x,y=y,w=w,h=h} end
        ''')

    def test_displayed_close_keys_match_actual_remapped_panel_input_and_old_keys_are_disabled(self):
        self.draw()
        self.lua.execute('''
            assert(bindings:assign('key','inventory','z'));assert(bindings:assign('key','cancel','f10'))
            panel:draw();local hint=assert(textContaining(': close'))
            assert(hint:find('Z / F10: close',1,true) and not hint:find('I / Escape',1,true))
            local token,known=bindings:translateKey('i');assert(not token and known)
            assert(runtime.inventoryOpen);panel:keypressed(bindings:translateKey('z'));assert(not runtime.inventoryOpen)
            assert(panel:toggle());panel:keypressed(bindings:translateKey('f10'));assert(not runtime.inventoryOpen)
            assert(#requests==0,'changing a private hint/input wrote campaign commands')
        ''')

    def test_unbound_close_keys_use_visible_button_instruction_and_touch_hides_keyboard_hints(self):
        self.draw()
        self.lua.execute('''
            assert(bindings:clear('key','inventory'));assert(bindings:clear('key','cancel'))
            panel:draw();assert(textContaining('Use CLOSE BACKPACK to close.'))
            assert(not textContaining('UNBOUND') and not textContaining('I / Escape'))
            printed={};view.mobile.enabled=true;panel:draw()
            assert(not textContaining(': close') and not textContaining('Use CLOSE BACKPACK'))
        ''')


if __name__ == '__main__':
    unittest.main()
