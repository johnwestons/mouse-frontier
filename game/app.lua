if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
  love.errorhandler=function(message)
    io.stderr:write("LOVE_ERROR: "..tostring(message).."\n"..debug.traceback().."\n"); io.stderr:flush()
    return function() os.exit(1) end
  end
end

local application=require("game.application_composition").new({engine=love})
local App={}

function App.load(...) return application.load(...) end
function App.update(...) return application.update(...) end
function App.draw(...) return application.draw(...) end
function App.mousepressed(...) return application.mousepressed(...) end
function App.mousemoved(...) return application.mousemoved(...) end
function App.mousereleased(...) return application.mousereleased(...) end
function App.wheelmoved(...) return application.wheelmoved(...) end
function App.keypressed(...) return application.keypressed(...) end
function App.keyreleased(...) return application.keyreleased(...) end
function App.textinput(...) return application.textinput(...) end
function App.touchpressed(...) return application.touchpressed(...) end
function App.touchmoved(...) return application.touchmoved(...) end
function App.touchreleased(...) return application.touchreleased(...) end
function App.focus(...) return application.focus(...) end
function App.installSmoke(...) return application.installSmoke(...) end
function App.quit(...) return application.quit(...) end

return App
