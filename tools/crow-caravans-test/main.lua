local sourceBase=love.filesystem.getSourceBaseDirectory()
package.path=sourceBase.."/../?.lua;"..sourceBase.."/../?/init.lua;"..package.path

function love.load()
    local CrowCaravans=require("game.crow_caravans")
    local Catalog=require("game.catalog")
    local LootProgression=require("game.loot_progression")
    local MerchantTrade=require("game.merchant_trade")
    local SaveSchema=require("game.save_schema")
    local result=CrowCaravans.audit()
    if not result.ready then error("crow caravan audit failed: "..tostring(result.error or "unknown result")) end
    assert(#result.scheduledStops==3,"new journeys must receive exactly three caravans")
    assert(result.scheduledStops[1]>=7 and result.scheduledStops[1]<=16,"early caravan left its band")
    assert(result.scheduledStops[2]>=22 and result.scheduledStops[2]<=32,"middle caravan left its band")
    assert(result.scheduledStops[3]>=38 and result.scheduledStops[3]<=48,"late caravan left its band")
    assert(result.minimumGap>=8,"new-journey caravans are too close together")
    local tradeResult=MerchantTrade.audit(Catalog)
    assert(tradeResult.ready,"merchant trade audit failed")

    local fixed={inventoryCapacity=16}
    local fixedState,fixedError=CrowCaravans.ensureSchedule(fixed,{
        bands={{7,7},{23,23},{39,39}},useDefaultExclusions=false,rng=function() return 0 end,
    })
    if not fixedState then error(fixedError) end
    assert(table.concat(fixedState.scheduledStops,",")=="7,23,39","fixed schedule did not use all three bands")
    for _,stop in ipairs(fixedState.scheduledStops) do
        local camp,reason=CrowCaravans.ensureCamp(fixed,Catalog,stop,{rng=function() return .5 end})
        assert(camp,reason)
        assert(#camp.merchants==3,"camp must have three merchants")
        assert(CrowCaravans.isActive(camp),"new camp must be active")
        local affordable=false
        for _,listing in ipairs(CrowCaravans.merchant(camp,"packmaster").listings) do
            if listing.basePrice<=CrowCaravans.practicalPriceCap then affordable=true end
        end
        assert(affordable,"packmaster must guarantee a practical listing costing at most six scrap")
        assert(type(camp.resaleStock)=="table" and camp.nextResaleSequence==1,
            "new camps must initialize deterministic resale state")
        for _,merchant in ipairs(camp.merchants) do
            assert(#merchant.listings==4,"merchant must have four listings")
            assert(merchant.actorId==camp.id..":"..merchant.id,"merchant actor id must be stable")
            for _,listing in ipairs(merchant.listings) do
                assert(type(listing.basePrice)=="number" and listing.basePrice>0,"listing needs a base price")
                if listing.kind=="weapon" then
                    assert(listing.weaponTier<=math.min(9,LootProgression.locationTier(stop)+1),"weapon exceeds caravan tier")
                elseif listing.kind=="ammo" then
                    assert(LootProgression.ammoUnlockTier[listing.item]<=LootProgression.locationTier(stop),"ammo is locked")
                elseif listing.category=="backpack" then
                    assert(Catalog.backpackUpgrades[listing.item].capacity>fixed.inventoryCapacity,"pack is not an upgrade")
                end
                assert(listing.item~="rose-heart-arrow" and listing.item~="blade-hearts","permanent heart leaked into default stock")
            end
        end
    end

    local preferenceData={
        inventoryCapacity=16,
        equipment={[1]="frontier-short-sword",[3]="compact-scrap-pistol"},
        inventory={[4]="long-barrel-22-pistol"},
        weaponDurability={["frontier-short-sword"]=100,["compact-scrap-pistol"]=100,["long-barrel-22-pistol"]=100},
        weaponProficiency={blade=12,firearms=9},
        ammo={["9mm"]=0,["22lr"]=30},
    }
    assert(CrowCaravans.ensureSchedule(preferenceData,{
        bands={{7,7},{23,23},{39,39}},useDefaultExclusions=false,rng=function() return 0 end,
    }))
    local preferenceCamp=assert(CrowCaravans.ensureCamp(preferenceData,Catalog,23,{rng=function() return .5 end}))
    local preferredPackmaster=CrowCaravans.merchant(preferenceCamp,"packmaster")
    assert(preferredPackmaster.listings[4].item=="9mm",
        "packmaster should favor the lowest-reserve ammo for an owned usable ranged weapon")
    local preferredIronbeak=CrowCaravans.merchant(preferenceCamp,"ironbeak")
    local ownedFamilies={blade=true,firearms=true}
    for slot=1,2 do
        local family=Catalog.weaponFamily(preferredIronbeak.listings[slot].item)
        assert(not ownedFamilies[family] and not preferenceData.weaponProficiency[family],
            "ironbeak should favor an unowned and untried family in each weapon role")
    end
    for _,listing in ipairs(preferredIronbeak.listings) do
        assert(listing.weaponTier<=LootProgression.locationTier(23)+1,
            "family preference must not exceed the caravan weapon tier limit")
    end

    local brokenWeaponData={
        inventoryCapacity=16,equipment={[2]="compact-scrap-pistol"},inventory={[5]="long-barrel-22-pistol"},
        weaponDurability={["compact-scrap-pistol"]=0,["long-barrel-22-pistol"]=75},
        ammo={["9mm"]=0,["22lr"]=20},
    }
    assert(CrowCaravans.ensureSchedule(brokenWeaponData,{
        bands={{7,7},{23,23},{39,39}},useDefaultExclusions=false,rng=function() return 0 end,
    }))
    local brokenWeaponCamp=assert(CrowCaravans.ensureCamp(brokenWeaponData,Catalog,23,{rng=function() return .5 end}))
    assert(CrowCaravans.merchant(brokenWeaponCamp,"packmaster").listings[4].item=="22lr",
        "ammo preference must ignore broken ranged weapons")

    local baseListing=preferredIronbeak.listings[1]
    local baseQuantity=baseListing.quantity
    local mergedBase,createdBase=CrowCaravans.addResaleListing(preferenceCamp,"packmaster",baseListing.item,
        Catalog,LootProgression,2)
    assert(mergedBase==baseListing and not createdBase and baseListing.quantity==baseQuantity+1
        and #preferenceCamp.resaleStock==0,"resale must merge with matching stock anywhere in camp")

    local decorListing,createdDecor=CrowCaravans.addResaleListing(preferenceCamp,"packmaster","orange-rose-vase",
        Catalog,LootProgression,2)
    assert(decorListing and createdDecor and decorListing.item=="orange-rose-vase" and decorListing.quantity==1,
        "sellable decor must enter caravan resale stock")
    assert(decorListing.id==preferenceCamp.id..":packmaster:resale:1" and decorListing.basePrice==3
        and decorListing.acquiredFor==2,"resale listing metadata must be deterministic and safely priced")
    local mergedDecor,createdDuplicate=CrowCaravans.addResaleListing(preferenceCamp,"ironbeak","orange-rose-vase",
        Catalog,LootProgression,3)
    assert(mergedDecor==decorListing and not createdDuplicate and decorListing.quantity==2
        and #preferenceCamp.resaleStock==1,"camp-wide resale duplicates must merge into one persistent stack")
    assert(#CrowCaravans.tradeListings(preferenceCamp,"packmaster",Catalog,LootProgression)==5
        and #CrowCaravans.tradeListings(preferenceCamp,"ironbeak",Catalog,LootProgression)==4,
        "tradeListings must append resale stock only to its owning merchant")

    local savedPreference=assert(SaveSchema.copy(preferenceData))
    local savedCamp=assert(CrowCaravans.ensureCamp(savedPreference,Catalog,23,{rng=function() return .99 end}))
    local savedDecor=CrowCaravans.listing(savedCamp,"packmaster",decorListing.id)
    assert(savedDecor and savedDecor.id==decorListing.id and savedDecor.quantity==2,
        "resale stock and stable ids must survive a save-friendly deep copy")
    savedDecor.quantity="2"
    local consumedLegacy,remainingDecor=CrowCaravans.consumeListing(savedCamp,"packmaster",savedDecor.id)
    assert(consumedLegacy and remainingDecor.quantity==1 and type(remainingDecor.quantity)=="number",
        "legacy string quantities must normalize before resale consumption")

    local repairData={inventoryCapacity=16,crowCaravans={version=1,scheduleVersion=1,scheduleMode="journey",
        scheduledStops={7,23,39},camps={["23"]={id="legacy-camp",stop=23,visited=true,nextResaleSequence="bad",
            resaleStock={
                {merchantId="packmaster",item="cowboy-hat",quantity="2",sequence=4,acquiredFor=1},
                {merchantId="missing",item="orange-rose-vase",quantity=1,sequence=5},
                {merchantId="ironbeak",item=" ",quantity=1,sequence=6},
            }}}}}
    local repairedCamp=assert(CrowCaravans.ensureCamp(repairData,Catalog,23,{rng=function() return .5 end}))
    assert(repairedCamp.visited and #repairedCamp.resaleStock==1 and repairedCamp.resaleStock[1].item=="cowboy-hat"
        and repairedCamp.resaleStock[1].quantity==2 and repairedCamp.resaleStock[1].id==repairedCamp.id..":packmaster:resale:4"
        and repairedCamp.nextResaleSequence==5,"incomplete camp repair must preserve and normalize valid resale stock")

    assert(CrowCaravans.markDeparted(fixed,7) and not CrowCaravans.isActive(CrowCaravans.lookup(fixed,7)),"departure did not persist")

    local locked={inventoryCapacity=6,crowCaravans={scheduleVersion=0,scheduledStops={}}}
    local lockedState=assert(CrowCaravans.ensureSchedule(locked,{
        bands={{7,7},{23,23},{39,39}},useDefaultExclusions=false,rng=function() return 0 end,
    }))
    assert(lockedState.scheduleVersion==1 and lockedState.scheduleMode=="journey","fresh schedule was not locked")
    local lockedStops=table.concat(lockedState.scheduledStops,",")
    local lockedAgain,lockedError,lockedChanged=CrowCaravans.ensureSchedule(locked,{
        bands={{7,7},{23,23},{39,39}},useDefaultExclusions=false,excludedStops={7,23,39},rng=function() return .99 end,
    })
    assert(lockedAgain,lockedError)
    assert(table.concat(lockedAgain.scheduledStops,",")==lockedStops and not lockedChanged,
        "dynamic exclusions changed a locked schedule")

    local function legacyFixture()
        return {
            character="schedule-test-mouse",location=30,inventoryCapacity=6,
            visitedStops={[12]=true,[30]=true,[31]=true},mysteryStops={5,13,24,34,45},
            crowCaravans={version=1,scheduleVersion=0,scheduledStops={},camps={}},
        }
    end
    local function legacyOptions(data)
        return {
            futureOnly=true,currentLocation=data.location,useDefaultExclusions=false,
            excludedStops={32,38,43,44,47,48},rng=CrowCaravans.deterministicRng(data,"legacy-future-schedule"),
        }
    end
    local legacyA,legacyB=legacyFixture(),legacyFixture()
    local futureA,futureErrorA=assert(CrowCaravans.ensureSchedule(legacyA,legacyOptions(legacyA)))
    local futureB,futureErrorB=assert(CrowCaravans.ensureSchedule(legacyB,legacyOptions(legacyB)))
    assert(not futureErrorA and not futureErrorB)
    assert(table.concat(futureA.scheduledStops,",")==table.concat(futureB.scheduledStops,","),
        "legacy schedule was not deterministic")
    assert(#futureA.scheduledStops==1 and futureA.scheduledStops[1]>30 and futureA.scheduledStops[1]~=31,
        "legacy schedule included an elapsed or visited stop")
    assert(futureA.scheduleVersion==1 and futureA.scheduleMode=="legacy-future","legacy schedule was not locked as partial")
    assert(legacyA.visitedStops[12] and legacyA.visitedStops[30] and legacyA.visitedStops[31]
        and legacyA.visitedStops[32]==nil,"legacy scheduling rewrote visited-stop state")
    local futureStop=futureA.scheduledStops[1]
    local futureLocked=assert(CrowCaravans.ensureSchedule(legacyA,{excludedStops={futureStop},rng=function() return .99 end}))
    assert(#futureLocked.scheduledStops==1 and futureLocked.scheduledStops[1]==futureStop,
        "partial migrated schedule did not stay locked")

    local elapsed={
        character="late-migration",location=46,visitedStops={[46]=true},
        crowCaravans={version=1,scheduleVersion=0,scheduledStops={},camps={}},
    }
    local elapsedState=assert(CrowCaravans.ensureSchedule(elapsed,{
        futureOnly=true,currentLocation=46,excludedStops={47,48},rng=CrowCaravans.deterministicRng(elapsed,"legacy-future-schedule"),
    }))
    assert(#elapsedState.scheduledStops==0 and elapsedState.scheduleMode=="legacy-future",
        "elapsed migration bands should be skipped")
    assert(#assert(CrowCaravans.ensureSchedule(elapsed)).scheduledStops==0,"empty migrated schedule did not stay locked")

    local malformed={
        character="repair-test",location=30,visitedStops={[9]=true,[28]=true},
        crowCaravans={version=1,scheduleVersion=1,scheduleMode="journey",scheduledStops={9,9,28,50},
            camps={["9"]={stop=9,visited=true},["28"]={stop=28,visited=true}}},
    }
    local repaired=assert(CrowCaravans.ensureSchedule(malformed,{excludedStops={9,28},rng=function() return .5 end}))
    assert(#repaired.scheduledStops==3 and repaired.scheduledStops[1]==9 and repaired.scheduledStops[2]==28
        and repaired.scheduledStops[3]>=38 and repaired.scheduledStops[3]<=48,
        "malformed schedule repair moved a visited valid appearance")
    assert(repaired.scheduledStops[2]-repaired.scheduledStops[1]>=8
        and repaired.scheduledStops[3]-repaired.scheduledStops[2]>=8,"repaired schedule broke minimum spacing")

    local blocked,blockedError=CrowCaravans.ensureSchedule({}, {
        bands={{7,7},{23,23},{39,39}},useDefaultExclusions=false,excludedStops={7},rng=function() return 0 end,
    })
    assert(not blocked and blockedError:find("no eligible stops",1,true),"empty band must fail clearly")

    print("CROW_CARAVAN_AUDIT_OK stops="..table.concat(result.scheduledStops,",")
        .." merchants="..result.merchants.." listings="..result.listings)
    love.event.quit(0)
end
