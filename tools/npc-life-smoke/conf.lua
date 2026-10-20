function love.conf(t)
    t.identity='mouse-frontier-npc-life-qa'
    t.version='11.5'
    t.window.title='Mouse Frontier resident routine smoke'
    t.window.width=os.getenv('MOUSE_FRONTIER_MOBILE')=='1' and 1280 or 960
    t.window.height=720
    t.window.vsync=0
end
