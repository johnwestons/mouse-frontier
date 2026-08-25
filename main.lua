local app = require("game.app")

function love.load() return app.load() end
function love.update(dt) return app.update(dt) end
function love.draw() return app.draw() end
function love.mousepressed(x,y,button,istouch,presses) return app.mousepressed(x,y,button,istouch,presses) end
function love.mousemoved(x,y,dx,dy,istouch) return app.mousemoved(x,y,dx,dy,istouch) end
function love.mousereleased(x,y,button,istouch,presses) return app.mousereleased(x,y,button,istouch,presses) end
function love.wheelmoved(x,y) return app.wheelmoved(x,y) end
function love.keypressed(key,scancode,isrepeat) return app.keypressed(key,scancode,isrepeat) end
function love.keyreleased(key,scancode) return app.keyreleased(key,scancode) end
function love.touchpressed(id,x,y,dx,dy,pressure) return app.touchpressed(id,x,y,dx,dy,pressure) end
function love.touchmoved(id,x,y,dx,dy,pressure) return app.touchmoved(id,x,y,dx,dy,pressure) end
function love.touchreleased(id,x,y,dx,dy,pressure) return app.touchreleased(id,x,y,dx,dy,pressure) end
function love.focus(focused) return app.focus(focused) end
function love.quit() return app.quit() end

-- Smoke instrumentation wraps the installed callbacks, so it must run only
-- after this lifecycle shell is complete.
app.installSmoke()
