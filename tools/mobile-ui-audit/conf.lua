function love.conf(t)
    local mobile=os.getenv("MOUSE_FRONTIER_MOBILE")=="1"
    t.identity=mobile and "mouse-frontier-mobile-ui-audit" or "mouse-frontier-desktop-ui-audit"
    t.version="11.5"
    t.window.title="Mouse Frontier Mobile UI Audit"
    t.window.width=mobile and 2340 or 1280
    t.window.height=mobile and 1080 or 720
    t.window.resizable=false
    t.window.vsync=0
end
