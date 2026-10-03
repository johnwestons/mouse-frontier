local WorldView=require("game.world_view")
local Accessibility=require("game.accessibility")
local Typography=require("game.typography")
local WideLayout=require("game.wide_layout")
local UIStyle=require("game.ui_layout")
local LootProgression=require("game.loot_progression")
local RepairArt=require("game.repair_workbench_art")
local RepairLayout=require("game.repair_workbench_layout")
local OutfitArt=require("game.outfit_sprite_art")

local function required(context, name, expectedType)
  local value=context[name]
  assert(value~=nil,"screen UI requires "..name)
  if expectedType then assert(type(value)==expectedType,"screen UI "..name.." must be a "..expectedType) end
  return value
end

local function new(context)
  assert(type(context)=="table","screen UI requires an explicit context")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local ui=required(context,"ui","table")
  local colors=required(context,"colors","table")
  local scenery=required(context,"scenery","table")
  local characters=required(context,"characters","table")
  local characterImages=required(context,"characterImages","table")
  local npcImages=required(context,"npcImages","table")
  local readSave=required(context,"readSave","function")
  local Util=required(context,"util","table")
  local Catalog=required(context,"catalog","table")
  local Inventory=required(context,"inventory","table")
  local EventUI=required(context,"eventUI","table")
  local canChooseEvent=required(context,"canChooseEvent","function")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local PlayerProgression=required(context,"playerProgression","table")
  local StopHelpProgression=required(context,"stopHelpProgression","table")
  local NpcRelationships=required(context,"npcRelationships","table")
  local MerchantTrade=required(context,"merchantTrade","table")
  local FinaleProgression=required(context,"finaleProgression","table")
  local Maintenance=required(context,"maintenance","table")
  local writeSave=required(context,"writeSave","function")
  local screenToGame=required(context,"screenToGame","function")
  local ensureStopLayout=required(context,"ensureStopLayout","function")
  local currentTradeSource=required(context,"currentTradeSource","function")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local drawLandscape=required(context,"drawLandscape","function")
  local drawTracks=required(context,"drawTracks","function")
  local drawLocomotive=required(context,"drawLocomotive","function")
  local drawTrainCar=required(context,"drawTrainCar","function")
  local drawAnimatedCharacter=required(context,"drawAnimatedCharacter","function")
  local getCharacterAnimations=required(context,"getCharacterAnimations","function")
  local isWeapon=required(context,"isWeapon","function")
  local travelCost=required(context,"travelCost","function")
  local repairStatus=required(context,"repairStatus","function")
  local questSummary=required(context,"questSummary","function")

  local function drawMenuFrame(x,y,w,h,kind,alpha)
      kind=UIStyle.frame(kind or 1)
      local frame=ui.menuFrames and ui.menuFrames[kind]
      if frame then
          love.graphics.setColor(1,1,1,alpha or 1)
          local sw,sh=frame.w,frame.h; local sx=math.floor(sw*.22); local sy=math.floor(sh*.28)
          local dx=math.min(kind==4 and 11 or 16,math.floor(w/4)); local dy=math.min(kind==4 and 8 or 14,math.floor(h/4))
          local xs={0,sx,sw-sx,sw}; local ys={0,sy,sh-sy,sh}; local xd={x,x+dx,x+w-dx,x+w}; local yd={y,y+dy,y+h-dy,y+h}
          for row=1,3 do for col=1,3 do local qw,qh=xs[col+1]-xs[col],ys[row+1]-ys[row]; local dw,dh=xd[col+1]-xd[col],yd[row+1]-yd[row]; if qw>0 and qh>0 and dw>0 and dh>0 then love.graphics.draw(frame.image,frame.quads[row][col],xd[col],yd[row],0,dw/qw,dh/qh) end end end
      else love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,y,w,h,8,8) end
      if runtime.saveData and Accessibility.enabled(runtime.saveData,"highContrast") then
          love.graphics.setColor(1,.84,.28,1); love.graphics.setLineWidth(3); love.graphics.rectangle("line",x,y,w,h,8,8); love.graphics.setLineWidth(1)
      end
  end

  local function textBox(text,x,y,w,h,scale,align,minimum)
      return Typography.drawText(love.graphics,text,x,y,w,h,{scale=(scale or 1)*(runtime.saveData and Accessibility.textScale(runtime.saveData) or 1),
          minScale=minimum or (mobileEnabled() and .75 or .65),align=align or "left",valign="center"})
  end

  local function journeyHudBounds()
      local windowWidth,windowHeight=love.graphics.getDimensions()
      local layout=WideLayout.measure(W,H,windowWidth,windowHeight)
      if layout.sidePanels and runtime.scene~="train" and runtime.scene~="expedition" then
          return {x=layout.leftX,y=18,w=layout.panelWidth,h=462}
      end
      if mobileEnabled() then
          local viewportScale=math.min(windowWidth/W,windowHeight/H)
          local visibleWidth=windowWidth/viewportScale
          local left=(W-visibleWidth)/2+20
          return {x=left,y=18,w=visibleWidth-40,h=179}
      end
      return {x=10,y=58,w=715,h=169}
  end

  function ui.drawJourneyHUD()
      return UIStyle.scope("journeyHud",journeyHudBounds(),function()
      local windowWidth,windowHeight=love.graphics.getDimensions()
      local layout=WideLayout.measure(W,H,windowWidth,windowHeight)
      ui.sideHudLayout=layout.sidePanels and runtime.scene~="train" and layout or nil
      if ui.sideHudLayout then
          local data=runtime.saveData
          local progression=PlayerProgression.status(data)
          local condition=Maintenance.status(data)
          local goodwill=StopHelpProgression.status(data)
          local x,width=layout.leftX,layout.panelWidth
          love.graphics.push("all"); love.graphics.origin()
          love.graphics.translate((windowWidth-W*math.min(windowWidth/W,windowHeight/H))/2,
              (windowHeight-H*math.min(windowWidth/W,windowHeight/H))/2)
          local viewportScale=math.min(windowWidth/W,windowHeight/H)
          love.graphics.scale(viewportScale,viewportScale)
          UIStyle.scope("resourceHud",{x=x,y=18,w=width,h=222},function()
              for index,spec in ipairs({{"FOOD","food",colors.green},{"WATER","water",colors.blue},{"COAL","coal",colors.red},{"OIL","oil",colors.brass}}) do
                  local capacity=spec[2]=="oil" and Maintenance.oilCapacity(data) or TrainUpgradeBalance.resourceCapacity(data,spec[2])
                  ui.drawResource(spec[1],data.resources[spec[2]],x,spec[3],width,capacity,18+(index-1)*57)
              end
          end)
          local cardY=250
          drawMenuFrame(x,cardY,width,230,4,.96)
          love.graphics.setColor(colors.cream)
          textBox("STOP "..data.location,x+10,cardY+7,width-20,24,.98)
          textBox(data.trait and data.trait.name or "Survivor",x+10,cardY+31,width-20,21,.76)
          textBox("HEALTH  "..data.health.." / "..data.maxHealth,x+10,cardY+57,width-20,23,.80)
          love.graphics.setColor(.28,.08,.06,1); love.graphics.rectangle("fill",x+10,cardY+83,width-20,6,2,2)
          love.graphics.setColor(.95,.26,.20,1); love.graphics.rectangle("fill",x+10,cardY+83,(width-20)*math.max(0,math.min(1,data.health/math.max(1,data.maxHealth))),6,2,2)
          love.graphics.setColor(colors.cream)
          textBox("LV "..progression.level.." / AB "..progression.abilityRank,x+10,cardY+96,width-20,21,.74)
          textBox(progression.maximum and "MAX LEVEL" or ("XP "..progression.xp.." / "..progression.nextXP),x+10,cardY+119,width-20,19,.72)
          textBox("GOODWILL "..goodwill.points,x+10,cardY+141,width-20,20,.76)
          textBox("TRAIN "..math.floor(condition.condition).."%",x+10,cardY+162,width-20,20,.72)
          textBox("CARS "..#(data.trainCars or {}),x+10,cardY+184,width-20,20,.72)
          local ammo={}
          for i=1,2 do
              local weapon=data.equipment[i]; local combat=weapon and Catalog.weaponCombat[weapon]
              if combat and combat.ammo then ammo[#ammo+1]=Util.titleFromFile(combat.ammo)..": "..(data.ammo[combat.ammo] or 0) end
          end
          if #ammo>0 then textBox(table.concat(ammo,"  "),x+10,cardY+207,width-20,20,.68) end
          ui.mobileHeaderBounds={x=x,y=18,w=width,h=462,resourceRight=x+width}
          love.graphics.pop()
          return
      end
      if mobileEnabled() then
          local data=runtime.saveData
          local progression=PlayerProgression.status(data)
          local condition=Maintenance.status(data)
          local goodwill=StopHelpProgression.status(data)
          local windowWidth,windowHeight=love.graphics.getDimensions()
          local viewportScale=math.min(windowWidth/W,windowHeight/H)
          local visibleWidth=windowWidth/viewportScale
          local left=(W-visibleWidth)/2+20
          local available=visibleWidth-40
          -- HUD uses the entire phone width and stays fixed while the world zooms.
          love.graphics.push("all"); love.graphics.origin()
          love.graphics.translate((windowWidth-W*viewportScale)/2,(windowHeight-H*viewportScale)/2)
          love.graphics.scale(viewportScale,viewportScale)
          local resourceWidth=(available-180-36)/4
          UIStyle.scope("resourceHud",{x=left,y=18,w=resourceWidth*4+36,h=61},function()
              for index,spec in ipairs({{"FOOD","food",colors.green},{"WATER","water",colors.blue},{"COAL","coal",colors.red},{"OIL","oil",colors.brass}}) do
                  local capacity=spec[2]=="oil" and Maintenance.oilCapacity(data) or TrainUpgradeBalance.resourceCapacity(data,spec[2])
                  ui.drawResource(spec[1],data.resources[spec[2]],left+(index-1)*(resourceWidth+12),spec[3],resourceWidth,capacity)
              end
          end)
          local column=(available-36)/4
          local x1,x2,x3,x4=left,left+column+12,left+2*(column+12),left+3*(column+12)
          for _,x in ipairs({x1,x2,x3,x4}) do drawMenuFrame(x,91,column,106,4,1) end
          love.graphics.setColor(colors.cream)
          textBox("STOP "..data.location,x1+16,102,column-32,36,1.35)
          textBox(data.trait and data.trait.name or "Survivor",x1+16,145,column-32,34,1.05)
          textBox("HEALTH",x2+16,101,column-32,26,.98)
          textBox(data.health.." / "..data.maxHealth,x2+16,131,column-32,34,1.35)
          love.graphics.setColor(.28,.08,.06,1); love.graphics.rectangle("fill",x2+16,176,column-32,7,2,2)
          love.graphics.setColor(.95,.26,.20,1); love.graphics.rectangle("fill",x2+16,176,(column-32)*math.max(0,math.min(1,data.health/math.max(1,data.maxHealth))),7,2,2)
          love.graphics.setColor(colors.cream)
          textBox("LEVEL "..progression.level.." / ABILITY "..progression.abilityRank,x3+16,100,column-32,28,1.02)
          textBox(progression.maximum and "MAX LEVEL" or ("XP "..progression.xp.." / "..progression.nextXP),x3+16,129,column-32,22,.92)
          textBox("GOODWILL "..goodwill.points.." / TRAIN "..math.floor(condition.condition).."%",x3+16,153,column-32,38,.98)
          local ammo={}
          for i=1,2 do
              local weapon=data.equipment[i]; local combat=weapon and Catalog.weaponCombat[weapon]
              if combat and combat.ammo then ammo[#ammo+1]=Util.titleFromFile(combat.ammo)..": "..(data.ammo[combat.ammo] or 0) end
          end
          love.graphics.setColor(colors.brass); textBox("AMMUNITION",x4+16,101,column-32,27,.98)
          love.graphics.setColor(colors.cream); textBox(#ammo>0 and table.concat(ammo,"\n") or "No ranged weapon",x4+16,134,column-32,52,1.10)
          ui.mobileHeaderBounds={x=left,y=18,w=available,h=179,resourceRight=left+4*resourceWidth+36}
          love.graphics.pop()
          return
      end
      local data=runtime.saveData
      local progression=PlayerProgression.status(data)
      local condition=Maintenance.status(data)
      local goodwill=StopHelpProgression.status(data)
      drawMenuFrame(10,58,410,142,4,1)
      love.graphics.setColor(colors.cream)
      textBox("STOP "..data.location,25,67,113,32,1.05)
      textBox(data.trait and data.trait.name or "Survivor",150,67,253,32,.85,"right")
      ui.drawHealthBar("HP",data.health,data.maxHealth,25,108,222)
      love.graphics.setColor(colors.cream)
      textBox("LEVEL "..progression.level,264,108,138,24,.8)
      textBox(progression.maximum and "MAX LEVEL" or ("XP "..progression.xp.."/"..progression.nextXP),264,137,138,24,.76)
      textBox("GOODWILL "..goodwill.points.." / TRAIN "..math.floor(condition.condition).."% / "..#(data.trainCars or {}).." CARS",25,169,378,24,.78,"center")
      local ammo={}
      for i=1,2 do
          local weapon=data.equipment[i]; local combat=weapon and Catalog.weaponCombat[weapon]
          if combat and combat.ammo then ammo[#ammo+1]=Util.titleFromFile(combat.ammo)..": "..(data.ammo[combat.ammo] or 0) end
      end
      if #ammo>0 then
          drawMenuFrame(500,150,225,77,4,1)
          love.graphics.setColor(colors.brass); textBox("AMMUNITION",516,157,193,22,.75)
          love.graphics.setColor(colors.cream); textBox(table.concat(ammo,"\n"),516,181,193,39,.78)
      end
      end)
  end

  local function button(text, x, y, w, h, active, textScale, opacity)
      opacity=runtime.saveData and Accessibility.enabled(runtime.saveData,"highContrast") and 1 or (opacity or 1)
      local highContrast=runtime.saveData and Accessibility.enabled(runtime.saveData,"highContrast")
      if highContrast then
          love.graphics.setColor(0,0,0,active and .98 or .82); love.graphics.rectangle("fill",x,y,w,h,8,8)
          love.graphics.setColor(active and 1 or .62,active and .84 or .62,active and .28 or .62,1); love.graphics.setLineWidth(active and 4 or 2); love.graphics.rectangle("line",x,y,w,h,8,8); love.graphics.setLineWidth(1)
      elseif ui.menuFrames and ui.menuFrames[4] then drawMenuFrame(x-3,y-3,w+6,h+6,4,(active and 1 or .55)*opacity) else love.graphics.setColor(active and colors.brass[1] or colors.panel[1],active and colors.brass[2] or colors.panel[2],active and colors.brass[3] or colors.panel[3],opacity); love.graphics.rectangle("fill", x, y, w, h, 8, 8) end
      local scale=(textScale or 1)*(runtime.saveData and Accessibility.textScale(runtime.saveData) or 1)
      if mobileEnabled() then scale=math.max(scale,.78) end
      scale=math.min(scale,mobileEnabled() and 1.18 or 1.22)
      love.graphics.setColor(colors.cream[1],colors.cream[2],colors.cream[3],opacity)
      local fitted,height,lines,fits=Typography.drawText(love.graphics,text,x+10,y+6,w-20,h-12,
          {scale=scale,minScale=mobileEnabled() and .75 or .60,align="center",valign="center"})
      return UIStyle.transformRect({x=x,y=y,w=w,h=h,textScale=fitted,textHeight=height,textLines=lines,textFits=fits})
  end

  local function requestExitPrompt(kind)
      runtime.exitPrompt=kind
      if ui.playSfx then ui.playSfx("menu") end
  end

  local function resolveExitPrompt(choice)
      local prompt=runtime.exitPrompt
      runtime.exitPrompt=nil
      if choice~="yes" then
          if runtime.returnEscAfterExitPrompt then
              runtime.returnEscAfterExitPrompt=nil
              ui.escMenuOpen=true
          end
          return
      end
      runtime.returnEscAfterExitPrompt=nil
      if prompt=="title" then
          if runtime.saveData then writeSave() end
          runtime.state="slots"
      elseif prompt=="quit" then
          love.event.quit()
      end
  end

  function ui.drawActionConfirmation()
      local request=runtime.pendingConfirmation
      if not request then ui.confirmYes=nil; ui.confirmNo=nil; return end
      love.graphics.setColor(0,0,0,.78)
      love.graphics.rectangle("fill",0,0,W,H)
      local mobile=mobileEnabled()
      local x,y,w,h=mobile and 120 or 205,mobile and 220 or 225,mobile and 720 or 550,mobile and 280 or 270
      return UIStyle.scope("confirmation",{x=x,y=y,w=w,h=h},function()
      drawMenuFrame(x,y,w,h,2,.99)
      local title="CONFIRM PURCHASE?"
      if request.kind=="deleteSave" then title="DELETE SAVE DATA?"
      elseif request.kind=="overwriteSave" then title="START A NEW JOURNEY?"
      elseif request.kind=="eventChoice" then title="CONFIRM RESPONSE?"
      elseif request.kind=="trainCar" then title="PURCHASE TRAIN CAR?" end
      love.graphics.setColor(colors.cream)
      textBox(title,x+30,y+25,w-60,44,mobile and 1.3 or 1.1,"center")
      love.graphics.setColor(colors.brass)
      love.graphics.rectangle("fill",x+44,y+79,w-88,3)
      love.graphics.setColor(colors.cream)
      local message=request.message or "Are you sure?"
      textBox(message,x+48,y+96,w-96,76,mobile and 1.02 or .88,"center")
      local buttonY=y+h-(mobile and 88 or 72)
      local buttonH=mobile and 62 or 46
      local gap=mobile and 24 or 18
      local buttonW=mobile and 245 or 190
      local total=buttonW*2+gap
      local startX=x+(w-total)/2
      ui.confirmYes=button(request.confirmLabel or (request.kind=="deleteSave" and "DELETE" or "CONFIRM"),
          startX,buttonY,buttonW,buttonH,true,mobile and .94 or .82)
      ui.confirmNo=button("CANCEL",startX+buttonW+gap,buttonY,buttonW,buttonH,true,mobile and .94 or .82)
      end)
  end

  local function drawExitPrompt()
      if not runtime.exitPrompt then return end
      love.graphics.setColor(0,0,0,.70)
      love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("exitPrompt",{x=270,y=252,w=420,h=196},function()
      drawMenuFrame(270,252,420,196,2,.99)
      love.graphics.setColor(colors.cream)
      local title=runtime.exitPrompt=="quit" and "Quit Game?" or "Return to Title Screen?"
      textBox(title,290,274,380,62,1.15,"center")
      love.graphics.setColor(colors.brass)
      love.graphics.rectangle("fill",315,340,330,2)
      local mobile=mobileEnabled()
      ui.exitYes=button("YES",mobile and 300 or 330,365,mobile and 160 or 115,mobile and 66 or 44,true,.92)
      ui.exitNo=button("NO",mobile and 500 or 515,365,mobile and 160 or 115,mobile and 66 or 44,true,.92)
      end)
  end

  function ui.drawEscapeMenu()
      if not ui.escMenuOpen then return end
      love.graphics.setColor(0,0,0,.68)
      love.graphics.rectangle("fill",0,0,W,H)
      local mobile=mobileEnabled()
      local panelX,panelY,panelW,panelH=mobile and 90 or 250,mobile and 82 or 142,mobile and 780 or 460,mobile and 550 or 436
      return UIStyle.scope("pauseMenu",{x=panelX,y=panelY,w=panelW,h=panelH},function()
      drawMenuFrame(panelX,panelY,panelW,panelH,2,.99)
      love.graphics.setColor(colors.cream)
      textBox("PAUSED",panelX+24,panelY+30,panelW-48,52,mobile and 1.5 or 1.25,"center")
      love.graphics.setColor(colors.brass)
      love.graphics.rectangle("fill",panelX+34,panelY+100,panelW-68,3)
      local buttonX=mobile and panelX+54 or panelX+50
      local buttonW=panelW-(mobile and 108 or 100)
      local buttonH=mobile and 76 or 54
      local gap=mobile and 18 or 16
      local firstY=panelY+(mobile and 128 or 124)
      ui.escMenuSelection=math.max(1,math.min(4,tonumber(ui.escMenuSelection) or 1))
      ui.escChoiceContinue=button("CONTINUE",buttonX,firstY,buttonW,buttonH,ui.escMenuSelection==1,mobile and 1.2 or .86)
      ui.escChoiceOptions=button("OPTIONS",buttonX,firstY+buttonH+gap,buttonW,buttonH,ui.escMenuSelection==2,mobile and 1.2 or .86)
      ui.escChoiceTitle=button("EXIT TO TITLE SCREEN",buttonX,firstY+(buttonH+gap)*2,buttonW,buttonH,ui.escMenuSelection==3,mobile and 1.1 or .82)
      ui.escChoiceQuit=button("EXIT GAME",buttonX,firstY+(buttonH+gap)*3,buttonW,buttonH,ui.escMenuSelection==4,mobile and 1.2 or .86)
      love.graphics.setColor(colors.cream)
      textBox("UP / DOWN  •  ENTER",panelX+24,panelY+panelH-36,panelW-48,24,.62,"center")
      end)
  end

  function ui.drawSlots()
      love.graphics.clear(0.09, 0.06, 0.04); love.graphics.setColor(colors.cream)
      return UIStyle.scope("slots",{x=0,y=0,w=W,h=H},function()
      if scenery.titleImage then
          local scale=math.min(540/scenery.titleImage:getWidth(),185/scenery.titleImage:getHeight())
          love.graphics.setColor(1,1,1)
          love.graphics.draw(scenery.titleImage,W/2,88,0,scale,scale,scenery.titleImage:getWidth()/2,scenery.titleImage:getHeight()/2)
      else
          textBox("MOUSE FRONTIER",0,82,W,48,2.2,"center")
      end
      love.graphics.setColor(colors.cream)
      textBox("CHOOSE A JOURNEY  •  ARROWS / WASD + ENTER",0,182,W,28,.82,"center")
      ui.slots, ui.slotNew, ui.slotDelete = {}, {}, {}
      local mobile=mobileEnabled()
      for i=1,3 do
          local data, y = readSave(i), (mobile and 215+(i-1)*150 or 225+(i-1)*125)
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill", mobile and 90 or 210, y, mobile and 780 or 540, mobile and 126 or 96, 12, 12)
          love.graphics.setColor(colors.cream); textBox("SAVE "..i,mobile and 114 or 232,y+15,mobile and 330 or 250,32,1.15)
          textBox(data and (Util.titleFromFile(data.character).."\nStop "..tostring(data.location or 1)) or "New journey",mobile and 114 or 232,y+52,mobile and 340 or 260,mobile and 60 or 40,mobile and .95 or .8)
          if data and mobile then
              ui.slots[i]=button("CONTINUE",485,y+31,175,64,true)
              ui.slotNew[i]=button("NEW",677,y+31,75,64,true)
              ui.slotDelete[i]=button("DELETE",765,y+31,88,64,true,.85)
          elseif data then
              ui.slots[i]=button("CONTINUE",500,y+16,105,32,true)
              ui.slotNew[i]=button("NEW",612,y+16,52,32,true)
              ui.slotDelete[i]=button("DELETE",671,y+16,65,32,true)
          else ui.slotNew[i]=button("NEW GAME",mobile and 555 or 585,y+(mobile and 31 or 25),mobile and 220 or 138,mobile and 64 or 46,true) end
      end
      end)
  end

  function ui.drawCharacterSelect()
      return UIStyle.scope("characters",{x=0,y=0,w=W,h=H},function()
      local mobile=mobileEnabled()
      love.graphics.clear(0.09, 0.06, 0.04); love.graphics.setColor(colors.cream)
      ui.characters = {}
      local columns=mobile and 4 or 5
      local rows=math.ceil(#characters/columns); local maxScroll=math.max(0,rows-3); ui.characterMaxScroll=maxScroll; runtime.characterScroll=math.max(0,math.min(maxScroll,runtime.characterScroll))
      local hoveredFile
      local mouseX,mouseY=screenToGame(love.mouse.getPosition())
      for i, file in ipairs(characters) do
          local col, row = (i-1)%columns, math.floor((i-1)/columns); local x, y = (mobile and 26 or 42)+col*(mobile and 216 or 182), 100+(row-runtime.characterScroll)*198
          local r={x=x,y=y,w=mobile and 194 or 150,h=180}; r.visible=y+r.h>94 and y<708
          local hitRect=UIStyle.transformRect(r); hitRect.visible=r.visible; ui.characters[i]=hitRect
          if r.visible then
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill", x,y,r.w,r.h,10,10)
          local img=characterImages[file]
          if img then local s=math.min(112/img:getWidth(),108/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,x+r.w/2,y+60,0,s,s,img:getWidth()/2,img:getHeight()/2) end
          local identity=Catalog.characterIdentity(file)
          love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(file),x+8,y+118,r.w-16,38,mobile and .92 or .72,"center")
          love.graphics.setColor(colors.brass); textBox(identity.role,x+8,y+158,r.w-16,20,mobile and .76 or .6,"center")
          local localMouseX,localMouseY=UIStyle.inversePoint(mouseX,mouseY,"characters",{x=0,y=0,w=W,h=H})
          if localMouseY>=94 and localMouseY<708 and Util.pointIn(localMouseX,localMouseY,r) then hoveredFile=file end
          end
      end
      love.graphics.setColor(0.09,0.06,0.04,1); love.graphics.rectangle("fill",0,0,W,94); love.graphics.rectangle("fill",0,708,W,H-708)
      love.graphics.setColor(colors.cream)
      textBox("CHOOSE YOUR TRAVELER",80,25,W-160,40,1.35,"center")
      textBox("Use arrows / WASD and Enter, or tap a traveler to read their profile.",80,67,W-160,27,.82,"center")
      if hoveredFile and not mobile then
          local lower=hoveredFile:lower()
          local trait=Catalog.characterTrait(hoveredFile)
          local abilityProfile=Catalog.characterAbility(hoveredFile)
          local ability,abilityDescription=abilityProfile.name,abilityProfile.description
          local tooltipW,tooltipH=265,142
          local tx,ty=mouseX+18,mouseY+18
          if tx+tooltipW>W then tx=mouseX-tooltipW-18 end
          if ty+tooltipH>H then ty=H-tooltipH-10 end
          love.graphics.setColor(.055,.04,.03,.97); love.graphics.rectangle("fill",tx,ty,tooltipW,tooltipH,8,8)
          love.graphics.setColor(colors.brass); love.graphics.rectangle("line",tx,ty,tooltipW,tooltipH,8,8)
          love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(hoveredFile),tx+12,ty+10,tooltipW-24,20,.88)
          love.graphics.setColor(colors.brass); textBox("ABILITY  "..ability,tx+12,ty+34,tooltipW-24,17,.65)
          love.graphics.setColor(colors.cream); textBox(abilityDescription,tx+12,ty+51,tooltipW-24,25,.62)
          love.graphics.setColor(colors.brass); textBox("TRAIT  "..trait.name,tx+12,ty+79,tooltipW-24,17,.65)
          love.graphics.setColor(colors.cream); textBox(trait.description,tx+12,ty+96,tooltipW-24,25,.58)
      end
      ui.characterUp=button("^",mobile and 888 or 905,110,mobile and 58 or 38,mobile and 70 or 42,runtime.characterScroll>0); ui.characterDown=button("v",mobile and 888 or 905,mobile and 565 or 590,mobile and 58 or 38,mobile and 70 or 42,runtime.characterScroll<maxScroll)
      love.graphics.setColor(colors.cream); textBox(tostring(math.floor(runtime.characterScroll)+1).."/"..(maxScroll+1),888,192,58,35,.78,"center")
      if runtime.characterPreviewFile then
          local file=runtime.characterPreviewFile; local identity=Catalog.characterIdentity(file)
          local animationSet=getCharacterAnimations()[file]
          local direction=runtime.characterPreviewDirection or "SE"
          local selectedAction=runtime.characterPreviewAction or "walk"
          local movementActions={"idle","walk"}
          if animationSet and animationSet.runDirectional and animationSet.run then movementActions[#movementActions+1]="run" end
          local actionLabels={sit="SIT",lay="LAY",use="USE",melee="MELEE",ranged="RANGE",hit="HIT",death="DEATH",unconscious="DOWN"}
          local poseActions={}
          for _,action in ipairs({"sit","lay","use","melee","ranged","hit","death","unconscious"}) do
              if animationSet and animationSet[action] then poseActions[#poseActions+1]=action end
          end
          local actionAvailable=false
          for _,action in ipairs(movementActions) do if action==selectedAction then actionAvailable=true end end
          for _,action in ipairs(poseActions) do if action==selectedAction then actionAvailable=true end end
          if not actionAvailable then selectedAction="walk"; runtime.characterPreviewAction=selectedAction end
          local directionVectors={
              NW={x=-1,y=-1},N={x=0,y=-1},NE={x=1,y=-1},W={x=-1,y=0},
              E={x=1,y=0},SW={x=-1,y=1},S={x=0,y=1},SE={x=1,y=1},
          }
          local eightWay=(selectedAction=="idle" or selectedAction=="walk" or selectedAction=="run")
              and animationSet and animationSet.directional
          if not eightWay and direction~="W" and direction~="E" then
              direction="E"; runtime.characterPreviewDirection=direction
          end
          ui.characterMovementActions={}
          ui.characterPoseActions={}
          ui.characterDirections={}
          love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,W,H)
          drawMenuFrame(185,115,590,500,1,1)
          love.graphics.setColor(colors.cream); textBox("TRAVELER PROFILE",205,136,550,38,1.15,"center")
          love.graphics.setColor(colors.brass); textBox("ANIMATION",205,172,220,18,.60,"center")
          local movementX,movementY,movementW,movementH,gap=205,193,220,34,5
          local movementButtonW=(movementW-gap*(#movementActions-1))/#movementActions
          for index,action in ipairs(movementActions) do
              local control=button(action:upper(),movementX+(index-1)*(movementButtonW+gap),movementY,movementButtonW,movementH,
                  selectedAction==action,.64)
              ui.characterMovementActions[#ui.characterMovementActions+1]={id=action,control=control}
          end
          love.graphics.setColor(colors.brass); textBox(eightWay and "WALK DIRECTION" or "FACING",205,235,112,19,.54,"center")
          local directionGrid={
              {{"NW",1,1},{"N",2,1},{"NE",3,1}},
              {{"W",1,2},{"CENTER",2,2},{"E",3,2}},
              {{"SW",1,3},{"S",2,3},{"SE",3,3}},
          }
          local directionX,directionY,cell,step=205,256,32,34
          for _,row in ipairs(directionGrid) do
              for _,entry in ipairs(row) do
                  local id,column,line=entry[1],entry[2],entry[3]
                  local x,y=directionX+(column-1)*step,directionY+(line-1)*step
                  if id=="CENTER" then
                      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,y,cell,cell,6,6)
                      love.graphics.setColor(colors.brass); love.graphics.rectangle("line",x,y,cell,cell,6,6)
                      love.graphics.setColor(colors.cream); textBox(direction,x,y,cell,cell,.48,"center")
                  else
                      local enabled=eightWay or id=="W" or id=="E"
                      local control=button(id,x,y,cell,cell,enabled and direction==id,.52,enabled and 1 or .42)
                      control.id=id; control.active=enabled
                      ui.characterDirections[id]=control
                  end
              end
          end
          local directionVector=directionVectors[direction] or directionVectors.SE
          local animationDistance=(animationSet and animationSet.motionProfile and animationSet.motionProfile.pixelsPerFrame or 20)
              *runtime.animationClock*5.2
          local motion={intentX=directionVector.x,intentY=directionVector.y,animationDistance=animationDistance,
              locomotionMode=selectedAction=="run" and "run" or "walk"}
          local previewAction=selectedAction=="run" and "walk" or selectedAction
          love.graphics.setColor(0,0,0,.22); love.graphics.ellipse("fill",365,397,42,7)
          local animated=drawAnimatedCharacter(file,previewAction,365,391,180,190,
              directionVector.x<0 and -1 or 1,runtime.animationClock,motion)
          if not animated then
              local img=characterImages[file]
              if img then local s=math.min(180/img:getWidth(),190/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,365,323,0,s,s,img:getWidth()/2,img:getHeight()/2) end
          end
          love.graphics.setColor(colors.brass); textBox("POSE / ACTION",205,406,220,19,.58,"center")
          local poseX,poseY,poseW,poseH,poseGap=205,426,52,30,3
          for index,action in ipairs(poseActions) do
              local column=(index-1)%4; local row=math.floor((index-1)/4)
              local control=button(actionLabels[action] or action:upper(),poseX+column*(poseW+poseGap),poseY+row*(poseH+4),poseW,poseH,
                  selectedAction==action,.58)
              ui.characterPoseActions[#ui.characterPoseActions+1]={id=action,control=control}
          end
          love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(file),435,188,310,44,1.05)
          love.graphics.setColor(colors.brass); textBox("ROLE: "..identity.role,435,236,310,27,.78)
          textBox("TRAIT: "..identity.trait.name,435,268,310,27,.8)
          love.graphics.setColor(colors.cream); textBox(identity.trait.description,435,297,310,52,.8)
          love.graphics.setColor(colors.brass); textBox("ABILITY: "..identity.ability.name,435,358,310,27,.8)
          love.graphics.setColor(colors.cream); textBox(identity.ability.description,435,390,310,59,.8)
          textBox("Your chosen traveler becomes the player. The others can be met along the journey.",220,493,525,38,.8,"center")
          ui.characterConfirm=button("CHOOSE THIS TRAVELER",mobile and 260 or 275,540,mobile and 280 or 250,mobile and 64 or 48,true,.78)
          ui.characterCancel=button("BACK",mobile and 565 or 555,540,mobile and 135 or 130,mobile and 64 or 48,true,.82)
      else
          ui.characterConfirm=nil; ui.characterCancel=nil
          ui.characterMovementActions={}; ui.characterPoseActions={}; ui.characterDirections={}
      end
      end)
  end


  local resourceIconKeys={FOOD="food",WATER="water",COAL="coal",OIL="oil"}
  local function drawResourceIcon(name,x,y,size)
      local variant=UIStyle.iconVariant()
      local image=ui.resourceIcons and ui.resourceIcons[variant~="default" and variant or resourceIconKeys[name]]
      if not image then return false end
      local imageWidth,imageHeight=image:getDimensions()
      size=size*UIStyle.iconScale()
      local scale=size/math.max(imageWidth,imageHeight)
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(image,x+(size-imageWidth*scale)/2,y+(size-imageHeight*scale)/2,0,scale,scale)
      return true
  end

  function ui.drawResource(name, value, x, color, width, capacity, y)
      width=width or 150
      capacity=capacity or 20
      if ui.sideHudLayout then
          y=y or 18
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,y,width,51,7,7)
          drawResourceIcon(name,x+9,y+3,24)
          love.graphics.setColor(colors.cream)
          textBox(value.." / "..capacity,x+width*.48,y+3,width*.52-10,26,.84,"right")
          love.graphics.setColor(color); love.graphics.rectangle("fill",x+9,y+39,(width-18)*math.max(0,math.min(1,value/capacity)),5,2,2)
          return
      end
      if mobileEnabled() then
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,18,width,61,7,7)
          drawResourceIcon(name,x+12,24,27)
          love.graphics.setColor(colors.cream)
          textBox(value.." / "..capacity,x+width*.45,25,width*.55-12,35,1.15,"right")
          love.graphics.setColor(color); love.graphics.rectangle("fill",x+12,68,(width-24)*math.max(0,math.min(1,value/capacity)),5,2,2)
          return
      end
      local barWidth=math.max(20,width-60)
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,20,width,34,7,7)
      drawResourceIcon(name,x+7,25,24)
      love.graphics.setColor(color); love.graphics.rectangle("fill",x+32,29,math.max(0,math.min(barWidth,value*barWidth/capacity)),16,4,4)
          love.graphics.setColor(colors.cream); textBox(value.."/"..capacity,x+34,28,width-40,22,.78)
  end

  function ui.drawHealthBar(label,value,maxValue,x,y,w)
      love.graphics.setColor(.055,.035,.025,1); love.graphics.rectangle("fill",x,y,w,39,5,5)
      love.graphics.setColor(colors.cream); textBox(label.." "..value.." / "..maxValue,x+8,y+2,w-16,26,.92)
      love.graphics.setColor(.28,.08,.06,1); love.graphics.rectangle("fill",x+8,y+31,w-16,5,2,2)
      love.graphics.setColor(.95,.26,.20,1); love.graphics.rectangle("fill",x+8,y+31,(w-16)*math.max(0,math.min(1,value/math.max(1,maxValue))),5,2,2)
  end

  local function drawTrade()
      local source=currentTradeSource()
      if not source then runtime.tradeOpen=false; runtime.tradeNPC=nil; runtime.tradeMerchantId=nil; runtime.tradeMessage=nil; runtime.tradeBuyPage=0; runtime.tradeSellPage=0; return end
      love.graphics.setColor(0,0,0,.86); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("trade",{x=60,y=42,w=840,h=640},function()
      local merchant=source.relationshipId or source.merchant or runtime.tradeNPC or runtime.saveData.currentNPC
      local terms=MerchantTrade.terms(runtime.saveData,source)
      local availableBudget=MerchantTrade.availableBudget(runtime.saveData,source)
      do
          drawMenuFrame(60,42,840,640,1,1)
          love.graphics.setColor(colors.cream); textBox(source.title or Util.titleFromFile(merchant).."'S TRADING POST",85,59,790,45,1.2,"center")
          textBox("YOUR SCRAP "..runtime.saveData.scrap.." / MERCHANT BUDGET "..math.max(0,availableBudget),85,108,790,27,.9,"center")
          love.graphics.setColor(colors.brass); textBox(runtime.tradeMessage or (terms.tier.." terms / "..math.floor(terms.discount*100+.5).."% buying discount"),85,139,790,32,.82,"center")
          local stockIndices,occupied={},{}
          for index in pairs(source.stock or {}) do if type(index)=="number" and MerchantTrade.stockItem(source,index) then stockIndices[#stockIndices+1]=index end end
          table.sort(stockIndices)
          for index=1,(runtime.saveData.inventoryCapacity or 6) do
              local item=runtime.saveData.inventory[index]
              if item and not (Catalog.repairParts and Catalog.repairParts[item]) then occupied[#occupied+1]=index end
          end
          local buyPages=math.max(0,math.ceil(#stockIndices/3)-1)
          local sellPages=math.max(0,math.ceil(#occupied/3)-1)
          runtime.tradeBuyPage=math.max(0,math.min(buyPages,runtime.tradeBuyPage or 0))
          runtime.tradeSellPage=math.max(0,math.min(sellPages,runtime.tradeSellPage or 0))
          ui.tradeBuy,ui.tradeSell,ui.tradeGive={},{},{}
          textBox("FOR SALE",90,177,350,26,.95)
          textBox("YOUR ITEMS",490,177,375,26,.95)
          for row=0,2 do
              local y=210+row*116
              local index=stockIndices[runtime.tradeBuyPage*3+row+1]
              if index then
                  local name,entry=MerchantTrade.stockItem(source,index)
                  local price=MerchantTrade.buyPrice(runtime.saveData,Catalog,source,index)
                  local enabled,target=MerchantTrade.canBuy(runtime.saveData,Catalog,source,index)
                  ui.drawItem(name,{x=90,y=y,w=54,h=54})
                  love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(name)..((tonumber(entry and entry.quantity) or 1)>1 and (" x"..entry.quantity) or ""),154,y,290,43,.85)
                  ui.tradeBuy[index]=button(target=="train" and "SEND" or "BUY",154,y+49,130,56,enabled,.95)
                  ui.tradeBuy[index].enabled=enabled
                  love.graphics.setColor(colors.cream); textBox(price.." SCRAP",297,y+49,150,56,.9,"center")
              end
              local ownedIndex=occupied[runtime.tradeSellPage*3+row+1]
              local name=ownedIndex and runtime.saveData.inventory[ownedIndex]
              if name then
                  ui.drawItem(name,{x=490,y=y,w=54,h=54})
                  love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(name),556,y,306,43,.85)
                  local price=MerchantTrade.sellPrice(runtime.saveData,Catalog,source,ownedIndex)
                  local gift=isWeapon(name) and source.allowGifts
                  ui.tradeSell[ownedIndex]=button("SELL +"..price,556,y+49,gift and 143 or 306,56,availableBudget>=price,.95)
                  ui.tradeSell[ownedIndex].enabled=availableBudget>=price
                  if gift then ui.tradeGive[ownedIndex]=button("GIVE",716,y+49,146,56,true,.95) end
              end
          end
          ui.tradeBuyPrev=button("<",90,559,65,52,runtime.tradeBuyPage>0)
          ui.tradeBuyNext=button(">",382,559,65,52,runtime.tradeBuyPage<buyPages)
          ui.tradePrev=button("<",490,559,65,52,runtime.tradeSellPage>0)
          ui.tradeNext=button(">",797,559,65,52,runtime.tradeSellPage<sellPages)
          ui.tradeBuyPrev.enabled=runtime.tradeBuyPage>0; ui.tradeBuyNext.enabled=runtime.tradeBuyPage<buyPages
          ui.tradePrev.enabled=runtime.tradeSellPage>0; ui.tradeNext.enabled=runtime.tradeSellPage<sellPages
          love.graphics.setColor(colors.cream)
          textBox((runtime.tradeBuyPage+1).." / "..(buyPages+1),170,559,196,52,.95,"center")
          textBox((runtime.tradeSellPage+1).." / "..(sellPages+1),570,559,212,52,.95,"center")
          ui.tradeClose=button("DONE TRADING",340,622,280,48,true,.95)
          return
      end
      end)
  end

  function ui.drawMap()
      love.graphics.setColor(0.05,0.035,0.02,0.78); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("map",{x=70,y=75,w=820,h=570},function()
      love.graphics.setColor(0.76,0.59,0.34); love.graphics.rectangle("fill",70,75,820,570,18,18)
      love.graphics.setColor(0.66,0.47,0.27)
      for y=95,625,20 do for x=90+(y%37),870,43 do love.graphics.rectangle("fill",x,y,3,2) end end
      love.graphics.setColor(0.49,0.31,0.18); love.graphics.setLineWidth(8); love.graphics.rectangle("line",70,75,820,570,18,18)
      love.graphics.setColor(0.22,0.13,0.065); textBox("THE MOUSE FRONTIER TRAIL",100,90,640,50,1.25,"center")
      if mobileEnabled() then
          -- The mobile HUD is hidden while an overlay is open, so keep the map
          -- dismiss control on the map itself where it remains reachable.
          ui.map=button("CLOSE MAP",746,82,128,50,true,.72)
      end
      local visited=math.max(1,runtime.saveData.location); local points={}; local biomes={"Desert","Wetland","Canyon","Ruins","Badlands","Forest","Old City","River","Deep Woods","Pale City","Autumn Wood","Wastes"}
      local maxScroll=math.max(0,math.floor((visited-1)/6)-2); runtime.mapScroll=math.max(0,math.min(maxScroll,runtime.mapScroll))
      for i=1,visited do
          local col=(i-1)%6; local row=math.floor((i-1)/6)
          local px=145+col*132; if row%2==1 then px=805-col*132 end
          local py=215+(row-runtime.mapScroll)*155+math.sin(i*1.73)*42
          points[#points+1]={px,py}
      end
      -- Revealed terrain sketches around every visited stop.
      for i,p in ipairs(points) do if p[2]>175 and p[2]<535 then
          local kind=((i-1)%4)+1; love.graphics.setColor(0.42,0.34,0.20,0.9)
          if kind==1 then for k=-2,2 do love.graphics.polygon("fill",p[1]+k*15,p[2]-35,p[1]+k*15-8,p[2]-20,p[1]+k*15+8,p[2]-20) end
          elseif kind==2 then love.graphics.setLineWidth(4); love.graphics.arc("line","open",p[1],p[2]-22,35,0.1,3.0)
          elseif kind==3 then for k=-2,2 do love.graphics.line(p[1]+k*13,p[2]-42,p[1]+k*13,p[2]-24); love.graphics.circle("fill",p[1]+k*13,p[2]-45,6) end
          else love.graphics.rectangle("line",p[1]-28,p[2]-53,55,27); love.graphics.polygon("fill",p[1]-32,p[2]-53,p[1],p[2]-72,p[1]+32,p[2]-53) end
      end end
      local current=points[#points]
      if current and current[2]>175 and current[2]<535 and scenery.redTrain then
          local s=72/scenery.redTrain:getWidth(); love.graphics.setColor(1,1,1)
          love.graphics.draw(scenery.redTrain,current[1]+36,current[2]-64,0,-s,s)
      end
      -- Dotted, winding path instead of straight route segments.
      love.graphics.setColor(0.61,0.16,0.12)
      for i=2,#points do local a,b=points[i-1],points[i]; if (a[2]>160 and a[2]<550) or (b[2]>160 and b[2]<550) then for step=0,12 do if step%2==0 then local t=step/12; local bend=math.sin(t*math.pi)*((i%2==0) and 22 or -22); local x=a[1]+(b[1]-a[1])*t; local y=a[2]+(b[2]-a[2])*t+bend; love.graphics.circle("fill",x,y,4) end end end end
      for i,p in ipairs(points) do if p[2]>175 and p[2]<535 then
          love.graphics.setColor(i==#points and colors.red or colors.cream); love.graphics.circle("fill",p[1],p[2],i==#points and 13 or 9)
          love.graphics.setColor(colors.ink); textBox(tostring(i),p[1]-14,p[2]-7,28,14,.72,"center")
          love.graphics.setColor(0.22,0.13,0.065); textBox(biomes[((i-1)%#biomes)+1],p[1]-58,p[2]+16,116,37,.84,"center")
      end end
      local enc=runtime.saveData.encounters[tostring(runtime.saveData.location)]; local status=not enc and "Unexplored stop" or (enc.hasMob and not enc.resolved and "Danger nearby" or (enc.hasMob and "Mob cleared" or "Peaceful stop"))
      love.graphics.setColor(0.39,0.25,0.14,0.92); love.graphics.rectangle("fill",105,548,750,78,8,8)
      love.graphics.setColor(colors.cream); textBox("STOP "..runtime.saveData.location.." / "..biomes[((runtime.saveData.location-1)%#biomes)+1].." / "..status,120,552,720,29,.88,"center")
      local quests=questSummary()
      local questLine=quests.count>0 and ("ACTIVE: "..quests.first..(quests.count>1 and ("  +"..(quests.count-1).." more") or "")) or "No active deliveries or passengers."
      textBox(questLine,120,582,720,38,.8,"center")
      local mobile=mobileEnabled()
      ui.mapUp=button("^",mobile and 790 or 805,105,mobile and 68 or 42,mobile and 64 or 36,runtime.mapScroll>0); ui.mapDown=button("v",mobile and 790 or 805,mobile and 181 or 155,mobile and 68 or 42,mobile and 64 or 36,runtime.mapScroll<maxScroll)
      love.graphics.setColor(colors.ink); textBox((runtime.mapScroll+1).."/"..(maxScroll+1),790,250,68,30,.85,"center")
      love.graphics.setLineWidth(1)
      end)
  end

  function ui.drawDialogue()
      if not runtime.dialogue then return end
      return UIStyle.scope("dialogue",{x=80,y=45,w=800,h=630},function()
      ui.dialogueContinue=nil
      local textScale=Accessibility.textScale(runtime.saveData)
      if runtime.helpDialogue then
          local view=runtime.helpDialogue; local mobile=mobileEnabled(); local x,y,w,h=145,66,670,590
          drawMenuFrame(x-6,y-6,w+12,h+12,1,1)
          love.graphics.setColor(colors.brass); textBox(view.title or "HELP A CRITTER",x+24,y+18,w-48,43,1.2,"center")
          local subtitle=view.authored and (runtime.dialogue.speaker or "") or ("OBJECTIVE: "..(view.objective or "Listen and choose a thoughtful response."))
          love.graphics.setColor(colors.cream); textBox(subtitle,x+35,y+66,w-70,37,.85,"center")
          love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",x+45,y+104,w-90,3)
          love.graphics.setColor(colors.cream)
          local bodyScale=math.min(1.02,.82*textScale)
          textBox(view.text or runtime.dialogue.text,x+48,y+120,w-96,177,.98)
          ui.helpDialogueChoices={}
          local buttonHeight=mobile and 62 or 48; local gap=mobile and 12 or 10; local startY=y+318
          for index,choice in ipairs(view.choices or {}) do
              local label=index.."  •  "..choice.label
              ui.helpDialogueChoices[index]=button(label,x+45,startY+(index-1)*(buttonHeight+gap),w-90,buttonHeight,choice.enabled~=false,mobile and .76 or .72)
          end
          ui.helpDialoguePause=button("CONTINUE LATER",x+185,y+h-55,300,mobile and 48 or 36,true,.9)
          if not mobile then love.graphics.setColor(colors.cream); textBox("ARROWS / TAB TO NAVIGATE  •  ENTER OR 1-3 TO CHOOSE",x+45,y+h-83,w-90,22,.68,"center") end
          ui.questAccept,ui.questDecline=nil,nil
          return
      end
      ui.helpDialogueChoices,ui.helpDialoguePause=nil,nil
      local mobile=mobileEnabled()
      local x,y,w=mobile and 110 or 170,mobile and 225 or 115,mobile and 740 or 620
      local bodyScale=(mobile and 1 or .95)*textScale
      local displayText=runtime.dialogue.text..(runtime.dialogue.notice and ("\n\n"..runtime.dialogue.notice) or "")
      local _,wrapped=love.graphics.getFont():getWrap(displayText,(w-48)/bodyScale)
      local h=math.min(mobile and 330 or 360,math.max(158,78+#wrapped*love.graphics.getFont():getHeight()*love.graphics.getFont():getLineHeight()*bodyScale))
      drawMenuFrame(x-6,y-6,w+12,h+12,1,1)
      love.graphics.setColor(colors.brass); textBox(runtime.dialogue.speaker or "Traveler",x+24,y+13,w-48,36,1.1)
      love.graphics.setColor(colors.cream); textBox(displayText,x+24,y+61,w-48,h-77,mobile and 1 or .95)
      if runtime.dialogue.choice and runtime.questOffer then
          local agreeing=runtime.questOffer.kind=="trade" and "TRADE" or "ACCEPT"
          local declining="DECLINE"
          local buttonWidth=(w-60)/2
          ui.questAccept=button(agreeing,x+20,y+h+15,buttonWidth,mobile and 64 or 48,true)
          ui.questDecline=button(declining,x+40+buttonWidth,y+h+15,buttonWidth,mobile and 64 or 48,true)
      else
          ui.questAccept=nil; ui.questDecline=nil
          ui.dialogueContinue=button("CONTINUE",x+w-154,y+h+12,130,mobile and 54 or 38,true,.78)
      end
      end)
  end

  function ui.drawTravelConfirm()
      -- The gameplay renderer already drew the fitted train and its contents.
      love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("travelConfirm",{x=140,y=142,w=680,h=456},function()
      drawMenuFrame(140,142,680,456,1,1)
      local cost=travelCost(); love.graphics.setColor(colors.cream); textBox("TRAVEL TO STOP "..(runtime.saveData.location+1),170,169,620,46,1.3,"center")
      textBox("Distance, terrain, passengers and train condition shape the cost of this journey.",178,229,604,56,.95,"center")
      love.graphics.setColor(colors.brass); textBox(cost.food.." FOOD / "..cost.water.." WATER / "..cost.coal.." COAL",178,301,604,42,1.15,"center")
      local terrain=TrainUpgradeBalance.revealsTerrain(runtime.saveData) and string.upper(cost.terrain or "plains") or "UNCHARTED — NAVIGATOR REQUIRED"
      if (cost.navigatorSaved or 0)>0 then terrain=terrain.."  •  SAVES 1 COAL" end
      love.graphics.setColor(colors.cream); textBox("TERRAIN: "..terrain,178,356,604,45,.9,"center")
      if cost.passengers>0 then textBox(cost.passengers.." passengers add "..cost.passengerLoad.." food and water.",178,408,604,31,.85,"center") end
      if cost.maintenanceCoal>0 then love.graphics.setColor(.98,.57,.43); textBox("LOW MAINTENANCE ADDS +"..cost.maintenanceCoal.." COAL",178,447,604,31,.85,"center") end
      local enough=runtime.saveData.resources.food>=cost.food and runtime.saveData.resources.water>=cost.water and runtime.saveData.resources.coal>=cost.coal
      local mobile=mobileEnabled()
      ui.travelYes=button(enough and "CONFIRM JOURNEY" or "NOT ENOUGH SUPPLIES",175,505,365,68,enough)
      ui.travelNo=button("CANCEL",565,505,220,68,true)
      ui.travelYes.enabled=enough
      end)
  end

  function ui.drawRandomEvent()
      WorldView.begin(); drawLandscape(); WorldView.finish(); love.graphics.setColor(0,0,0,0.76); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("event",{x=60,y=42,w=840,h=640},function()
          ui.eventChoices=EventUI.draw(runtime.randomEvent,scenery.eventArt,drawMenuFrame,button,colors,runtime.saveData.eventProgress or {},canChooseEvent)
      end)
  end

  local function ownsTrainCar(id) return TrainUpgradeBalance.owns(runtime.saveData,id) end

  local repairPanelBounds={x=150,y=70,w=660,h=580}

  local function ownedRepairWeapons()
      return LootProgression.ownedWeapons(runtime.saveData,Catalog)
  end

  local repairColors={ink={.20,.12,.07},muted={.40,.30,.20},brass={.46,.26,.10},green={.17,.34,.18},red={.61,.18,.12}}

  local function repairButton(label,rect,enabled,selected)
      OutfitArt.draw(not enabled and "button-disabled" or selected and "button-selected" or "button",rect,{stretch=true})
      love.graphics.setColor(colors.cream)
      textBox(label,rect.x+9,rect.y+5,rect.w-18,rect.h-10,.78,"center")
      local result=UIStyle.transformRect({x=rect.x,y=rect.y,w=rect.w,h=rect.h})
      result.enabled=enabled
      return result
  end

  local function drawWeaponRepairWorkbench()
      local data=runtime.saveData
      local names=ownedRepairWeapons()
      local selected=runtime.weaponRepairSelected
      local previousSelected=selected
      local selectedIndex
      for index,name in ipairs(names) do if name==selected then selectedIndex=index; break end end
      if not selectedIndex and #names>0 then
          selectedIndex=1; selected=names[1]; runtime.weaponRepairSelected=selected
      elseif not selectedIndex then
          selected=nil; runtime.weaponRepairSelected=false
      end
      if selected~=previousSelected or (runtime.weaponRepairStartedAt and runtime.weaponRepairActiveWeapon~=selected) then
          runtime.weaponRepairStartedAt=nil; runtime.weaponRepairActiveWeapon=nil; runtime.weaponRepairMessage=nil
          runtime.weaponRepairDrag=nil
      end
      runtime.weaponRepairScroll=math.max(1,math.min(math.max(1,#names-RepairLayout.visibleRows+1),math.floor(runtime.weaponRepairScroll or 1)))
      local status=selected and repairStatus(selected) or nil
      ui.repairRows={}; ui.repairRail=nil
      RepairArt.surface(0,0,960,720)
      OutfitArt.draw("paper",{x=276,y=498,w=418,h=145},{stretch=true})
      OutfitArt.draw("paper",{x=711,y=143,w=218,h=494},{stretch=true})
      OutfitArt.draw("paper",{x=286,y=126,w=389,h=72},{stretch=true})
      love.graphics.setColor(colors.cream); textBox("WEAPON WORKBENCH",90,27,665,32,1.27)
      textBox("SCRAP "..tostring(data.scrap or 0).."     FIELD SERVICE 26–99%     MAJOR REPAIR 0–25% + PART",92,60,812,25,.69)
      love.graphics.setColor(repairColors.ink); textBox("OWNED WEAPONS",34,130,213,28,.95,"center")
      if #names==0 then
          textBox("NO WEAPONS\nIN BACKPACK OR\nEQUIPMENT",40,280,204,78,.82,"center")
      end
      for row=1,RepairLayout.visibleRows do
          local index=(runtime.weaponRepairScroll or 1)+row-1
          local name=names[index]
          if name then
              local r=RepairLayout.row(row); ui.repairRows[#ui.repairRows+1]={rect=r,name=name,index=index}
              local active=name==selected
              OutfitArt.draw(active and "card-selected" or "card",r,{stretch=true})
              local profile=Catalog.weaponStats[name]
              love.graphics.setColor(repairColors.ink); textBox(profile.name or Util.titleFromFile(name),r.x+9,r.y+9,r.w-54,35,.65,nil,.60)
              local condition=repairStatus(name).durability
              love.graphics.setColor(condition<=25 and repairColors.red or repairColors.green); textBox(tostring(condition).."%",r.x+r.w-43,r.y+10,37,19,.68,"right")
              RepairArt.condition(r.x+10,r.y+48,r.w-20,5,condition)
          end
      end
      ui.repairListUp=repairButton("^",RepairLayout.listUp,runtime.weaponRepairScroll>1)
      ui.repairListDown=repairButton("v",RepairLayout.listDown,runtime.weaponRepairScroll+RepairLayout.visibleRows<=#names)
      OutfitArt.draw("paper",{x=91,y=537,w=99,h=30},{stretch=true})
      love.graphics.setColor(repairColors.ink); textBox((#names==0 and "0" or tostring(runtime.weaponRepairScroll or 1)).." / "..tostring(#names),84,533,109,39,.79,"center")

      if selected then
          local profile=Catalog.weaponStats[selected]
          love.graphics.setColor(repairColors.ink); textBox(profile.name or Util.titleFromFile(selected),299,136,363,49,.98,"center")
          love.graphics.setColor(repairColors.brass); textBox("CONDITION",729,170,182,24,.83,"center")
          local condition=status.durability or 100
          local conditionLabel=condition==0 and "BROKEN" or (condition<=25 and "CRITICAL" or (condition<50 and "WORN" or (condition<75 and "USED" or "SOUND")))
          RepairArt.condition(729,202,182,10,condition)
          love.graphics.setColor(repairColors.ink); textBox(tostring(condition).."%  /  "..conditionLabel,729,222,182,26,.77,"center")
          RepairArt.item(selected,RepairLayout.weapon,ui,Catalog)
          if status.part then
              RepairArt.item(status.part,RepairLayout.part,ui,Catalog)
              local part=Catalog.repairParts[status.part]
              love.graphics.setColor(repairColors.brass); textBox(status.major and "CRITICAL PART" or "PART IF NEEDED",729,272,182,24,.77,"center")
              love.graphics.setColor(repairColors.ink); textBox(part and (part.component or part.name) or Util.titleFromFile(status.part),729,306,182,64,.81,"center")
              if not status.major then love.graphics.setColor(repairColors.muted)
              else love.graphics.setColor(status.hasPart and repairColors.green or repairColors.red) end
              local partState=not status.major and "ONLY REQUIRED BELOW 26%" or (status.hasPart and ("BACKPACK  x"..tostring(status.partCount)) or "NOT IN BACKPACK")
              textBox(partState,729,373,182,46,.73,"center")
          end
          local costLabel=status.major and "MAJOR REPAIR" or "FIELD SERVICE"
          love.graphics.setColor(repairColors.brass); textBox(costLabel,729,438,182,27,.83,"center")
          love.graphics.setColor(repairColors.ink); textBox(status.needed and (tostring(status.cost).." SCRAP") or "NO REPAIR NEEDED",729,471,182,40,.84,"center")
          love.graphics.setColor(colors.cream); textBox("TIMING CHECK",315,435,330,22,.74,"center")
          local rail=RepairLayout.rail; ui.repairRail=rail
          local phase=runtime.weaponRepairStartedAt and ((runtime.animationClock-runtime.weaponRepairStartedAt)*.86)%1 or nil
          RepairArt.timing(rail,phase)
          love.graphics.setColor(repairColors.green); textBox("GOOD",315,485,150,17,.65,"center")
          love.graphics.setColor(repairColors.brass); textBox("PERFECT",495,485,150,17,.65,"center")
          local requiredPart=status.part and Catalog.repairParts[status.part]
          local blockedInstruction=not status.needed and "This weapon is ready."
              or (not status.hasPart and (requiredPart and "Find this part in chests; carry it in your backpack." or "No compatible component is available for this weapon.")
              or ((data.scrap or 0)<status.cost and "Not enough scrap for this repair." or nil))
          local instruction=runtime.weaponRepairMessage or blockedInstruction
              or (runtime.weaponRepairStartedAt and "Tap or press confirm on the brass mark." or "Start repair, then tap or press confirm.")
          love.graphics.setColor(repairColors.ink); textBox(instruction,294,510,382,64,.77,"center")
          local canStart=status.needed and status.affordable and true or false
          local actionLabel=runtime.weaponRepairStartedAt and "TAP / SPACE"
              or (not status.needed and "READY" or (not status.hasPart and "FIND PART" or ((data.scrap or 0)<status.cost and "LOW SCRAP" or "BEGIN REPAIR")))
          ui.repairStart=repairButton(actionLabel,RepairLayout.start,canStart,runtime.weaponRepairStartedAt and true or false)
      else
          love.graphics.setColor(repairColors.ink); textBox("Collect a weapon to begin repair.",299,136,363,49,.84,"center")
          ui.repairStart=repairButton("BEGIN REPAIR",RepairLayout.start,false)
      end
      ui.repairBack=repairButton("BACK TO WORKSHOP",RepairLayout.back,true)
      ui.repairClose=repairButton("CLOSE",RepairLayout.close,true)
  end

  function ui.drawTrainUpgrades()
      if runtime.weaponRepairOpen then
          return UIStyle.scope("trainUpgrades",RepairLayout.bounds,drawWeaponRepairWorkbench)
      end
      love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("trainUpgrades",repairPanelBounds,function()
      local mobile=mobileEnabled()
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",150,70,660,580,16,16)
      love.graphics.setColor(colors.brass); textBox("TRAIN WORKSHOP",170,88,620,40,1.35,"center")
      local engine=EngineUpgrades.profile(runtime.saveData.engineLevel); local engineStatus=TrainUpgradeBalance.engineStatus(runtime.saveData,EngineUpgrades); local nextEngine=engineStatus.entry
      local maintenance=Maintenance.status(runtime.saveData)
      love.graphics.setColor(colors.cream); textBox("Scrap "..runtime.saveData.scrap.." / Train "..math.floor(maintenance.condition).."% / Oil "..maintenance.oil.."/"..maintenance.oilCapacity,170,130,620,26,.88,"center")
      love.graphics.setColor(.25,.18,.12); love.graphics.rectangle("fill",185,158,590,62,7,7)
      love.graphics.setColor(colors.brass); textBox("ENGINE: "..engine.name,201,163,394,24,.88)
      love.graphics.setColor(colors.cream); textBox("Fuel "..math.floor(engine.coal*100).."% / Supplies "..math.floor(engine.supplies*100).."% / Speed "..math.floor(engine.speed*100).."%",201,188,394,29,.75)
      local engineLabel=engineStatus.maximum and "MAX LEVEL" or (engineStatus.locked and ("UNLOCK "..engineStatus.unlockStop) or (nextEngine.cost.." SCRAP"))
      ui.engineUpgrade=button(engineLabel,mobile and 610 or 630,mobile and 162 or 170,mobile and 155 or 125,mobile and 54 or 36,engineStatus.affordable==true)
      ui.engineUpgrade.enabled=engineStatus.affordable==true
      ui.trainCars={}
      for i,c in ipairs(Catalog.trainCarCatalog) do
          local y=230+(i-1)*58; local status=TrainUpgradeBalance.carStatus(runtime.saveData,c)
          love.graphics.setColor(.25,.18,.12); love.graphics.rectangle("fill",185,y,590,52,7,7)
          love.graphics.setColor(colors.cream); textBox(c.name..": "..c.description,201,y+4,394,44,.85)
          local label=status.owned and "OWNED" or (status.locked and ("UNLOCK "..status.unlockStop) or c.cost.." SCRAP")
          ui.trainCars[i]=button(label,mobile and 610 or 630,y+(mobile and 1 or 6),mobile and 155 or 125,mobile and 50 or 34,status.affordable)
          ui.trainCars[i].enabled=status.affordable==true
      end
      ui.weaponRepair=button("WEAPON BENCH",185,mobile and 578 or 594,185,mobile and 64 or 38,true,.78)
      ui.weaponRepair.enabled=true
      local canSew=ui.canOpenOutfitWorkbench and ui.canOpenOutfitWorkbench() or false
      ui.sewingBench=button("SEWING BENCH",387,mobile and 578 or 594,185,mobile and 64 or 38,canSew,.78)
      ui.sewingBench.enabled=canSew
      ui.upgradeClose=button("CLOSE",590,mobile and 578 or 594,185,mobile and 64 or 38,true)
      end)
  end

  function ui.drawEditControls()
      local mobile=mobileEnabled()
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",mobile and 100 or 110,mobile and 145 or 158,mobile and 825 or 815,mobile and 225 or 122,10,10)
      love.graphics.setColor(colors.cream); love.graphics.print(runtime.editedItem and "MOVE / SCALE SELECTED ITEM" or "SELECT A YELLOW HANDLE",132,172)
      ui.editLeft=button("<",mobile and 125 or 132,mobile and 235 or 222,mobile and 56 or 40,mobile and 56 or 36,runtime.editedItem~=nil); ui.editRight=button(">",mobile and 245 or 220,mobile and 235 or 222,mobile and 56 or 40,mobile and 56 or 36,runtime.editedItem~=nil)
      ui.editUp=button("^",mobile and 185 or 176,mobile and 202 or 202,mobile and 56 or 40,mobile and 56 or 34,runtime.editedItem~=nil); ui.editDown=button("v",mobile and 185 or 176,mobile and 268 or 244,mobile and 56 or 40,mobile and 56 or 34,runtime.editedItem~=nil)
      ui.editSmaller=button("SIZE -",mobile and 320 or 280,mobile and 205 or 216,mobile and 100 or 82,mobile and 52 or 38,runtime.editedItem~=nil)
      ui.editLarger=button("SIZE +",mobile and 430 or 370,mobile and 205 or 216,mobile and 100 or 82,mobile and 52 or 38,runtime.editedItem~=nil)
      ui.editRotate=button("ROTATE",mobile and 540 or 460,mobile and 205 or 216,mobile and 100 or 82,mobile and 52 or 38,runtime.editedItem~=nil)
      ui.editBack=button("LAYER -",mobile and 650 or 560,mobile and 205 or 194,mobile and 100 or 82,mobile and 52 or 34,runtime.editedItem~=nil); ui.editForward=button("LAYER +",mobile and 760 or 650,mobile and 205 or 194,mobile and 100 or 82,mobile and 52 or 34,runtime.editedItem~=nil)
      ui.editPickup=button("PICK UP",mobile and 540 or 560,mobile and 270 or 236,mobile and 140 or 82,mobile and 52 or 34,runtime.editedItem~=nil)
      ui.editDone=button("DONE",mobile and 720 or 650,mobile and 270 or 236,mobile and 140 or 82,mobile and 52 or 34,true)
      local item=runtime.editedItem and runtime.saveData.droppedItems[runtime.editedItem]
      local function slider(label,x,y,w,value,kind)
          love.graphics.setColor(colors.cream); love.graphics.print(label,x,y-17,0,.65,.65)
          love.graphics.setColor(.11,.07,.04,.9); love.graphics.rectangle("fill",x,y,w,9,4,4)
          local parts=18
          for n=0,parts-1 do
              local t=n/(parts-1)
              if kind=="hue" then
                  local h=t*6; local sector=math.floor(h); local f=h-sector; local q=1-f
                  local r,g,b=1,0,0
                  if sector==0 then r,g,b=1,f,0 elseif sector==1 then r,g,b=q,1,0 elseif sector==2 then r,g,b=0,1,f elseif sector==3 then r,g,b=0,q,1 elseif sector==4 then r,g,b=f,0,1 else r,g,b=1,0,q end
                  love.graphics.setColor(r,g,b,.9)
              else love.graphics.setColor(t,t,t,.9) end
              love.graphics.rectangle("fill",x+t*w-2,y+1,w/(parts-1)+3,7)
          end
          love.graphics.setColor(colors.cream); love.graphics.circle("fill",x+value*w,y+4.5,6)
          love.graphics.setColor(colors.ink); love.graphics.circle("line",x+value*w,y+4.5,6)
          return {x=x-7,y=y-7,w=w+14,h=23}
      end
      local hue=item and (item.hue or 0) or 0
      local saturation=item and math.max(0,math.min(2,item.saturation or 1)) or 1
      ui.editHue=slider("HUE  "..math.floor(hue*360).."°",mobile and 330 or 755,mobile and 345 or 190,mobile and 180 or 145,hue,"hue")
      ui.editSaturation=slider("SATURATION  "..math.floor(saturation*100).."%",mobile and 570 or 755,mobile and 345 or 239,mobile and 180 or 145,saturation/2,"saturation")
  end

  function ui.updateEditColorSlider(x)
      local item=runtime.editedItem and runtime.saveData.droppedItems[runtime.editedItem]
      local control=ui.editSliderDrag=="hue" and ui.editHue or ui.editSaturation
      if not item or not control then return end
      local value=math.max(0,math.min(1,(x-(control.x+7))/(control.w-14)))
      if ui.editSliderDrag=="hue" then item.hue=value else item.saturation=value*2 end
  end

  local function drawEnding()
      WorldView.begin(); drawLandscape(); WorldView.finish(); love.graphics.setColor(0.08,0.05,0.03,0.72); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("ending",{x=80,y=55,w=800,h=610},function()
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",80,55,800,610,20,20)
      local finale=FinaleProgression.evaluate(runtime.saveData,StopHelpProgression,Maintenance)
      love.graphics.setColor(colors.brass); textBox(finale.choice and finale.tier or "THE LAST SWITCH",110,83,740,58,1.5,"center")
      love.graphics.setColor(colors.cream); textBox(finale.reunion,145,151,670,86,.95,"center")
      love.graphics.setColor(colors.brass)
      textBox("GOODWILL "..finale.goodwill.."  •  FAMILY CLUES "..finale.storyClues.."/10  •  MYSTERY CLUES "..finale.mysteryClues.."/5",120,245,720,20,.66,"center")
      textBox("HELP "..finale.helpCount.."  •  RIDES "..finale.rides.."  •  TRAIN "..finale.condition.."%  •  CARS "..finale.cars.."  •  LEVEL "..finale.level,120,271,720,20,.66,"center")
      if not finale.choice then
          love.graphics.setColor(colors.cream); textBox("Your family asks what comes next. Choose the legacy this journey leaves behind.",185,318,590,46,.78,"center")
          ui.endingChoices={}
          for index,choice in ipairs(FinaleProgression.choices) do
              local x=115+(index-1)*245
              love.graphics.setColor(colors.cream); textBox(choice.description,x,362,220,73,.8,"center")
              ui.endingChoices[index]=button(index.."  "..choice.title,x,440,220,58,true)
              ui.endingChoices[index].id=choice.id
          end
          love.graphics.setColor(colors.cream); textBox("All three paths are hopeful. Your choice changes the final legacy, never a good-or-evil alignment.",190,535,580,24,.62,"center")
          ui.endingButton=nil
      else
          ui.endingChoices=nil
          love.graphics.setColor(colors.cream); textBox(finale.outcome,145,313,670,82,.92,"center")
          love.graphics.setColor(colors.brass); textBox(finale.tierText,155,404,650,63,.85,"center")
          local family={runtime.saveData.character,(runtime.saveData.npcRoster or {})[1],(runtime.saveData.npcRoster or {})[2]}
          for i,file in ipairs(family) do local img=characterImages[file] or npcImages[file]; if img then local s=math.min(72/img:getWidth(),96/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,380+(i-1)*100,520+math.sin(runtime.animationClock*3+i)*3,0,s,s,img:getWidth()/2,img:getHeight()/2) end end
          ui.endingButton=button("CAMPAIGN COMPLETE  •  RETURN",330,590,300,45,true)
      end
      end)
  end

  return {
    drawMenuFrame=drawMenuFrame,
    button=button,
    requestExitPrompt=requestExitPrompt,
    resolveExitPrompt=resolveExitPrompt,
    drawExitPrompt=drawExitPrompt,
    drawTrade=drawTrade,
    ownsTrainCar=ownsTrainCar,
    drawEnding=drawEnding
  }
end

return {new=new}
