"""The animation viewer's dynamic actions remain reachable by pointer and keyboard."""
import os
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class CharacterViewerInputTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            local noop=function()end
            love={graphics={},keyboard={isDown=function()return false end},mouse={getPosition=function()return 0,0 end},
                filesystem={getInfo=function()return nil end}}
            runtime={state='characters',characterPreviewFile='conductor-cat.png',characterPreviewAction='idle',
                characterPreviewDirection='E',characterPreviewPage=1}
            ui={characterPoseActions={},characterMovementActions={},characterDirections={}}
            for index,id in ipairs({'sweep','carry','tend'}) do
                ui.characterPoseActions[index]={id=id,control={x=100*index,y=200,w=90,h=34}}
            end
            ui.characterPosePageCount=2
            ui.characterPosePrev={x=100,y=300,w=40,h=34};ui.characterPoseNext={x=300,y=300,w=40,h=34}
            local ctx=setmetatable({runtime=runtime,ui=ui,
                controlBindings=require('game.control_bindings').new(love.filesystem),
                mobileEnabled=function()return false end,characters={},maintenanceSession={},scenery={},inventory={},
                catalog={},npcRelationships={},merchantTrade={},util=require('game.util'),engineUpgrades={},
                trainUpgradeBalance={},maintenance={},battleRules={},stops={},settlements={},interiorDoors={},firstAid={},
                shootingRange={},screenToGame=function(x,y)return x,y end}, {__index=function()return noop end})
            input=require('game.gameplay_input').new(ctx)
        ''')

    def test_mouse_and_touch_path_select_every_chore_and_turn_pages(self):
        self.lua.execute('''
            for index,id in ipairs({'sweep','carry','tend'}) do
                input.mousepressed(100*index+10,210,1)
                assert(runtime.characterPreviewAction==id)
            end
            input.mousepressed(310,310,1);assert(runtime.characterPreviewPage==2)
            input.mousepressed(310,310,1);assert(runtime.characterPreviewPage==2)
            input.mousepressed(110,310,1);assert(runtime.characterPreviewPage==1)
        ''')

    def test_keyboard_can_activate_dynamic_actions_and_page_controls(self):
        self.lua.execute('''
            for index,id in ipairs({'sweep','carry','tend'}) do
                ui.keyboardFocusScreen='character-profile';ui.keyboardFocusId='character.pose.'..index
                ui.keyboardFocusVisible=true
                input.keypressed('return');assert(runtime.characterPreviewAction==id)
            end
            ui.keyboardFocusId='character.pose.next';input.keypressed('return');assert(runtime.characterPreviewPage==2)
            ui.keyboardFocusId='character.pose.previous';input.keypressed('return');assert(runtime.characterPreviewPage==1)
        ''')


if __name__=='__main__':unittest.main()
