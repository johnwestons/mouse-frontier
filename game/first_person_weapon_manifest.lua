local Manifest={}

local ROOT="assets/sprites/weapons/first-person/"
local DEFAULT_ADS_ANCHOR={x=.5,y=.35,calibrated=false}

-- Keep an entry uncalibrated until its production PNG has been checked against
-- the in-game reticle. The renderer can use the safe default without presenting
-- that default as weapon-specific sight data.

local function path(file)
    return ROOT..file
end

local function pair(id,anchor)
    return {
        kind="firearm",
        views={
            hip=path(id.."-hip.png"),
            sights=path(id.."-sights.png"),
        },
        adsAnchor=anchor,
    }
end

local function special(id,states,hipState,sightsState,anchor,shotSequence)
    local views={}
    for state,file in pairs(states) do views[state]=path(file) end
    views.hip=assert(views[hipState],id.." requires a hip state")
    views.sights=assert(views[sightsState],id.." requires an aimed state")
    return {kind="special",views=views,adsAnchor=anchor,shotSequence=shotSequence}
end

Manifest.weapons={
    ["frontier-22-lever-rifle"]=pair("frontier-22-lever-rifle",{x=.498455,y=.159358,calibrated=true}),
    ["frontier-sr22-pistol"]=pair("frontier-sr22-pistol",{x=.500000,y=.127592,calibrated=true}),
    ["frontier-22-pocket-pistol"]=pair("frontier-22-pocket-pistol",{x=.500000,y=.251196,calibrated=true}),
    ["frontier-compact-9mm"]=pair("frontier-compact-9mm",{x=.500000,y=.114833,calibrated=true}),
    ["frontier-silver-22-revolver"]=pair("frontier-silver-22-revolver",{x=.500000,y=.106771,calibrated=true}),
    ["frontier-32-pocket-pistol"]=pair("frontier-32-pocket-pistol",{x=.500000,y=.188995,calibrated=true}),
    ["frontier-380-pocket-pistol"]=pair("frontier-380-pocket-pistol",{x=.499554,y=.202423,calibrated=true}),
    ["frontier-pearl-pocket-pistol"]=pair("frontier-pearl-pocket-pistol",{x=.500000,y=.139323,calibrated=true}),
    ["frontier-silver-compact-pistol"]=pair("frontier-silver-compact-pistol",{x=.500000,y=.230463,calibrated=true}),
    ["frontier-compact-9mm-pistol"]=pair("frontier-compact-9mm-pistol",{x=.500000,y=.259968,calibrated=true}),
    ["frontier-45-1911"]=pair("frontier-45-1911",{x=.500000,y=.126953,calibrated=true}),
    ["frontier-9mm-service-pistol"]=pair("frontier-9mm-service-pistol",{x=.500000,y=.114833,calibrated=true}),
    ["frontier-9mm-glock"]=pair("frontier-9mm-glock",{x=.500000,y=.083732,calibrated=true}),
    ["frontier-22-target-pistol"]=pair("frontier-22-target-pistol",{x=.500000,y=.074960,calibrated=true}),
    ["frontier-380-revolver"]=pair("frontier-380-revolver",{x=.500000,y=.261719,calibrated=true}),
    ["long-barrel-22-pistol"]=pair("long-barrel-22-pistol",{x=.500000,y=.238260,calibrated=true}),
    ["heavy-frontier-pistol"]=pair("heavy-frontier-pistol",{x=.499023,y=.113932,calibrated=true}),
    ["frontier-long-barrel-revolver"]=pair("frontier-long-barrel-revolver",{x=.498047,y=.138672,calibrated=true}),
    ["frontier-long-22-target-pistol"]=pair("frontier-long-22-target-pistol",{x=.500000,y=.214844,calibrated=true}),
    ["frontier-lever-rifle"]=pair("frontier-lever-rifle",{x=.494141,y=.183594,calibrated=true}),
    ["wood-stock-survival-carbine"]=pair("wood-stock-survival-carbine",{x=.499023,y=.173828,calibrated=true}),
    ["vintage-bolt-action-rifle"]=pair("vintage-bolt-action-rifle",{x=.490741,y=.283508,calibrated=true}),
    ["frontier-12g-pump-shotgun"]=pair("frontier-12g-pump-shotgun",{x=.500977,y=.141276,calibrated=true}),
    ["frontier-762-carbine"]=pair("frontier-762-carbine",{x=.500000,y=.223958,calibrated=true}),
    ["weathered-lever-rifle"]=pair("weathered-lever-rifle",{x=.499023,y=.211589,calibrated=true}),
    ["patched-22-survival-rifle"]=pair("patched-22-survival-rifle",{x=.497069,y=.168655,calibrated=true}),
    ["frontier-lever-carbine"]=pair("frontier-lever-carbine",{x=.495117,y=.214193,calibrated=true}),
    ["compact-carbine"]=pair("compact-carbine",{x=.496395,y=.196296,calibrated=true}),
    ["frontier-556-carbine"]=pair("frontier-556-carbine",{x=.497070,y=.145182,calibrated=true}),
    ["improvised-556-rifle"]=pair("improvised-556-rifle",{x=.500000,y=.142230,calibrated=true}),
    ["improvised-service-rifle"]=pair("improvised-service-rifle",{x=.499511,y=.210150,calibrated=true}),
    ["frontier-9mm-smg"]=pair("frontier-9mm-smg",{x=.499436,y=.143179,calibrated=true}),
    ["frontier-ak-compact"]=pair("frontier-ak-compact",{x=.500000,y=.138672,calibrated=true}),
    ["frontier-single-shot-hunter"]=pair("frontier-single-shot-hunter",{x=.500000,y=.186198,calibrated=true}),
    ["scrap-pistol"]=pair("scrap-pistol",{x=.500000,y=.162679,calibrated=true}),
    ["compact-scrap-pistol"]=pair("compact-scrap-pistol",{x=.500000,y=.231260,calibrated=true}),
    ["sawed-off-shotgun"]=pair("sawed-off-shotgun",{x=.500000,y=.125199,calibrated=true}),
    ["machine-pistol"]=pair("machine-pistol",{x=.500000,y=.092504,calibrated=true}),
    ["rugged-submachine-gun"]=pair("rugged-submachine-gun",{x=.500424,y=.101949,calibrated=true}),

    -- The user-approved full-draw master is the only production bow view for
    -- now. Earlier low-ready, nocked, partial-draw, and release attempts were
    -- explicitly rejected, so both runtime poses intentionally share it until
    -- matching states are derived from that master.
    ["hunting-bow"]=special("hunting-bow",{
        fullDraw="hunting-bow-full-draw-aim.png",
    },"fullDraw","fullDraw",{x=.490431,y=.456938,calibrated=true}),
    ["critter-crossbow"]=special("critter-crossbow",{
        lowReady="critter-crossbow-low-ready.png",
        uncocked="critter-crossbow-uncocked.png",
        cocked="critter-crossbow-cocked.png",
        loadedAim="critter-crossbow-bolt-loaded-aim.png",
        release="critter-crossbow-release.png",
    },"lowReady","loadedAim",{x=.500000,y=.155212,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="uncocked",placement="hip"},
        },
    }),
    ["trail-slingshot"]=special("trail-slingshot",{
        lowReady="trail-slingshot-low-ready.png",
        loaded="trail-slingshot-loaded.png",
        fullDraw="trail-slingshot-full-draw-aim.png",
        release="trail-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.326954,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["wrist-braced-slingshot"]=special("wrist-braced-slingshot",{
        lowReady="wrist-braced-slingshot-low-ready.png",
        loaded="wrist-braced-slingshot-loaded.png",
        fullDraw="wrist-braced-slingshot-full-draw-aim.png",
        release="wrist-braced-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.199362,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["metal-scrap-slingshot"]=special("metal-scrap-slingshot",{
        lowReady="metal-scrap-slingshot-low-ready.png",
        loaded="metal-scrap-slingshot-loaded.png",
        fullDraw="metal-scrap-slingshot-full-draw-aim.png",
        release="metal-scrap-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.223285,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["long-hunting-slingshot"]=special("long-hunting-slingshot",{
        lowReady="long-hunting-slingshot-low-ready.png",
        loaded="long-hunting-slingshot-loaded.png",
        fullDraw="long-hunting-slingshot-full-draw-aim.png",
        release="long-hunting-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.117188,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["scrap-boomerang"]=special("scrap-boomerang",{
        ready="scrap-boomerang-ready-throw.png",
        flight="scrap-boomerang-flight-spin.png",
        returning="scrap-boomerang-return-approach.png",
    },"ready","ready",nil,{
        steps={
            {state="flight",duration=.28,placement="hip"},
            {state="returning",duration=.34,placement="hip"},
            {state="ready",duration=.08,placement="hip"},
        },
        restoresLoaded=true,
    }),
}

local function validAnchor(anchor)
    return type(anchor)=="table" and type(anchor.x)=="number" and type(anchor.y)=="number"
        and anchor.x>=0 and anchor.x<=1 and anchor.y>=0 and anchor.y<=1
        and type(anchor.calibrated)=="boolean"
end

function Manifest.anchorFor(name)
    local entry=Manifest.weapons[name]
    local anchor=entry and entry.adsAnchor
    if validAnchor(anchor) then return {x=anchor.x,y=anchor.y},anchor.calibrated==true end
    return {x=DEFAULT_ADS_ANCHOR.x,y=DEFAULT_ADS_ANCHOR.y},false
end

function Manifest.calibrationSummary()
    local result={calibrated=0,provisional=0,withoutAnchor=0}
    for _,entry in pairs(Manifest.weapons) do
        local anchor=entry.adsAnchor
        if validAnchor(anchor) then
            if anchor.calibrated then result.calibrated=result.calibrated+1
            else result.provisional=result.provisional+1 end
        else
            result.withoutAnchor=result.withoutAnchor+1
        end
    end
    return result
end

function Manifest.shotSequenceFor(name)
    local entry=Manifest.weapons[name]
    return entry and entry.shotSequence or nil
end

local function validateShotSequence(name,entry,issues)
    local sequence=entry.shotSequence
    if sequence==nil then return end
    if type(sequence)~="table" or type(sequence.steps)~="table" or #sequence.steps==0 then
        issues[#issues+1]=name.." has an invalid shot sequence"
        return
    end
    if sequence.restoresLoaded~=nil and type(sequence.restoresLoaded)~="boolean" then
        issues[#issues+1]=name.." has an invalid restoresLoaded flag"
    end
    for index,step in ipairs(sequence.steps) do
        if type(step)~="table" or type(step.state)~="string" or not entry.views[step.state] then
            issues[#issues+1]=name.." shot sequence step "..index.." has no matching view"
        elseif step.placement~="hip" and step.placement~="sights" then
            issues[#issues+1]=name.." shot sequence step "..index.." has an invalid placement"
        elseif step.duration~=nil and (type(step.duration)~="number" or step.duration<=0) then
            issues[#issues+1]=name.." shot sequence step "..index.." has an invalid duration"
        elseif index<#sequence.steps and step.duration==nil then
            issues[#issues+1]=name.." shot sequence step "..index.." cannot hold before the final step"
        end
    end
end

function Manifest.validate()
    local issues={}
    for name,entry in pairs(Manifest.weapons) do
        if type(name)~="string" or name=="" then issues[#issues+1]="invalid weapon id"
        elseif type(entry)~="table" or type(entry.views)~="table" then issues[#issues+1]=name.." has no views"
        else
            for _,state in ipairs({"hip","sights"}) do
                if type(entry.views[state])~="string" or entry.views[state]=="" then
                    issues[#issues+1]=name.." has no "..state.." view"
                end
            end
            for state,file in pairs(entry.views) do
                if type(state)~="string" or type(file)~="string" or not file:match("%.png$") then
                    issues[#issues+1]=name.." has an invalid view entry"
                end
            end
            if entry.adsAnchor~=nil and not validAnchor(entry.adsAnchor) then
                issues[#issues+1]=name.." has an invalid ADS anchor"
            end
            validateShotSequence(name,entry,issues)
        end
    end
    return #issues==0,issues
end

return Manifest
