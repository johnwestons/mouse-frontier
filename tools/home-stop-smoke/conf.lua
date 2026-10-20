function love.conf(t)
    t.identity="mouse-frontier-home-stop-smoke"
    t.window.title="Mouse Frontier home stop validation"
    t.window.width=tonumber(os.getenv("MOUSE_FRONTIER_SMOKE_WIDTH")) or 1560
    t.window.height=tonumber(os.getenv("MOUSE_FRONTIER_SMOKE_HEIGHT")) or 720
    t.window.resizable=false
    t.window.visible=false
    t.window.vsync=0
    t.console=true
end
