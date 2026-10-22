"""Actual Lua51 guest settings adapter, device stores and input boundaries."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class GuestSettingsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Players=require('game.coop_players'); Prefs=require('game.local_preferences')
            B=require('game.control_bindings'); Layout=require('game.control_layout'); Access=require('game.accessibility')
            fs,files=F.filesystem(); writes={}; oldWrite=fs.write
            fs.write=function(path,bytes) assert(not path:match('slot') and not path:match('save')); writes[#writes+1]=path; return oldWrite(path,bytes) end
            store=Prefs.new(fs); bindings=B.new(fs); data=F.campaign(); assert(F.enroll(data))
            data.audio.station='vibes'; data.audio.musicVolume=.99; data.accessibility.textSize=3
            before=assert(Schema.copy(data)); store:bind(data,function() return 'client' end)
            controls={}; shapes={}; texts={}; neutral=0; commandCalls=0; layoutApplies=0
            love={filesystem=fs,keyboard={isDown=function(key) return controls[key]==true end},
                joystick={getJoysticks=function() return {} end},graphics={
                getDimensions=function() return 960,720 end,
                push=function() end,pop=function() end,origin=function() end,translate=function() end,scale=function() end,
                clear=function() end,setFont=function() end,setColor=function() end,setLineWidth=function() end,
                rectangle=function(kind,x,y,w,h) shapes[#shapes+1]={kind=kind,x=x,y=y,w=w,h=h} end}}
            package.loaded['game.typography']={font=function() return {} end,drawText=function(_,text) texts[#texts+1]=text end}
            mobile={enabled=true,layout=function() return Layout.normalize() end,
                setLayout=function(self,value) self.applied=Layout.normalize(value); layoutApplies=layoutApplies+1 end,
                setOpacity=function(self,value) self.opacity=value end}
            runtime={state='game',scene='train',saveData=Players.forActor(data,'companion')}
            controller={menuOpen=false,network={submitCommand=function() commandCalls=commandCalls+1;error('settings attempted gameplay command') end}}
            view={ready=true,focused=true,epoch=1,runtime=runtime,mobile=mobile,controller=controller,
                neutralize=function() neutral=neutral+1 end}
            function controller:open() self.menuOpen=true;view:neutralize() end
            local engineAudio={new=function() return {
                installGunPools=function() end,resetMusic=function() end,
                previousTrack=function(_,value) seenAudio=value;return true end,
                nextTrack=function(_,value) seenAudio=value;return true end,
                togglePause=function(_,value) seenAudio=value;value.musicPaused=not value.musicPaused;return true end,
                toggleMute=function(_,value) seenAudio=value;value.musicMuted=not value.musicMuted;return true end,
                update=function() end,shutdown=function() end} end}
            audio=require('game.audio_runtime').new({runtime={state='slots'},ui={localPreferences=store},
                catalog={},audio=engineAudio,audioCatalog={}});audio.initialize()
            Settings=require('game.coop_guest_settings')
            s=Settings.new(view,{preferences=store,bindings=bindings,filesystem=fs,audio=audio})
            function unchanged()
                assert(commandCalls==0 and Schema.validate(data))
                local function eq(a,b)
                    if type(a)~=type(b) then return false end
                    if type(a)~='table' then return a==b end
                    for k,v in pairs(a) do if not eq(v,b[k]) then return false end end
                    for k,v in pairs(b) do if not eq(v,a[k]) then return false end end
                    return true
                end
                assert(eq(data,before),'settings mutated host campaign')
            end
            function activate(id)
                s:draw();for _,t in ipairs(s:targets()) do if t.id==id then assert(t.enabled);s:point(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2);return end end
                error('control missing '..id)
            end
        ''')

    def test_graphics_options_persist_locally_without_commands(self):
        self.lua.execute('''
            s:open();activate('graphics');activate('battle-distance+');activate('battle-distance+')
            assert(Prefs.new(fs).values.graphics.renderDistance==20)
            activate('battle-distance-');assert(Prefs.new(fs).values.graphics.renderDistance==14)
            activate('battle-distance-auto');assert(Prefs.new(fs).values.graphics.renderDistance==0)
            s:close();unchanged()
        ''')

    def test_open_close_keeps_local_play_private_pause_and_neutralizes_without_commands(self):
        self.lua.execute('''
            assert(s:open() and controller.menuOpen and s:isOpen() and neutral>=2)
            s:close();assert(not s:isOpen() and controller.menuOpen and neutral>=3)
            view.ready=false;assert(not s:open());unchanged()
        ''')

    def test_audio_real_runtime_uses_own_device_settings_and_follows_current_shared_radio(self):
        self.lua.execute('''
            s:open();assert(s:values().audio.musicVolume==.1)
            s:audio('musicVolume',.15);s:audio('sfxVolume',-.1);s:audio('rainVolume',.15)
            s:audio('station','8bit');s:audio('rainEnabled');s:audio('togglePause');s:audio('toggleMute')
            assert(seenAudio==Prefs.audio(runtime.saveData) and seenAudio.musicMuted and seenAudio.musicPaused)
            assert(math.abs(Prefs.new(fs).values.audio.musicVolume-.25)<1e-9 and math.abs(Prefs.new(fs).values.audio.sfxVolume-.45)<1e-9)
            assert(s:values().audio.station=='8bit');s:audio('follow');assert(s:values().audio.station=='vibes')
            assert(not Prefs.hasOverride(data));unchanged()
        ''')

    def test_accessibility_changes_and_roundtrip_do_not_import_or_write_host_values(self):
        self.lua.execute('''
            s:open();assert(Access.ensure(runtime.saveData).textSize==1)
            s:accessibility('textSize');for _,id in ipairs({'highContrast','reducedMotion','controlHints','touchFeedback','largeTouchTargets'}) do s:accessibility(id) end
            local restored=Prefs.new(fs);restored:bind({},function() return 'client' end)
            assert(restored.values.accessibility.textSize==2 and restored.values.accessibility.highContrast)
            assert(Access.ensure(runtime.saveData).reducedMotion);unchanged()
        ''')

    def test_preference_write_failure_remains_device_only_and_close_retries(self):
        self.lua.execute('''
            s:open();local write=fs.write;fs.write=function(path,bytes) if path==Prefs.PATH then return false end;return write(path,bytes) end
            assert(not s:audio('sfxVolume',.1) and s.preferencesDirty and s.notice)
            fs.write=write;s:close();assert(not s.preferencesDirty and Prefs.new(fs).values.audio.sfxVolume==.65);unchanged()
        ''')

    def test_aim_controls_are_touch_sized_keyboard_reachable_and_persist_without_host_changes(self):
        self.lua.execute('''
            s:open(); activate('accessibility'); activate('aimSensitivity+'); activate('aimAssist-')
            assert(Access.aimSettings(runtime.saveData).aimSensitivity==1.1)
            assert(Access.aimSettings(runtime.saveData).aimAssist==.3)
            s:draw(); s.ui.keyboardFocusScreen=s:screenKey(); s.ui.keyboardFocusId='aimAssist+'
            s:keypressed('return'); assert(Access.aimSettings(runtime.saveData).aimAssist==.35)
            local rects={}
            for _,t in ipairs(s:targets()) do
                assert(t.rect.x>=30 and t.rect.y>=20 and t.rect.x+t.rect.w<=930 and t.rect.y+t.rect.h<=700)
                if t.id:match('^aim') then
                    assert(t.rect.w>=44 and t.rect.h>=44); rects[#rects+1]=t.rect
                end
            end
            assert(#rects==4)
            for i=1,6 do activate('aimAssist-') end
            activate('aimAssist-'); assert(Access.aimLabel(runtime.saveData,'aimAssist')=='OFF')
            local restored=Prefs.new(fs)
            assert(restored.values.accessibility.aimAssist==0 and restored.values.accessibility.aimSensitivity==1.1)
            unchanged()
        ''')

    def test_raw_keyboard_capture_and_original_press_token_survive_binding_change(self):
        self.lua.execute('''
            assert(bindings:assign('key','interact','z'));assert(s:translateGameplayKey('z')=='e')
            assert(bindings:assign('key','interact','k'));assert(s:translateGameplayKey('z',true)=='e')
            local token,known=s:translateGameplayKey('e');assert(token==nil and known)
            s:open();s:beginCapture('key','inventory');assert(s:keypressed('z'))
            assert(bindings.keyboard.inventory=='z' and not bindings:isCapturing() and B.new(fs).keyboard.inventory=='z')
            assert(s:translateGameplayKey('z')=='i');s:close();assert(next(s.pressedKeys)==nil);unchanged()
        ''')

    def test_keyboard_capture_cancel_modifier_conflict_and_readback_failure(self):
        self.lua.execute('''
            s:open();s:beginCapture('key','inventory');s:keypressed('lctrl');assert(bindings:isCapturing())
            s:keypressed('e');assert(bindings:isCapturing() and bindings.keyboard.inventory=='i')
            s:keypressed('escape');assert(not bindings:isCapturing() and s:isOpen())
            local read=fs.read;fs.read=function(path) if path==B.PATH then return '' end;return read(path) end
            s:beginCapture('key','inventory');s:keypressed('z');assert(s.bindingsDirty and s.notice)
            fs.read=read;s:close();assert(not s.bindingsDirty and B.new(fs).keyboard.inventory=='z',tostring(s.bindingsDirty)..' '..tostring(B.new(fs).keyboard.inventory));unchanged()
        ''')

    def test_raw_controller_button_axis_capture_and_context_scoped_gameplay_translation(self):
        self.lua.execute('''
            s:open();s:bindingChange('clear','button','radio');s:beginCapture('button','interact');s:gamepadpressed('rightstick')
            assert(bindings.buttons.interact=='rightstick' and B.new(fs).buttons.interact=='rightstick')
            s:beginCapture('axis','move_x');s:gamepadaxis('rightx',.2);assert(bindings:isCapturing())
            s:gamepadaxis('rightx',.9);assert(not bindings:isCapturing() and B.new(fs).axes.move_x=='rightx')
            assert(s:translateGameplayButton('rightstick','game')=='e')
            assert(s:translateGameplayButton('rightstick','menu',true)=='e')
            assert(s:translateGameplayButton('rightshoulder','battle')=='g')
            s:close();unchanged()
        ''')

    def test_device_binding_clear_reset_and_live_movement_keyboard_query(self):
        self.lua.execute('''
            s:open();s:bindingChange('clear','key','interact');assert(bindings.keyboard.interact==nil and B.new(fs).keyboard.interact==nil)
            s:bindingChange('reset','key');assert(bindings.keyboard.interact=='e')
            assert(bindings:assign('key','move_up','z'));bindings:installKeyboardQuery();controls.z=true
            assert(love.keyboard.isDown('w'));controls.z=nil;controls.w=true;assert(not love.keyboard.isDown('w'));unchanged()
        ''')

    def test_default_controller_up_load_poll_and_persist_use_real_love_button_name(self):
        self.lua.execute('''
            assert(bindings.buttons.move_up=='dpup')
            local pressed={dpup=true};local observed={}
            love.joystick.getJoysticks=function() return {{isGamepad=function() return true end,
                getGamepadAxis=function() return 0 end,
                isGamepadDown=function(_,name) observed[name]=true;return pressed[name]==true end}} end
            local x,y=bindings:movement();assert(x==0 and y==-1 and observed.dpup and not observed.dpadup)
            assert(bindings:translateButton('dpup','game')=='w')
            assert(bindings:save());local loaded=B.new(fs);assert(loaded.buttons.move_up=='dpup')
            x,y=loaded:movement();assert(x==0 and y==-1)
            pressed.dpup=nil;assert(select(2,loaded:movement())==0)
            unchanged()
        ''')

    def test_legacy_typo_migrates_but_explicit_unbound_and_custom_up_assignments_survive(self):
        self.lua.execute('''
            files[B.PATH]='button move_up dpadup';local loaded=B.new(fs)
            assert(loaded.buttons.move_up=='dpup' and loaded:save())
            assert(files[B.PATH]:find('button move_up dpup',1,true) and B.new(fs).buttons.move_up=='dpup')
            files[B.PATH]='button move_up none';assert(B.new(fs).buttons.move_up==nil)
            files[B.PATH]='button move_up leftshoulder';assert(B.new(fs).buttons.move_up=='leftshoulder')
            files[B.PATH]='button move_right dpadup';assert(B.new(fs).buttons.move_right==nil)
            unchanged()
        ''')

    def test_settings_menu_remapped_keyboard_and_controller_tokens_are_translated_once(self):
        self.lua.execute('''
            s:open();s:draw();assert(bindings:assign('key','confirm','z'))
            s.ui.keyboardFocusScreen=s:screenKey();s.ui.keyboardFocusId='sfxVolume+'
            local volume=s:values().audio.sfxVolume;s:keypressed('return');assert(s:values().audio.sfxVolume==volume)
            s:keypressed('z');assert(s:values().audio.sfxVolume>volume)
            volume=s:values().audio.sfxVolume;s:gamepadpressed('a');assert(s:values().audio.sfxVolume>volume)
            unchanged()
        ''')

    def test_touch_corrupt_readback_does_not_apply_and_focus_does_not_resume_held_input(self):
        self.lua.execute('''
            s:open();s.layout=Layout.normalize();s.layout.opacity=.8
            local read=fs.read;fs.read=function(path) if path=='control-layout.txt' then return 'joystick .9 .9' end;return read(path) end
            assert(not s:saveTouch() and s.layoutDirty and layoutApplies==0)
            fs.read=read;assert(s:saveTouch() and layoutApplies==1)
            s:beginCapture('button','interact');s:focus(false)
            assert(not bindings:isCapturing() and controller.menuOpen and s:isOpen());unchanged()
        ''')

    def test_device_io_exceptions_remain_recoverable_without_campaign_writes(self):
        self.lua.execute('''
            s:open();local write=fs.write;fs.write=function() error('device write unavailable') end
            s:beginCapture('key','inventory');s:keypressed('z');assert(s.bindingsDirty)
            s:bindingChange('clear','button','interact');assert(s.bindingsDirty)
            assert(not s:audio('musicVolume',.1) and s.preferencesDirty)
            fs.write=write;s.layout=Layout.normalize();s.layout.opacity=.8
            local read=fs.read;fs.read=function() error('device read unavailable') end
            assert(not s:saveTouch() and s.layoutDirty and layoutApplies==0)
            fs.read=read;s:close();assert(not s.bindingsDirty and not s.preferencesDirty and not s.layoutDirty)
            assert(B.new(fs).keyboard.inventory=='z' and B.new(fs).buttons.interact==nil);unchanged()
        ''')

    def test_real_draw_controls_drive_audio_accessibility_and_capture_on_each_page(self):
        self.lua.execute('''
            s:open();activate('sfxVolume+');assert(s:values().audio.sfxVolume>.55)
            activate('accessibility');activate('highContrast');assert(Access.ensure(runtime.saveData).highContrast)
            activate('controls');activate('bind-move_up');s:keypressed('z');assert(bindings.keyboard.move_up=='z')
            activate('device-controller');activate('axes');activate('bind-move_x');s:gamepadaxis('rightx',.9)
            assert(bindings.axes.move_x=='rightx' and #shapes>20 and #texts>20)
            activate('close');assert(not s:isOpen() and controller.menuOpen);unchanged()
        ''')

    def test_touch_layout_own_finger_persists_real_layout_and_applies_only_after_checked_write(self):
        self.lua.execute('''
            s:open();s.page='controls';s.device='touch';s:draw();local p=s:touchLayout().joystick
            local x,y=70+p.x*820,230+p.y*300
            s:touchpressed('own',x,y);s:touchpressed('other',800,450)
            s:touchmoved('other',800,450);assert(s:touchLayout().joystick.x==p.x)
            s:touchmoved('own',70+.4*820,230+.5*300);s:touchreleased('other');assert(layoutApplies==0)
            s:touchreleased('own');local loaded=assert(Layout.load(fs));assert(loaded.joystick.x==.4 and loaded.joystick.y==.5)
            assert(mobile.applied.joystick.x==.4 and layoutApplies==1);unchanged()
        ''')

    def test_touch_write_failure_bounded_positions_opacity_and_keyboard_controls(self):
        self.lua.execute('''
            s:open();s.page='controls';s.device='touch';s.selectedControl='primary'
            local write=fs.write;fs.write=function(path,bytes) if path=='control-layout.txt' then return false end;return write(path,bytes) end
            assert(not s:touchChange('primary',10,-10) and s.layoutDirty and layoutApplies==0)
            assert(s.layout.primary.x==.9 and s.layout.primary.y==.08)
            fs.write=write;assert(s:saveTouch());assert(mobile.applied.primary.x==.9)
            s:touchChange(nil,'opacity',-20);assert(Layout.load(fs).opacity==Layout.MIN_OPACITY)
            activate('reset-touch');assert(Layout.load(fs).primary.x==.78 and mobile.opacity==.8);unchanged()
        ''')

    def test_projection_refresh_focus_loss_and_release_cancel_capture_and_drag_without_resume(self):
        self.lua.execute('''
            s:open();s:beginCapture('key','inventory');view.focused=false;s:update()
            assert(not bindings:isCapturing() and controller.menuOpen and s:isOpen())
            local fresh=assert(Schema.copy(data));fresh.audio.station='chill';store:bind(fresh,function() return 'client' end)
            runtime.saveData=Players.forActor(fresh,'companion');assert(s:values().audio.station=='chill')
            s:audio('musicVolume',.1);assert(Prefs.new(fs).values.audio.musicVolume==.2)
            view.focused=true;view.epoch=2;s:update();assert(next(s.pressedKeys)==nil)
            s:release();assert(not s:isOpen() and controller.menuOpen);unchanged()
        ''')


if __name__ == '__main__':
    unittest.main()
