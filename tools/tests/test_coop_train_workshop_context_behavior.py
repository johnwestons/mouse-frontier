"""Train purchase affordances and authority share the original train-only scene."""
import unittest
import test_coop_authority_behavior as authority
import test_coop_guest_train_behavior as guest_train


class TrainWorkshopAuthorityTests(unittest.TestCase):
    setUp = authority.CoopAuthorityTests.setUp

    def test_both_actors_and_both_upgrade_commands_reject_off_train_without_campaign_effects(self):
        self.lua.execute('''
            data.location=50;data.scrap=200
            local Codec=require('game.net.codec');local limits={maxBytes=1048576,maxDepth=32,maxEntries=20000,maxStringBytes=65536}
            local function plain(value)
                if type(value)~='table' then return value end
                local result={};for key,entry in pairs(value) do result[type(key)..':'..tostring(key)]=plain(entry) end;return result
            end
            for _,id in ipairs({'host','companion'}) do
                for _,command in ipairs({'train.upgrade','train.engineUpgrade'}) do
                    for _,scene in ipairs({'stop','house','expedition','caravan'}) do
                        data.scene='train';states[id].scene='train'
                        local req=request(id,command,command=='train.upgrade' and {carId='storage',quotedPrice=22}
                            or {quotedPrice=15,quotedLevel=1})
                        data.scene=scene;states[id].scene=scene
                        local before=assert(Codec.encode(plain(data),limits))
                        local ok,reason=authority:prepareRequest(id,command,req.args)
                        assert(not ok and reason=='unavailable',id..' prepared an off-train purchase')
                        local response=run(id,req);assert(not response.ok and response.reason=='unavailable')
                        assert(Codec.encode(plain(data),limits)==before,'off-train purchase mutated '..scene)
                    end
                end
            end
        ''')

    def test_mismatched_trusted_and_campaign_scene_rejects_and_real_train_purchase_still_works(self):
        self.lua.execute('''
            data.location=50;data.scrap=200
            for _,id in ipairs({'host','companion'}) do
                data.scene='train';states[id].scene='train'
                local req=request(id,'train.engineUpgrade',{})
                states[id].scene='stop';assert(run(id,req).reason=='unavailable')
                states[id].scene='train';data.scene='stop'
                assert(not authority:prepareRequest(id,'train.engineUpgrade',{}))
                data.scene='train';local level=data.engineLevel;local scrap=data.scrap
                local result=run(id,request(id,'train.engineUpgrade',{}))
                assert(result.ok and data.engineLevel==level+1 and data.scrap<scrap)
            end
            -- General personal inventory remains available away from the train.
            data.scene='stop';states.companion.scene='stop';guest.inventory[1]='cowboy-hat'
            local result=run('companion',request('companion','inventory.swap',
                {source={kind='inventory',index=1},target={kind='inventory',index=2}}))
            assert(result.ok and guest.inventory[2]=='cowboy-hat' and not guest.inventory[1])
        ''')


class GuestWorkshopContextTests(unittest.TestCase):
    setUp = guest_train.GuestTrainTests.setUp

    def test_direct_keyboard_and_panel_routes_cannot_open_or_submit_off_train(self):
        self.lua.execute('''
            for _,scene in ipairs({'stop','house','expedition','caravan'}) do
                runtime.scene=scene;runtime.saveData.scene=scene
                assert(not panel:workshopAvailable() and not panel:open())
                assert(not panel:submit('train.upgrade',{carId='storage',quotedPrice=22},{}))
                assert(not panel:submit('train.engineUpgrade',{quotedPrice=15,quotedLevel=1},{}))
                assert(not runtime.trainUpgradeOpen and #requests==0)
            end
            runtime.scene='train';runtime.saveData.scene='stop';assert(not panel:open())
            runtime.saveData.scene='train';runtime.state='battle';assert(not panel:open())
            runtime.state='game';assert(panel:open() and panel:choose('engine') and panel:confirm())
            assert(#requests==1 and requests[1].name=='train.engineUpgrade')
        ''')

    def test_scene_handoff_invalidates_old_quote_before_another_draw_and_preserves_pending_receipt(self):
        self.lua.execute('''
            assert(panel:open() and panel:choose('storage'));local oldQuote=panel.quote
            runtime.scene='stop';runtime.saveData.scene='stop'
            assert(not panel:confirm() and #requests==0)
            panel:update();assert(not runtime.trainUpgradeOpen and not panel.quote and not panel.offers)
            runtime.scene='train';runtime.saveData.scene='train'
            assert(panel:open() and panel:choose('storage') and panel:confirm())
            runtime.scene='expedition';runtime.saveData.scene='expedition';panel:update()
            assert(not runtime.trainUpgradeOpen and panel.pending and #requests==1)
            result(1,{carId='storage',price=22},copy.coop.revision);panel:update()
            assert(not panel.pending and #requests==1 and data.scrap==200)
        ''')


if __name__ == '__main__':
    unittest.main()
