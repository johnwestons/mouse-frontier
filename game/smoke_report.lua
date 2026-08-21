-- Smoke-test report writer.
--
-- The module deliberately has no dependency on the game state.  It can be used
-- from a LÖVE callback (where love.filesystem is the safe writable filesystem)
-- or from a small standalone Lua harness.
local Report = {}
Report.__index = Report
local unpackArgs = table.unpack or unpack

local function text(value)
    if value == nil then return "nil" end
    local ok, result = pcall(tostring, value)
    return ok and result or "<unprintable>"
end

local function oneLine(value)
    return text(value):gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function clock()
    if love and love.timer and love.timer.getTime then
        local ok, result = pcall(love.timer.getTime)
        if ok then return result end
    end
    return os.clock()
end

local function stamp()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- A bounded, cycle-safe value formatter.  It is intentionally diagnostic
-- rather than Lua-source serialization: functions/userdata are represented
-- safely and tables cannot make a report recurse forever.
local function describe(value, seen, depth)
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return text(value) end
    if kind == "function" or kind == "thread" or kind == "userdata" then
        return "<" .. kind .. ":" .. oneLine(value) .. ">"
    end
    depth = depth or 0
    if depth >= 3 then return "{...}" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local parts = {}
    for key, item in pairs(value) do
        if #parts >= 40 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = "[" .. describe(key, seen, depth + 1) .. "]=" .. describe(item, seen, depth + 1)
    end
    seen[value] = nil
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function traceback(message, level)
    if debug and debug.traceback then
        return debug.traceback(text(message), (level or 1) + 1)
    end
    return text(message)
end

function Report.new(options)
    options = options or {}
    local self = setmetatable({
        path = options.path or "smoke-test.rpt",
        append = options.append == true,
        flushEvery = tonumber(options.flushEvery) or 1,
        lines = {},
        startedAt = clock(),
        runId = options.runId or os.date("!%Y%m%dT%H%M%SZ"),
        counts = {steps = 0, checkpoints = 0, values = 0, warnings = 0, errors = 0},
        closed = false,
        _writes = 0,
        _initialized = options.append == true
    }, Report)
    self:_line("MOUSE FRONTIER SMOKE REPORT")
    self:_line("run_id=" .. oneLine(self.runId) .. " started=" .. stamp())
    if options.metadata then self:metadata(options.metadata) end
    return self
end

function Report:_line(line)
    if not self.closed then self.lines[#self.lines + 1] = "[" .. stamp() .. "] " .. line end
end

function Report:metadata(values)
    if type(values) ~= "table" then return self:value("metadata", values) end
    for key, value in pairs(values) do self:_line("META " .. oneLine(key) .. "=" .. describe(value)) end
    return self
end

function Report:step(name, status, details)
    self.counts.steps = self.counts.steps + 1
    self:_line("STEP " .. oneLine(name) .. " status=" .. oneLine(status or "started") .. (details and " details=" .. describe(details) or ""))
    return self
end

function Report:checkpoint(name, passed, details)
    self.counts.checkpoints = self.counts.checkpoints + 1
    self:_line("CHECKPOINT " .. oneLine(name) .. " result=" .. (passed and "PASS" or "FAIL") .. (details and " details=" .. describe(details) or ""))
    return self
end

function Report:value(name, value, context)
    self.counts.values = self.counts.values + 1
    self:_line("VALUE " .. oneLine(name) .. " type=" .. type(value) .. " value=" .. describe(value) .. (context and " context=" .. describe(context) or ""))
    return self
end

function Report:warning(message, context)
    self.counts.warnings = self.counts.warnings + 1
    self:_line("WARNING " .. oneLine(message) .. (context and " context=" .. describe(context) or "") .. "\nTRACEBACK " .. traceback(message, 2))
    return self
end

function Report:error(message, context)
    self.counts.errors = self.counts.errors + 1
    local detail = context and " context=" .. describe(context) or ""
    self:_line("ERROR " .. oneLine(message) .. detail .. "\nTRACEBACK " .. traceback(message, 2))
    return self
end

function Report:run(name, callback, ...)
    local args = {...}
    self:step(name, "started")
    local function invoke() return callback(unpackArgs(args)) end
    local ok, a, b, c = xpcall(invoke, function(err) return traceback(err, 3) end)
    if ok then
        self:step(name, "passed")
        self:value(name .. ".return", {a, b, c})
        return true, a, b, c
    end
    self:error(name .. ": " .. text(a))
    self:step(name, "failed")
    return false, a
end

function Report:summary()
    local c = self.counts
    return "steps=" .. c.steps .. " checkpoints=" .. c.checkpoints .. " values=" .. c.values .. " warnings=" .. c.warnings .. " errors=" .. c.errors
end

function Report:flush()
    if self.closed or #self.lines == 0 then return true end
    local payload = table.concat(self.lines, "\n") .. "\n"
    local ok, result
    local absolute = self.path:match("^%a:[/\\]") or self.path:match("^[/\\][/\\]") or self.path:sub(1, 1) == "/"
    if love and love.filesystem and love.filesystem.write and not absolute then
        if self._initialized and love.filesystem.append then
            ok, result = pcall(love.filesystem.append, self.path, payload)
        else
            ok, result = pcall(love.filesystem.write, self.path, payload)
        end
    else
        local file
        ok, file = pcall(io.open, self.path, self._initialized and "a" or "w")
        if ok and file then file:write(payload); file:close(); result = true else ok, result = false, file end
    end
    if ok and result then self.lines = {}; self._writes = self._writes + 1; self._initialized = true; return true end
    return false, text(result)
end

function Report:finish(status)
    if self.closed then return true end
    self:_line("SUMMARY status=" .. oneLine(status or (self.counts.errors > 0 and "failed" or "passed")) .. " " .. self:summary() .. " duration=" .. string.format("%.3f", clock() - self.startedAt))
    local ok, err = self:flush()
    if ok then self.closed = true end
    return ok, err
end

Report.start = Report.new
Report.record = Report.value
Report.warn = Report.warning
Report.fail = Report.error
Report.close = Report.finish

return Report
