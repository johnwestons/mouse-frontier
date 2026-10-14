-- Read-only scene callbacks for a detached guest presentation. Never use the
-- ordinary world-scene service here: its lazy getters may create world state.
local Areas=require('game.expedition_areas')
local Expedition=require('game.expedition_runtime')
local Caravan=require('game.crow_caravan_area')
local Caravans=require('game.crow_caravans')
local Sludges=require('game.stop_sludges')
local Wildlife=require('game.wildlife')
local Mice=require('game.mice')
local ShootingRange=require('game.shooting_range')
local Life=require('game.coop_last_stand_lifecycle')
local View={}
local function shallow(value)
    local result={}; for key,item in pairs(value or {}) do result[key]=item end; return result
end
function View.new(c)
    local runtime=assert(c.runtime); local scenery=assert(c.content).scenery
    local areas=shallow(Areas)
    function areas.state(data,id) return data.expeditions and data.expeditions[id] end
    function areas.updateGates(data,id) local state=areas.state(data,id); return state and state.gates end
    function areas.environment(data,id) return Areas.environment(data,id,true) end
    function areas.isMobActive(data,id,mob)
        local gates=areas.updateGates(data,id)
        return not mob.requires or gates and gates[mob.requires]==true
    end
    local roaming=shallow(require('game.roaming_mobs')); local drawMobs=roaming.draw
    local drawDistances={}
    function roaming.draw(system,context,drawPlayer)
        local drawContext=shallow(context); local area=shallow(context.area); area.mobs={}
        local state=shallow(context.areaState); state.mobs={}
        local visualSystem=shallow(system); visualSystem.transient=shallow(system.transient)
        local transients={}; visualSystem.transient[area.id]=transients
        for _,mob in ipairs(context.area.mobs or {}) do
            local saved=context.areaState.mobs[mob.id]
            local live=c.roamingPresentation and c.roamingPresentation:get(mob.id)
            -- Reliable dead flags win. A stale/default zero death timer never
            -- resurrects a defeated mob when a baseline or scene is replaced.
            local active=live and live.active or not live and (not context.isActive or context.isActive(mob))
            if saved and (not saved.dead or live and live.allowDeath and live.deathTimer<1.35) and active then
                area.mobs[#area.mobs+1]=mob
                state.mobs[mob.id]=shallow(saved)
                local transient={state='patrol',timer=0,facing=1,animationDistance=0,hitTimer=0,healthTimer=0,deathTimer=0}
                for key,value in pairs(system.transient[area.id] and system.transient[area.id][mob.id] or {}) do transient[key]=value end
                -- Saved attack cues can supply a brief hit flash, but stale
                -- AI states must not leave an eternal warning/attack pose.
                transient.state='patrol'; transient.timer=0
                if live then
                    state.mobs[mob.id].x,state.mobs[mob.id].y=live.x,live.y
                    for key,value in pairs(live) do if key~='x' and key~='y' then transient[key]=value end end
                    transient.lastDrawDistance=drawDistances[mob.id] or live.animationDistance
                end
                transients[mob.id]=transient
            end
        end
        drawContext.area=area; drawContext.areaState=state
        drawMobs(visualSystem,drawContext,drawPlayer)
        for id,transient in pairs(transients) do drawDistances[id]=transient.lastDrawDistance end
    end
    local options={runtime=runtime,ui=c.ui,catalog=c.catalog,areas=areas,
        roamingMobs=roaming,width=960,height=720,suppressMessages=true,readOnlyPresentation=true,
        getIsWeapon=function() return function(name) return c.catalog.weaponStats[name]~=nil end end,
        getBeginEncounter=function() error('guest presentation cannot begin encounters') end,
        writeSave=function() error('guest presentation cannot save') end,
        clampToStop=function() error('guest presentation cannot change scene') end}
    -- Atlas images loaded by this instance must never replace the solo world's
    -- tables. Shared ordinary sprite images remain owned by the asset streamer.
    for _,key in ipairs({'mobImages','mobIdleImages','mobWalkImages','mobAttackImages',
        'mobHitImages','mobDeathImages','mobRangedImages'}) do
        -- Ordinary encounter art loads after the guest scene is constructed.
        -- Keep those lookups live while writing private expedition atlases to
        -- the local table, so neither early copies nor released images linger.
        options[key]=setmetatable({},{__index=c.content[key] or {}})
    end
    local expedition=Expedition.new(options)
    local sludges=Sludges.new(); local caravanSession
    -- Tactical and roaming presentation share this guest's authored atlases.
    -- These private tables retain live ordinary-art lookups through __index.
    local view={battleImages={}}
    for _,key in ipairs({'mobImages','mobIdleImages','mobWalkImages','mobAttackImages',
        'mobHitImages','mobDeathImages','mobRangedImages'}) do view.battleImages[key]=options[key] end
    function view.ensureStopLayout()
        local data=runtime.saveData
        local layout=data.stopLayouts and data.stopLayouts[tostring(data.location)]
        assert(layout,'guest scene is missing the host stop layout')
        if runtime.scene=='house' then
            local door=layout.houseDoors and layout.houseDoors[tostring(data.activeHouseDoor or 1)]
            if door then local result=shallow(layout); result.interior=door.interior or layout.interior; return result end
        end
        return layout
    end
    function view.itemIsHere(item)
        local data=runtime.saveData
        if item.scene~=runtime.scene then return false end
        if runtime.scene=='train' then return (item.carIndex or 1)==(data.activeCar or 1) end
        if runtime.scene=='house' then return item.location==data.location and (item.houseDoor or 1)==(data.activeHouseDoor or 1) end
        if runtime.scene=='expedition' then return item.expeditionAreaId==data.activeExpeditionArea end
        if runtime.scene=='caravan' then return data.crowCaravans and item.caravanCampId==data.crowCaravans.activeCampId end
        return item.location==data.location
    end
    function view.pendingMailHere()
        local data=runtime.saveData
        for _,quest in ipairs(data.mailQuests or {}) do
            if not quest.complete and quest.destination==data.location and quest.recipient==data.currentNPC then return quest end
        end
    end
    function view.drawWildlife(layout)
        if runtime.scene~='stop' or not layout then return end
        Wildlife.draw(layout.wildlife,scenery.stopWildlife,runtime.animationClock)
        Mice.draw(layout.mice,scenery.stopWildlife,runtime.animationClock)
    end
    function view.drawStopSludges(images)
        Sludges.draw(sludges,{data=runtime.saveData,location=runtime.saveData.location,
            clock=runtime.animationClock,images=images,readOnly=true})
    end
    function view.drawShootingRangeSpot()
        if runtime.scene~='stop' then return end
        ShootingRange.drawSpot(view.ensureStopLayout().shootingRange,
            scenery.shootingRangeAssets and scenery.shootingRangeAssets.entrance,runtime.animationClock)
    end
    function view.drawCaravanGate()
        local data=runtime.saveData; local root=data.crowCaravans
        if runtime.scene~='stop' or not root then return end
        local scheduled=false
        for _,stop in ipairs(root.scheduledStops or {}) do if stop==data.location then scheduled=true; break end end
        local camp=Caravans.lookup(data,data.location)
        if not scheduled or camp and not Caravans.isActive(camp) then return end
        local gate=Caravan.stopGate(data.location); if not gate then return end
        local banner=assert(scenery.crowCaravanAssets and scenery.crowCaravanAssets.crowBanner)
        local width,height=banner:getDimensions()
        local settings=require('game.accessibility').ensure(data)
        local sway=settings.reducedMotion and 0 or math.sin(runtime.animationClock*1.7)*math.rad(1.6)
        love.graphics.setColor(1,1,1,1); love.graphics.draw(banner,gate.x,gate.y+12,sway,94/height,94/height,width/2,height)
    end
    local function campState()
        local root=runtime.saveData.crowCaravans
        for _,camp in pairs(root and root.camps or {}) do if camp.id==root.activeCampId then return camp end end
    end
    function view.drawCaravanRuntime(options)
        local camp=assert(campState(),'guest scene is missing the host caravan')
        if not caravanSession or caravanSession.state~=camp then
            caravanSession=assert(Caravan.new({stop=camp.stop,seed=camp.seed,variantId=camp.variantId}))
            caravanSession.state=camp; caravanSession.data=runtime.saveData
        end
        caravanSession.clock=runtime.animationClock
        return Caravan.draw(caravanSession,options)
    end
    local retentionOptions={}
    local function assetPlan()
        local data=runtime.saveData;local keep={backgrounds={},mobs={}}
        local hidden=retentionOptions.range==true or Life.active(data)~=nil
            or data and data.scene=='train' and data.trainAmbush and data.trainAmbush.active==true or false
        if not data or hidden then return keep,hidden end
        if runtime.battle then
            for _,unit in ipairs(runtime.battle.units or {})do if unit.file then keep.mobs[unit.file]=true end end
        elseif runtime.scene=='expedition' then
            local area=Areas.current(data)
            if area then
                keep.backgrounds[area.id]=true
                for _,mob in ipairs(area.mobs or {})do keep.mobs[mob.file]=true end
            end
        end
        return keep,hidden
    end
    -- This preflight releases irrelevant private caches before the shared
    -- streamer loads new actors. It never loads art or changes campaign facts.
    function view.prepareAssetRetention(options)
        retentionOptions=options or {}
        local keep=assetPlan();expedition.retainAssets(keep);return keep
    end
    function view.prepare()
        local keep,hidden=assetPlan();expedition.retainAssets(keep)
        local scene=runtime.scene
        if scene=='stop' or scene=='house' then view.ensureStopLayout()
        elseif scene=='expedition' then
            local data=runtime.saveData; local area=assert(Areas.current(data),'unknown guest expedition')
            assert(areas.state(data,area.id),'guest scene is missing the host expedition')
            if not runtime.battle and not hidden then expedition.ensureAssets(area)end
        elseif scene=='caravan' then assert(campState(),'guest scene is missing the host caravan')
        elseif scene~='train' then return nil,'scene_not_supported' end
        if runtime.battle and not hidden then
            local mobs={};for file in pairs(keep.mobs)do mobs[#mobs+1]={file=file}end
            table.sort(mobs,function(a,b)return a.file<b.file end)
            expedition.ensureAssets({mobs=mobs},{background=false,mobs=keep.mobs})
        end
        return true
    end
    view.drawExpedition=expedition.draw
    view.presentFieldAttack=expedition.presentAttack
    view.updatePresentation=expedition.updatePresentation
    view.drawExpeditionTrailhead=expedition.drawTrailhead
    view.release=expedition.release
    return view
end
return View
