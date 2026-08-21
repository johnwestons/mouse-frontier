-- Deterministic, callback-driven gameplay smoke tester.
-- The controller deliberately knows nothing about the game state.  main.lua
-- supplies hooks, which makes this module safe to use with local game values.
local SmokeController = {}
SmokeController.__index = SmokeController

local function now()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return os.clock()
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    return out
end

local function path(value, key)
    for part in tostring(key):gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function equal(a, b, epsilon)
    if type(a) == "number" and type(b) == "number" and epsilon then
        return math.abs(a - b) <= epsilon
    end
    return a == b
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return true, fn end
    local args = {...}
    return xpcall(function() return fn(unpack(args)) end, debug.traceback)
end

function SmokeController.new(options)
    options = options or {}
    local self = setmetatable({}, SmokeController)
    self.hooks = options.hooks or {}
    self.steps = options.steps or {}
    self.timeout = options.timeout or options.stepTimeout or 5
    self.name = options.name or "mouse-frontier-smoke"
    self.reportPath = options.reportPath or "smoke.rpt"
    self.clock = options.clock or now
    self.autoStart = options.autoStart ~= false
    self.running, self.finished, self.failed = false, false, false
    self.index, self.elapsed, self.startedAt = 0, 0, nil
    self.results, self.errors, self.events = {}, {}, {}
    if self.autoStart then self:start() end
    return self
end

function SmokeController:start()
    self.running, self.finished, self.failed = true, false, false
    self.index, self.elapsed, self.startedAt = 0, 0, self.clock()
    self.results, self.errors, self.events = {}, {}, {}
    return self
end

function SmokeController:stop(reason)
    if self.running then self:_fail(reason or "stopped") end
    return self
end

function SmokeController:_log(kind, message, extra)
    local event = {time = self.clock(), kind = kind, message = tostring(message)}
    if extra then event.data = copy(extra) end
    self.events[#self.events + 1] = event
    return event
end

function SmokeController:_fail(message)
    self.failed, self.running, self.finished = true, false, true
    self.errors[#self.errors + 1] = tostring(message)
    self:_log("error", message)
end

function SmokeController:_begin(step)
    self.elapsed = 0
    self.current = {step = step, started = self.clock(), actionDone = false, result = nil}
    self:_log("step_start", step.name or ("step-" .. self.index))
    local ok, result = safeCall(step.before or step.onStart, self, step)
    if not ok then self:_fail("before " .. tostring(step.name) .. ": " .. tostring(result)); return end
    local action = step.action or step.run
    if not action and self.hooks.action then action = function(ctx) return self.hooks.action(ctx, step) end end
    if action then
        ok, result = safeCall(action, self, step)
        if not ok then self:_fail("action " .. tostring(step.name) .. ": " .. tostring(result)); return end
        self.current.result, self.current.actionDone = result, result ~= false
    else
        self.current.actionDone = true
    end
end

function SmokeController:_snapshot(step)
    local source = step.snapshot or self.hooks.snapshot
    if not source then return nil, true end
    local ok, value = safeCall(source, self, step)
    if not ok then return nil, false, value end
    return value, true
end

function SmokeController:_check(step, snapshot)
    local check = step.check or step.assert or step.validate
    if check then
        local ok, result = safeCall(check, self, step, snapshot, self.current.result)
        if not ok then return false, "check " .. tostring(step.name) .. ": " .. tostring(result) end
        if result == false then return false end
        if type(result) == "string" then return false, result end
    end
    local expected = step.expect or step.expected
    if expected and type(snapshot) == "table" then
        for key, want in pairs(expected) do
            local got = path(snapshot, key)
            local pass = type(want) == "function" and want(got, snapshot) or equal(got, want, step.epsilon)
            if not pass then return false, "expected " .. tostring(key) .. "=" .. tostring(want) .. ", got " .. tostring(got) end
        end
    end
    return true
end

function SmokeController:_complete(step, snapshot)
    local record = {name = step.name or ("step-" .. self.index), ok = true,
        elapsed = self.elapsed, value = copy(self.current.result), state = copy(snapshot)}
    self.results[#self.results + 1] = record
    self:_log("step_ok", record.name, record)
    local ok, err = safeCall(step.after or step.onComplete, self, step, record)
    if not ok then self:_fail("after " .. record.name .. ": " .. tostring(err)); return end
    self.current = nil
    if self.index >= #self.steps then
        self.running, self.finished = false, true
        self:_log("complete", self.name)
    end
end

function SmokeController:update(dt)
    if not self.running then return self:getStatus() end
    dt = tonumber(dt) or 0
    if self.index == 0 then self.index = 1; self:_begin(self.steps[self.index]) end
    if self.finished then return self:getStatus() end
    local step, current = self.steps[self.index], self.current
    self.elapsed = self.elapsed + math.max(0, dt)
    if not current.actionDone then
        local action = step.action or step.run
        local ok, result = safeCall(action, self, step)
        if not ok then self:_fail("action " .. tostring(step.name) .. ": " .. tostring(result)); return self:getStatus() end
        current.result = result
        current.actionDone = result ~= false
    end
    local snapshot, ok, err = self:_snapshot(step)
    if not ok then self:_fail("snapshot " .. tostring(step.name) .. ": " .. tostring(err)); return self:getStatus() end
    local pass, message = self:_check(step, snapshot)
    if pass and current.actionDone then self:_complete(step, snapshot)
    elseif message then self:_log("check_wait", message)
    end
    local limit = step.timeout or self.timeout
    if self.running and self.current == nil then
        self.index = self.index + 1
        if self.index <= #self.steps then self:_begin(self.steps[self.index]) end
    elseif self.running and self.elapsed > limit then
        self:_fail("timeout in " .. tostring(step.name) .. " after " .. tostring(self.elapsed) .. "s")
    end
    return self:getStatus()
end

function SmokeController:getStatus()
    return {name = self.name, running = self.running, finished = self.finished,
        failed = self.failed, index = self.index, total = #self.steps,
        current = self.current and (self.current.step.name or self.index) or nil,
        elapsed = self.elapsed, passed = #self.results, errors = #self.errors}
end

function SmokeController:getSummary()
    return {status = self:getStatus(), results = copy(self.results), errors = copy(self.errors), events = copy(self.events)}
end

function SmokeController:report()
    local s = self:getSummary(); local out = {"MOUSE_FRONTIER_SMOKE_REPORT v1", "name=" .. self.name,
        "status=" .. (s.status.failed and "FAIL" or (s.status.finished and "PASS" or "RUNNING")),
        "passed=" .. tostring(s.status.passed), "failed=" .. tostring(s.status.errors)}
    for i, item in ipairs(s.results) do out[#out + 1] = string.format("STEP %d %s %.3f", i, item.ok and "OK" or "FAIL", item.elapsed or 0) end
    for _, err in ipairs(s.errors) do out[#out + 1] = "ERROR " .. tostring(err) end
    return table.concat(out, "\n") .. "\n"
end

function SmokeController:writeReport(filename)
    filename = filename or self.reportPath
    local data = self:report()
    if love and love.filesystem and love.filesystem.write then return love.filesystem.write(filename, data) end
    local file, err = io.open(filename, "w"); if not file then return false, err end
    file:write(data); file:close(); return true
end

return SmokeController
