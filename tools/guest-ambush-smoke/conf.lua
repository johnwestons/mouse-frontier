function love.conf(t)
    t.identity='mouse-frontier-guest-ambush-'..(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE') or 'fixture')
    t.window.width=1120; t.window.height=840; t.window.visible=false; t.window.vsync=0
end
