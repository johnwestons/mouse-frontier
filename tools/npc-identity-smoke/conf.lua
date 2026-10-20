function love.conf(t)
    t.identity='mouse-frontier-npc-identity-smoke'
    t.window.title='Mouse Frontier named NPC validation'
    t.window.width=tonumber(os.getenv('MOUSE_FRONTIER_SMOKE_WIDTH')) or 1280
    t.window.height=tonumber(os.getenv('MOUSE_FRONTIER_SMOKE_HEIGHT')) or 720
    t.console=true
end
