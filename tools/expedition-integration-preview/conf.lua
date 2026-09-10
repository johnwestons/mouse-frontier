function love.conf(t)
    t.identity="mouse-frontier-expedition-integration-qa"
    t.version="11.5"
    t.window.title="Mouse Frontier Expedition Integration QA"
    t.window.width=os.getenv("MOUSE_FRONTIER_MOBILE")=="1" and 1280 or 960
    t.window.height=720
    t.window.resizable=false
    t.window.vsync=0
end
