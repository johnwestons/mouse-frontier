local ScreenManager = {}
ScreenManager.__index = ScreenManager

function ScreenManager.new(session)
    assert(session,"ScreenManager requires a GameSession")
    return setmetatable({session=session,current=session.screen,handlers={},previous=nil},ScreenManager)
end

function ScreenManager:register(name,handlers)
    assert(type(name)=="string" and name~="","screen name is required")
    local target=self.handlers[name] or {}
    for key,value in pairs(handlers or {}) do target[key]=value end
    self.handlers[name]=target
    return target
end

function ScreenManager:is(name)
    return self.current==name
end

function ScreenManager:transition(name,payload)
    assert(self.handlers[name],"unregistered screen: "..tostring(name))
    if name==self.current then
        self.session:setScreen(name)
        return false
    end
    local previous=self.current
    local leaving=self.handlers[previous]
    if leaving and leaving.leave then leaving.leave(name,payload) end
    self.previous=previous
    self.current=name
    self.session:setScreen(name)
    local entering=self.handlers[name]
    if entering and entering.enter then entering.enter(previous,payload) end
    return true
end

function ScreenManager:dispatch(method,...)
    local screen=self.handlers[self.current]
    local handler=screen and screen[method]
    if not handler then return false end
    return handler(...)
end

function ScreenManager:update(dt)
    return self:dispatch("update",dt)
end

function ScreenManager:draw(...)
    return self:dispatch("draw",...)
end

function ScreenManager:snapshot()
    return {current=self.current,previous=self.previous,sessionScreen=self.session.screen}
end

return ScreenManager
