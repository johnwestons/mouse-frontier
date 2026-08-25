local Config = require("game.config")

function love.conf(t)
    t.identity = Config.identity
    t.version = "11.5"
    t.externalstorage = false
    t.accelerometerjoystick = false
    t.window.title = Config.title
    t.window.width = Config.baseWidth
    t.window.height = Config.baseHeight
    t.window.resizable = true
    t.window.minwidth = Config.minimumWidth
    t.window.minheight = Config.minimumHeight
    -- Modules such as love.system are not loaded yet while love.conf runs.
    -- love._os is the platform value exposed by LÖVE during configuration.
    if love._os == "Android" then
        t.window.resizable = false
        t.window.fullscreen = true
        t.window.fullscreentype = "desktop"
    end
end
