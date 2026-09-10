function love.load()
    local ok,message=xpcall(function()
        require("game.character_motion_self_test").run()
    end,debug.traceback)
    if not ok then io.stderr:write(message.."\n"); io.stderr:flush() end
    love.event.quit(ok and 0 or 1)
end
