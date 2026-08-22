local GameSession = {}
GameSession.__index = GameSession

function GameSession.new()
    return setmetatable({
        screen="intro",
        selectedSlot=nil,
        saveData=nil,
        player=nil,
        scene="train"
    },GameSession)
end

function GameSession:setScreen(screen)
    self.screen=screen
    return screen
end

function GameSession:selectSlot(slot)
    self.selectedSlot=slot
    return slot
end

function GameSession:setSaveData(data)
    self.saveData=data
    return data
end

function GameSession:setPlayer(player)
    self.player=player
    return player
end

function GameSession:setScene(scene)
    self.scene=scene or "train"
    if self.saveData then self.saveData.scene=self.scene end
    return self.scene
end

function GameSession:activate(data,player)
    self.saveData=data
    self.player=player
    self.scene=(data and data.scene) or "train"
    return data and data.location>=50 and "ending" or "game"
end

function GameSession:sync(screen,slot,data,player,scene)
    self.screen=screen or self.screen
    self.selectedSlot=slot
    self.saveData=data
    self.player=player
    self.scene=scene or self.scene
    if self.saveData then
        self.saveData.scene=self.scene
        if self.player then
            self.saveData.playerX,self.saveData.playerY=self.player.x,self.player.y
        end
    end
    return self
end

function GameSession:scheduleSave(saveModule)
    if not self.selectedSlot or not self.saveData then return false end
    saveModule.schedule(self.selectedSlot,self.saveData)
    return true
end

function GameSession:snapshot()
    return {screen=self.screen,selectedSlot=self.selectedSlot,saveData=self.saveData,player=self.player,scene=self.scene}
end

return GameSession
