local RuntimeState = {}

local SESSION_FIELDS = {
    state = "screen",
    selectedSlot = "selectedSlot",
    saveData = "saveData",
    player = "player",
    scene = "scene",
}

local TRANSIENT_DEFAULTS = {
    actionTimer = 0,
    battleZoom = 1,
    characterScroll = 0,
    chestOpen = false,
    editDragging = false,
    editMode = false,
    giftOpen = false,
    holdPickupTime = 0,
    inventoryDragActive = false,
    inventoryOpen = false,
    mapOpen = false,
    mapScroll = 0,
    playerPose = "idle",
    poseMenu = false,
    tradeOpen = false,
    trainUpgradeOpen = false,
    travelConfirm = false,
}

local function readSessionField(self, key)
    local sessionField = SESSION_FIELDS[key]
    if sessionField then return self.session[sessionField] end
end

RuntimeState.__index = function(self, key)
    local method = RuntimeState[key]
    if method then return method end
    return readSessionField(self, key)
end

RuntimeState.__newindex = function(self, key, value)
    if key == "state" then
        self.transition(value)
    elseif key == "selectedSlot" then
        self.session:selectSlot(value)
    elseif key == "saveData" then
        self.session:setSaveData(value)
    elseif key == "player" then
        self.session:setPlayer(value)
    elseif key == "scene" then
        self.session:setScene(value)
    else
        rawset(self, key, value)
    end
end

function RuntimeState.new(options)
    options = options or {}
    assert(options.session, "RuntimeState requires a GameSession")
    assert(type(options.transition) == "function", "RuntimeState requires a screen transition function")
    local instance={
        session = options.session,
        transition = options.transition,
    }
    for key,value in pairs(TRANSIENT_DEFAULTS) do instance[key]=value end
    return setmetatable(instance, RuntimeState)
end

function RuntimeState:activate(data, player)
    local target = self.session:activate(data, player)
    self.transition(target)
    return target
end

function RuntimeState:syncForSave()
    return self.session:sync(
        self.state,
        self.selectedSlot,
        self.saveData,
        self.player,
        self.scene
    )
end

function RuntimeState:resetForGameEntry()
    self.inventoryOpen=false
    self.mapOpen=false
    self.dialogue=nil
    self.editMode=false
    self.chestOpen=false
    self.activeChest=nil
    self.carTransition=nil
end

function RuntimeState:snapshot()
    local snapshot = self.session:snapshot()
    snapshot.state = snapshot.screen
    return snapshot
end

function RuntimeState:isSynchronized(screenManager)
    return self.state == self.session.screen
        and (not screenManager or screenManager.current == self.state)
end

return RuntimeState
