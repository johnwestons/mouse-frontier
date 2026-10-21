"""Device settings stay local through migration, guest play and storage faults."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class LocalPreferencesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures')
            Schema=require('game.save_schema'); Players=require('game.coop_players')
            Prefs=require('game.local_preferences'); Access=require('game.accessibility')
            fs,files=Fixtures.filesystem(); store=Prefs.new(fs); data=Fixtures.campaign()
            mode='offline'
            function attach(value) return store:attach(value or data,function() return mode end) end
        ''')

    def test_touch_aim_preferences_default_clamp_and_roundtrip_only_on_device(self):
        self.lua.execute('''
            local defaults=Access.aimSettings(store.menu)
            assert(defaults.aimAssist==.35 and defaults.aimSensitivity==1)
            defaults.aimAssist=1; assert(Access.aimSettings(store.menu).aimAssist==.35)
            attach(); Access.adjustAim(data,'aimAssist',-.35); Access.adjustAim(data,'aimSensitivity',.4)
            assert(Access.aimLabel(data,'aimAssist')=='OFF' and Access.aimLabel(data,'aimSensitivity')=='1.4x')
            assert(store:save(true)); local restored=Prefs.new(fs)
            restored:attach(data); local aim=Access.aimSettings(data)
            assert(aim.aimAssist==0 and aim.aimSensitivity==1.4 and not data.accessibility and Schema.validate(data))
            Access.adjustAim(data,'aimAssist',10); Access.adjustAim(data,'aimSensitivity',-10)
            assert(Access.aimSettings(data).aimAssist==1 and Access.aimSettings(data).aimSensitivity==.5)
            local access=Access.ensure(data); access.aimAssist=0/0; access.aimSensitivity=math.huge
            assert(Access.aimSettings(data).aimAssist==.35 and Access.aimSettings(data).aimSensitivity==1)
            access.aimAssist=-5; access.aimSensitivity=9
            assert(Access.aimSettings(data).aimAssist==0 and Access.aimSettings(data).aimSensitivity==2)
        ''')

    def test_existing_device_preferences_gain_aim_defaults_without_importing_host_values(self):
        self.lua.execute('''
            local Codec=require('game.net.codec'); local values=store.values
            values.accessibility.aimAssist=nil; values.accessibility.aimSensitivity=nil
            files[Prefs.PATH]=assert(Codec.encode(values)); store=Prefs.new(fs)
            data.accessibility.aimAssist=1; data.accessibility.aimSensitivity=2
            mode='client'; attach()
            assert(Access.aimSettings(data).aimAssist==.35 and Access.aimSettings(data).aimSensitivity==1)
            Access.adjustAim(data,'aimAssist',-.15); Access.adjustAim(data,'aimSensitivity',.2)
            assert(store:save(true)); local loaded=Prefs.new(fs)
            assert(loaded.values.accessibility.aimAssist==.2 and loaded.values.accessibility.aimSensitivity==1.2)
            assert(data.accessibility.aimAssist==1 and data.accessibility.aimSensitivity==2)
        ''')

    def test_host_accessibility_drawn_aim_controls_fit_and_change_saved_preferences(self):
        self.lua.execute('''
            attach(); local noop=function() end; local mobile=true; local rects={}
            love={graphics={setColor=noop},keyboard={isDown=function() return false end}}
            package.loaded['game.typography']={drawText=noop}
            local runtime={saveData=data,optionsPage='accessibility',state='game'}
            local ui={optionsOpen=true,localPreferences=store,menuSettings=store.menu,playSfx=noop}
            local bindings=require('game.control_bindings').new(fs)
            local context={runtime=runtime,ui=ui,width=960,height=720,holdPickupSeconds=1,colors={cream={1,1,1}},
                controlBindings=bindings,util=require('game.util'),mobileEnabled=function() return mobile end,
                getAudioStatus=function() return {available=false} end,
                button=function(label,x,y,w,h)
                    local r={x=x,y=y,w=w,h=h}; rects[#rects+1]=r; return r
                end}
            for _,key in ipairs({'characters','maintenanceSession','scenery','inventory','catalog','npcRelationships',
                'merchantTrade','engineUpgrades','trainUpgradeBalance','maintenance','battleRules','stops','settlements',
                'interiorDoors','firstAid','shootingRange','clouds','lastStand','npcImages','train'}) do context[key]={} end
            setmetatable(context,{__index=function() return noop end})
            local hud=require('game.gameplay_hud').new(context)
            require('game.gameplay_input').new(context)
            local function click(key)
                local r=assert(ui[key]); assert(ui.handleOptionsMousePressed(r.x+r.w/2,r.y+r.h/2))
            end
            for _,touch in ipairs({true,false}) do
                mobile=touch; rects={}; hud.drawOptions()
                for _,r in ipairs(rects) do assert(r.x>=42 and r.y>=26 and r.x+r.w<=918 and r.y+r.h<=694) end
                for _,key in ipairs({'accessAimAssistDown','accessAimAssistUp','accessAimSensitivityDown','accessAimSensitivityUp'}) do
                    assert(ui[key].w>=44 and ui[key].h>=44)
                end
                click('accessAimAssistDown'); click('accessAimSensitivityUp')
            end
            assert(Access.aimSettings(data).aimAssist==.25 and Access.aimSettings(data).aimSensitivity==1.2)
            local loaded=Prefs.new(fs)
            assert(loaded.values.accessibility.aimAssist==.25 and loaded.values.accessibility.aimSensitivity==1.2)
            assert(not data.accessibility and Schema.validate(data))
            runtime.optionsPage='audio'; hud.drawOptions()
            assert(not ui.accessAimAssistDown and not ui.accessAimAssistUp and not ui.accessAimSensitivityDown and not ui.accessAimSensitivityUp)
        ''')

    def test_local_play_options_persist_on_device_without_campaign_or_legacy_import(self):
        self.lua.execute('''
            local defaults=store:localPlay(); assert(defaults.connectionMode=='auto' and not defaults.autoJoin)
            defaults.autoJoin=true; assert(not store:localPlay().autoJoin)
            assert(store:setLocalPlay({connectionMode='usb',autoJoin=true}))
            assert(not store.values.configured and not data.localPlay)
            local restored=Prefs.new(fs); local selected=restored:localPlay()
            assert(selected.connectionMode=='usb' and selected.autoJoin)
            mode='client'; restored:attach(data,function() return mode end)
            assert(restored:localPlay().connectionMode=='usb' and not data.localPlay and Schema.validate(data))
            restored:attach(data,function() return 'offline' end)
            assert(restored:localPlay().autoJoin and restored:localPlay().connectionMode=='usb')
        ''')

    def test_local_play_legacy_defaults_invalid_options_and_checked_write_recovery(self):
        self.lua.execute('''
            local Codec=require('game.net.codec'); local value=store.values
            value.localPlay=nil; files[Prefs.PATH]=assert(Codec.encode(value))
            local legacy=Prefs.new(fs); assert(legacy:localPlay().connectionMode=='auto' and not legacy:localPlay().autoJoin)
            assert(not legacy:setLocalPlay({connectionMode='internet',autoJoin=true}))
            assert(not legacy:setLocalPlay({connectionMode='auto',autoJoin='yes'}))
            assert(not legacy:setLocalPlay({connectionMode='auto',autoJoin=true,credential='secret'}))
            local write=fs.write; fs.write=function(path,bytes) if path==Prefs.PATH then return false end; return write(path,bytes) end
            assert(not legacy:setLocalPlay({connectionMode='wifi',autoJoin=true}) and legacy.lastError)
            local recovered=Prefs.new(fs); assert(recovered:localPlay().connectionMode=='auto')
            files[Prefs.PATH]=nil; recovered=Prefs.new(fs)
            assert(recovered:localPlay().connectionMode=='wifi' and recovered:localPlay().autoJoin)
            fs.write=write; assert(legacy:save() and not legacy.lastError)
            assert(Prefs.new(fs):localPlay().connectionMode=='wifi' and not files[Prefs.PATH..'.tmp'])
        ''')

    def test_own_legacy_settings_import_once_and_campaign_roundtrip_excludes_them(self):
        self.lua.execute('''
            data.audio.musicVolume=.73; data.audio.sfxVolume=.27; data.audio.station='vibes'
            data.accessibility.textSize=3; data.accessibility.reducedMotion=true
            local view=attach()
            assert(view.audio.musicVolume==.73 and Access.textScale(data)==1.30)
            assert(data.coop.preferencesDetached and not data.accessibility and not data.audio.musicVolume)
            assert(data.audio.station=='vibes' and Schema.validate(data))
            love={filesystem=fs}; local Save=require('game.save')
            assert(Save.write(1,data)); local loaded=assert(Save.read(1))
            assert(loaded.coop.preferencesDetached and not loaded.accessibility and not loaded.audio.musicMuted)
            local reloaded=Prefs.new(fs); reloaded:attach(loaded)
            assert(Prefs.audio(loaded).sfxVolume==.27 and Access.ensure(loaded).reducedMotion)
            local other=Fixtures.campaign(); other.audio.musicVolume=.01; other.accessibility.textSize=1
            reloaded:attach(other)
            assert(Prefs.audio(other).musicVolume==.73 and Access.ensure(other).textSize==3)
        ''')

    def test_guest_never_imports_or_mutates_host_preferences(self):
        self.lua.execute('''
            data.audio.musicVolume=.88; data.accessibility.textSize=3
            local before=assert(Schema.copy(data)); mode='client'; local view=attach()
            assert(view.audio.musicVolume==.1 and Access.ensure(data).textSize==1)
            view.audio.musicVolume=.2; Access.toggle(data,'highContrast'); assert(store:save(true))
            assert(data.audio.musicVolume==.88 and data.accessibility.textSize==3)
            assert(not data.accessibility.highContrast and not data.coop.preferencesDetached)
            local own=Fixtures.campaign(); mode='offline'; attach(own)
            assert(Prefs.audio(own).musicVolume==.2 and Access.ensure(own).highContrast)
            assert(data.audio.musicVolume==before.audio.musicVolume)
        ''')

    def test_unloaded_campaigns_and_closed_stores_are_collectable_in_lua51(self):
        self.lua.execute('''
            local view=attach(); Prefs.audio(data).station='vibes'
            local probe=setmetatable({data,store,view},{__mode='v'})
            data=nil; collectgarbage('collect'); collectgarbage('collect')
            assert(not probe[1],'a settings view retained its unloaded campaign')
            assert(view.audio.station=='vibes' and Prefs.followRadio(view))
            assert(store.menu.audio.station=='chill')
            view=nil; store=nil; collectgarbage('collect'); collectgarbage('collect')
            assert(not probe[2] and not probe[3],'local settings retained their closed store')
        ''')

    def test_actor_views_share_device_settings_without_changing_simulation_speed(self):
        self.lua.execute('''
            assert(Fixtures.enroll(data)); attach()
            local guest=Players.forActor(data,'companion')
            Access.toggle(guest,'reducedMotion'); Prefs.audio(guest).sfxVolume=.4
            assert(Access.ensure(data).reducedMotion and Prefs.audio(data).sfxVolume==.4)
            assert(Access.motionSpeed(data)==4)
            mode='host'; assert(Access.motionSpeed(data)==1 and Access.motionSpeed(guest)==1)
            mode='client'; assert(Access.motionSpeed(guest)==1)
            local staged=assert(Schema.copy(data)); Access.ensure(staged)
            assert(not staged.accessibility and Access.motionSpeed(staged)==1 and Schema.validate(staged))
            assert(not Schema.migrate(guest))
        ''')

    def test_radio_override_is_personal_and_can_resume_following_shared_station(self):
        self.lua.execute('''
            attach(); data.audio.station='chill'; data.audio.rainEnabled=false
            local localAudio=Prefs.audio(data)
            localAudio.station='vibes'; localAudio.rainEnabled=true
            assert(data.audio.station=='chill' and not data.audio.rainEnabled and Prefs.hasOverride(data))
            data.audio.station='8bit'; assert(localAudio.station=='vibes')
            assert(Prefs.followRadio(data))
            assert(localAudio.station=='8bit' and not localAudio.rainEnabled and not Prefs.hasOverride(data))
            local other=Prefs.new(fs); other:attach(data)
            assert(Prefs.audio(data).station=='8bit' and not Prefs.hasOverride(data))
        ''')

    def test_failed_import_keeps_legacy_until_verified_write_succeeds(self):
        self.lua.execute('''
            data.audio.musicVolume=.7; data.accessibility.textSize=2
            local write=fs.write
            fs.write=function(path,text) if path==Prefs.PATH then return false end; return write(path,text) end
            attach()
            assert(store.lastError and not data.coop.preferencesDetached)
            assert(data.accessibility.textSize==2 and data.audio.musicVolume==.7)
            assert(files[Prefs.PATH..'.tmp'] and not files[Prefs.PATH])
            local recovered=Prefs.new(fs); assert(recovered.values.audio.musicVolume==.7)
            fs.write=write; attach()
            assert(not store.lastError and data.coop.preferencesDetached and not data.accessibility)
            assert(not files[Prefs.PATH..'.tmp'] and Schema.validate(data))
        ''')

    def test_false_success_and_throwing_filesystem_never_detach_campaign(self):
        self.lua.execute('''
            fs.write=function() return true end
            attach(); assert(store.lastError and not data.coop.preferencesDetached)
            fs.write=function() error('disk failure') end
            attach(); assert(store.lastError and data.accessibility and data.audio.sfxVolume)
        ''')

    def test_untrusted_settings_file_is_bounded_data_and_menu_edits_win_over_import(self):
        self.lua.execute('''
            files[Prefs.PATH]='executed=true; return {}'
            store=Prefs.new(fs); assert(not executed and not store.persisted)
            files[Prefs.PATH]=string.rep('x',8193)
            store=Prefs.new(fs); assert(not store.persisted)
            store.menu.audio.musicVolume=.31; Access.toggle(store.menu,'highContrast'); assert(store:save(true))
            data.audio.musicVolume=.8; attach()
            assert(Prefs.audio(data).musicVolume==.31 and Access.ensure(data).highContrast)
        ''')

    def test_schema_rejects_personal_fields_reintroduced_into_detached_campaign(self):
        self.lua.execute('''
            attach(); assert(Schema.validate(data))
            data.audio.musicVolume=.2; assert(not Schema.validate(data) and not Schema.migrate(data))
            data.audio.musicVolume=nil; data.accessibility={}; assert(not Schema.validate(data))
            data.accessibility=nil; data.coop.preferencesDetached='yes'; assert(not Schema.validate(data))
        ''')

    def test_guest_focus_and_shutdown_save_only_device_preferences(self):
        self.lua.execute('''
            mode='client'; attach(); local writes=0; local write=fs.write
            fs.write=function(...) writes=writes+1; return write(...) end
            local function forbidden() error('guest touched host campaign storage') end
            local session={networkMode='client',scheduleSave=forbidden}
            local runtime={selectedSlot=1,saveData=data,syncForSave=forbidden}
            local ui={localPreferences=store}
            local persistence=require('game.persistence_runtime').new({runtime=runtime,ui=ui,session=session,
                save={schedule=forbidden,update=forbidden,read=forbidden,remove=forbidden,flush=forbidden},
                maintenance={release=function() end},maintenanceSession={},focusMobile=function() end,
                focusAudio=function() end,shutdownAudio=function() end})
            Prefs.audio(data).musicVolume=.64
            assert(persistence.focus(false) and persistence.shutdown() and writes==4)
            assert(Prefs.new(fs).values.audio.musicVolume==.64)
            fs.write=function() return false end
            assert(not persistence.focus(false) and not persistence.shutdown() and store.lastError)
        ''')

    def test_production_audio_uses_device_volume_and_persists_playback_independently(self):
        self.lua.execute('''
            attach(); local audio={shutdown=function() end,installGunPools=function() end,
                update=function(_,settings) heard=settings.sfxVolume end,
                toggleMute=function(_,settings) settings.musicMuted=not settings.musicMuted; return settings.musicMuted end}
            local runtime={saveData=data,state='game',scene='train'}
            local service=require('game.audio_runtime').new({runtime=runtime,
                ui={localPreferences=store,menuSettings=store.menu},catalog={},audioCatalog={},audio={new=function() return audio end}})
            Prefs.audio(data).sfxVolume=.81; service.initialize(); service.update()
            assert(heard==.81 and not data.audio.sfxVolume)
            assert(service.toggleMute()); assert(not service.toggleMute())
            assert(Prefs.new(fs).values.audio.musicMuted==false)
            runtime.state='slots'; service.update(); assert(heard==.81)
        ''')

    def test_guest_audio_uses_projected_scene_radio_and_local_controls_without_host_runtime_swap(self):
        self.lua.execute('''
            attach(); local heard={}; local audio={shutdown=function() end,installGunPools=function() end,
                update=function(_,settings,category) heard={station=settings.station,rain=settings.rainEnabled,volume=settings.musicVolume,category=category} end,
                toggleMute=function(_,settings) settings.musicMuted=not settings.musicMuted; return settings.musicMuted end}
            local runtime={state='slots',saveData=nil,scene='train'}
            local service=require('game.audio_runtime').new({runtime=runtime,ui={localPreferences=store,menuSettings=store.menu},
                catalog={},audioCatalog={},audio={new=function() return audio end}})
            local guest={state='game',scene='stop',saveData=data}; data.audio.station='vibes'; data.audio.rainEnabled=false
            Prefs.followRadio(data); Prefs.audio(data).musicVolume=.42; service.initialize(); service.update(guest)
            assert(heard.station=='vibes' and heard.rain==false and heard.volume==.42 and heard.category=='stops')
            assert(runtime.state=='slots' and not runtime.saveData and not data.audio.musicVolume)
            assert(service.toggleMute(guest) and Prefs.new(fs).values.audio.musicMuted and not data.audio.musicMuted)
            guest.scene='house'; service.update(guest); assert(heard.category=='insideHomes')
            service.update(); assert(heard.category=='chill' and runtime.state=='slots')
        ''')


if __name__ == '__main__':
    unittest.main()
