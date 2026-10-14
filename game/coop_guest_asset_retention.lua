-- Guest presentation bypasses the ordinary gameplay update's asset cleanup.
-- Keep decisions use checked campaign facts and private panels; no save/world
-- fields are changed to imitate Source screen modes.
local Assets=require('game.assets')
local Events=require('game.coop_events')
local Life=require('game.coop_last_stand_lifecycle')
local Retention={};Retention.__index=Retention
local function opened(panel)return panel and panel.opened==true or false end
local function available(panel)return panel and panel.available and panel:available() or false end
function Retention.plan(view)
    local runtime=view.runtime;local data=runtime.saveData
    local stand=view.lastStand
    local shooting=available(view.range) or available(view.ambush) or stand and available(stand.shooter) or false
    local keep={battle=runtime.battle~=nil or data and data.tacticalBattle~=nil or false,
        event=data and Events.readAlong(data)~=nil or false,
        firstAid=opened(view.activities and view.activities.firstAid) or opened(stand and stand.aid),
        shootingRange=shooting,caravan=runtime.scene=='caravan' and runtime.state=='game'}
    -- Ordinary scenes and tactical BattleUI all draw the global landscape.
    -- Only the first-person/modal special views bypass those renderers.
    local hideBackground=shooting
        or data and Life.active(data)~=nil or false
    return keep,hideBackground,runtime.state=='intro'
end
function Retention.new(content)
    return setmetatable({content=assert(content)},Retention)
end
function Retention:update(view)
    local runtime=view.runtime;if not runtime.saveData then return end
    local keep,hideBackground,intro=Retention.plan(view)
    local signature=table.concat({runtime.state,runtime.scene,tostring(keep.battle),tostring(keep.event),
        tostring(keep.firstAid),tostring(keep.shootingRange),tostring(keep.caravan),tostring(hideBackground),tostring(intro)},'|')
    if signature==self.signature then return end
    self.signature=signature
    if not intro then Assets.releaseIntroImages(self.content.scenery)end
    Assets.releaseDormantSceneArt(self.content.scenery,runtime,keep)
    if hideBackground and self.content.backgroundImages and self.content.backgroundImages.release then
        self.content.backgroundImages:release()
    end
end
return Retention
