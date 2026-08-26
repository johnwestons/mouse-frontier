local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"screen flow requires "..name)
  if expected then assert(type(value)==expected,"screen flow "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","screen flow requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local screens=required(context,"screens","table")
  local Intro=required(context,"intro","table")
  local scenery=required(context,"scenery","table")
  local colors=required(context,"colors","table")
  local updateBattle=required(context,"updateBattle","function")
  local drawBattle=required(context,"drawBattle","function")
  local drawEnding=required(context,"drawEnding","function")
  local drawGameplay=required(context,"drawGameplay","function")
  local installed=false
  local routeCount=0

  local function passiveUpdate() return true end

  local function install()
      if installed then return false end
      local routes={
          {"intro",{
              update=function(dt)
                  if Intro.update(ui.introCinematic,dt) then runtime.state="slots" end
                  return true
              end,
              draw=function(windowWidth,windowHeight)
                  return Intro.draw(ui.introCinematic,scenery,colors,windowWidth,windowHeight)
              end,
          }},
          {"slots",{update=passiveUpdate,draw=function(...) return ui.drawSlots(...) end}},
          {"characters",{update=passiveUpdate,draw=function(...) return ui.drawCharacterSelect(...) end}},
          {"battle",{update=updateBattle,draw=drawBattle}},
          {"event",{update=passiveUpdate,draw=function(...) return ui.drawRandomEvent(...) end}},
          {"ending",{update=passiveUpdate,draw=drawEnding}},
          {"game",{
              update=function() return false end,
              draw=function()
                  if runtime.travelConfirm then return ui.drawTravelConfirm() end
                  return drawGameplay()
              end,
          }},
      }
      for _,route in ipairs(routes) do screens:register(route[1],route[2]) end
      routeCount=#routes
      installed=true
      return true
  end

  local function isInstalled() return installed end
  local function count() return routeCount end

  return {install=install,isInstalled=isInstalled,count=count}
end

return {new=new}
