local GameSession = {}
local Items = require("game.item_instances")
local CoopPlayers = require("game.coop_players")
local CoopEntities = require("game.coop_entities")
GameSession.__index = GameSession

function GameSession.new()
    return setmetatable({
        screen="intro",
        selectedSlot=nil,
        saveData=nil,
        player=nil,
        scene="train",
        networkMode="offline",
        localPlayerId=CoopPlayers.HOST,
    },GameSession)
end

function GameSession:setNetworkMode(mode,localPlayerId)
    assert(mode=="offline" or mode=="host" or mode=="client","invalid session mode")
    local expected=mode=="client" and CoopPlayers.COMPANION or CoopPlayers.HOST
    assert(localPlayerId==nil or localPlayerId==expected,"invalid local player identity")
    self.networkMode,self.localPlayerId=mode,expected
end

function GameSession:canWriteCampaign()
    return self.networkMode=="offline" or self.networkMode=="host"
end

local function scope(session,scene)
    local data=session.saveData
    if not data then return nil end
    -- A saved event remains the campaign surface on title screens too.
    -- Focus/quit can save there; a UI change must not stale its saved epoch.
    local screen=data.tacticalBattle and 'battle' or data.events and data.events.current and 'event' or session.screen or 'game'
    return table.concat({scene or session.scene or "train",tostring(data.location),
        tostring(data.activeHouseDoor),tostring(data.activeExpeditionArea),
        tostring(data.crowCaravans and data.crowCaravans.activeCampId),screen},"|")
end

function GameSession:syncSceneEpoch(scene)
    if not self:canWriteCampaign() or not self.saveData then return false end
    local current=scope(self,scene)
    local changed=self.campaignScope~=nil and self.campaignScope~=current
    if changed and self.saveData.coop then
        assert(self.saveData.coop.sceneEpoch<2147483647,"scene epoch exhausted")
        self.saveData.coop.sceneEpoch=self.saveData.coop.sceneEpoch+1
        if self.saveData.conversations then self.saveData.conversations.active=nil end
    end
    self.campaignScope=current
    return changed
end

function GameSession:character(id)
    return CoopPlayers.get(self.saveData,id or self.localPlayerId)
end

function GameSession:acceptPartyState(result)
    assert(self:canWriteCampaign() and result.sceneEpoch==self.saveData.coop.sceneEpoch,"invalid party commit")
    assert(result.scene==self.saveData.scene,"party scene mismatch")
    self.scene=result.scene; self.screen=result.screen
    local actor=CoopPlayers.get(self.saveData,self.localPlayerId)
    if self.player and actor then
        self.player.x,self.player.y=actor.playerX,actor.playerY
        self.player.velocityX,self.player.velocityY=0,0; self.player.moving=false
    end
    -- The transaction already advanced the epoch. Presentation must not do it
    -- again through setScene/setScreen's legacy-change detector.
    self.campaignScope=scope(self)
end

function GameSession:actorData(id)
    return CoopPlayers.forActor(self.saveData,id or self.localPlayerId)
end

function GameSession:setScreen(screen)
    self.screen=screen
    self:syncSceneEpoch()
    return screen
end

function GameSession:selectSlot(slot)
    self.selectedSlot=slot
    return slot
end

function GameSession:setSaveData(data)
    self.saveData=data
    self.campaignScope=scope(self,data and data.scene)
    return data
end

function GameSession:setPlayer(player)
    self.player=player
    return player
end

function GameSession:setScene(scene)
    self.scene=scene or "train"
    self:syncSceneEpoch()
    if self.saveData and self:canWriteCampaign() then self.saveData.scene=self.scene end
    return self.scene
end

function GameSession:activate(data,player)
    self.saveData=data
    self.player=player
    self.scene=(data and data.scene) or "train"
    self.screen=data and data.events and data.events.current and 'event'
        or data and data.location>=50 and not (data.coop and data.coop.journey) and 'ending' or 'game'
    self.campaignScope=scope(self)
    -- A paid final leg must finish its arrival checkpoint after reload before
    -- the ending screen takes over the update loop.
    return self.screen
end

function GameSession:sync(screen,slot,data,player,scene)
    if self.saveData~=data then self.campaignScope=nil end
    self.screen=screen or self.screen
    self.selectedSlot=slot
    self.saveData=data
    self.player=player
    self.scene=scene or self.scene
    self:syncSceneEpoch()
    if self.saveData and self:canWriteCampaign() then
        self.saveData.scene=self.scene
        if self.player then
            self.saveData.playerX,self.saveData.playerY=self.player.x,self.player.y
        end
    end
    return self
end

function GameSession:scheduleSave(saveModule)
    if not self:canWriteCampaign() or not self.selectedSlot or not self.saveData then return false end
    local identified=CoopEntities.ensure(self.saveData)
    if not identified then return false end
    if Items.enabled(self.saveData) and not Items.ensure(self.saveData) then return false end
    return saveModule.schedule(self.selectedSlot,self.saveData)==true
end

function GameSession:snapshot()
    return {screen=self.screen,selectedSlot=self.selectedSlot,saveData=self.saveData,player=self.player,scene=self.scene}
end

return GameSession
