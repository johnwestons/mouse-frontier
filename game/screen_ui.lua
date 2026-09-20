local WorldView=require("game.world_view")
local Accessibility=require("game.accessibility")
local Typography=require("game.typography")

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
  local isWeapon=required(context,"isWeapon","function")
  local travelCost=required(context,"travelCost","function")
  local repairStatus=required(context,"repairStatus","function")
  local questSummary=required(context,"questSummary","function")

  local function drawMenuFrame(x,y,w,h,kind,alpha)
      local frame=ui.menuFrames and ui.menuFrames[kind or 1]
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

  function ui.drawJourneyHUD()
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
          for index,spec in ipairs({{"FOOD","food",colors.green},{"WATER","water",colors.blue},{"COAL","coal",colors.red},{"OIL","oil",colors.brass}}) do
              local capacity=spec[2]=="oil" and Maintenance.oilCapacity(data) or TrainUpgradeBalance.resourceCapacity(data,spec[2])
              ui.drawResource(spec[1],data.resources[spec[2]],left+(index-1)*(resourceWidth+12),spec[3],resourceWidth,capacity)
          end
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
  end

  local function button(text, x, y, w, h, active, textScale)
      local highContrast=runtime.saveData and Accessibility.enabled(runtime.saveData,"highContrast")
      if highContrast then
          love.graphics.setColor(0,0,0,active and .98 or .82); love.graphics.rectangle("fill",x,y,w,h,8,8)
          love.graphics.setColor(active and 1 or .62,active and .84 or .62,active and .28 or .62,1); love.graphics.setLineWidth(active and 4 or 2); love.graphics.rectangle("line",x,y,w,h,8,8); love.graphics.setLineWidth(1)
      elseif ui.menuFrames and ui.menuFrames[4] then drawMenuFrame(x-3,y-3,w+6,h+6,4,active and 1 or .55) else love.graphics.setColor(active and colors.brass or colors.panel); love.graphics.rectangle("fill", x, y, w, h, 8, 8) end
      local scale=(textScale or 1)*(runtime.saveData and Accessibility.textScale(runtime.saveData) or 1)
      if mobileEnabled() then scale=math.max(scale,.78) end
      scale=math.min(scale,mobileEnabled() and 1.18 or 1.22)
      love.graphics.setColor(colors.cream)
      local fitted,height,lines,fits=Typography.drawText(love.graphics,text,x+10,y+6,w-20,h-12,
          {scale=scale,minScale=mobileEnabled() and .75 or .60,align="center",valign="center"})
      return {x=x,y=y,w=w,h=h,textScale=fitted,textHeight=height,textLines=lines,textFits=fits}
  end

  local function requestExitPrompt(kind)
      runtime.exitPrompt=kind
      if ui.playSfx then ui.playSfx("menu") end
  end

  local function resolveExitPrompt(choice)
      local prompt=runtime.exitPrompt
      runtime.exitPrompt=nil
      if choice~="yes" then return end
      if prompt=="title" then
          writeSave()
          runtime.state="slots"
      elseif prompt=="quit" then
          love.event.quit()
      end
  end

  local function drawExitPrompt()
      if not runtime.exitPrompt then return end
      love.graphics.setColor(0,0,0,.70)
      love.graphics.rectangle("fill",0,0,W,H)
      drawMenuFrame(270,252,420,196,2,.99)
      love.graphics.setColor(colors.cream)
      local title=runtime.exitPrompt=="quit" and "Quit Game?" or "Return to Title Screen?"
      textBox(title,290,274,380,62,1.15,"center")
      love.graphics.setColor(colors.brass)
      love.graphics.rectangle("fill",315,340,330,2)
      local mobile=mobileEnabled()
      ui.exitYes=button("YES",mobile and 300 or 330,365,mobile and 160 or 115,mobile and 66 or 44,true,.92)
      ui.exitNo=button("NO",mobile and 500 or 515,365,mobile and 160 or 115,mobile and 66 or 44,true,.92)
  end

  function ui.drawSlots()
      love.graphics.clear(0.09, 0.06, 0.04); love.graphics.setColor(colors.cream)
      if scenery.titleImage then
          local scale=math.min(540/scenery.titleImage:getWidth(),185/scenery.titleImage:getHeight())
          love.graphics.setColor(1,1,1)
          love.graphics.draw(scenery.titleImage,W/2,88,0,scale,scale,scenery.titleImage:getWidth()/2,scenery.titleImage:getHeight()/2)
      else
          love.graphics.printf("MOUSE FRONTIER", 0, 82, W, "center", 0, 2.2, 2.2)
      end
      love.graphics.setColor(colors.cream)
      love.graphics.printf("Choose a journey", 0, 182, W, "center")
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
  end

  function ui.drawCharacterSelect()
      local mobile=mobileEnabled()
      love.graphics.clear(0.09, 0.06, 0.04); love.graphics.setColor(colors.cream)
      textBox("CHOOSE YOUR TRAVELER",80,25,W-160,40,1.35,"center")
      textBox("Tap a traveler to read their profile.",80,67,W-160,27,.85,"center")
      ui.characters = {}
      local columns=mobile and 4 or 5
      local rows=math.ceil(#characters/columns); local maxScroll=math.max(0,rows-3); runtime.characterScroll=math.max(0,math.min(maxScroll,runtime.characterScroll))
      local hoveredFile
      local mouseX,mouseY=screenToGame(love.mouse.getPosition())
      for i, file in ipairs(characters) do
          local col, row = (i-1)%columns, math.floor((i-1)/columns); local x, y = (mobile and 26 or 42)+col*(mobile and 216 or 182), 100+(row-runtime.characterScroll)*198
          local r={x=x,y=y,w=mobile and 194 or 150,h=180,visible=y>78 and y<700}; ui.characters[i]=r
          if y>78 and y<700 then
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill", x,y,r.w,r.h,10,10)
          local img=characterImages[file]
          if img then local s=math.min(112/img:getWidth(),108/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,x+r.w/2,y+60,0,s,s,img:getWidth()/2,img:getHeight()/2) end
          local identity=Catalog.characterIdentity(file)
          love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(file),x+8,y+118,r.w-16,38,mobile and .92 or .72,"center")
          love.graphics.setColor(colors.brass); textBox(identity.role,x+8,y+158,r.w-16,20,mobile and .76 or .6,"center")
          if Util.pointIn(mouseX,mouseY,r) then hoveredFile=file end
          end
      end
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
          love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(hoveredFile),tx+12,ty+10,tooltipW-24,"left",0,.88,.88)
          love.graphics.setColor(colors.brass); love.graphics.print("ABILITY  "..ability,tx+12,ty+34,0,.65,.65)
          love.graphics.setColor(colors.cream); love.graphics.printf(abilityDescription,tx+12,ty+51,tooltipW-24,"left",0,.62,.62)
          love.graphics.setColor(colors.brass); love.graphics.print("TRAIT  "..trait.name,tx+12,ty+79,0,.65,.65)
          love.graphics.setColor(colors.cream); love.graphics.printf(trait.description,tx+12,ty+96,tooltipW-24,"left",0,.58,.58)
      end
      ui.characterUp=button("^",mobile and 888 or 905,110,mobile and 58 or 38,mobile and 70 or 42,runtime.characterScroll>0); ui.characterDown=button("v",mobile and 888 or 905,mobile and 565 or 590,mobile and 58 or 38,mobile and 70 or 42,runtime.characterScroll<maxScroll)
      love.graphics.setColor(colors.cream); textBox(tostring(runtime.characterScroll+1).."/"..(maxScroll+1),888,192,58,35,.78,"center")
      if runtime.characterPreviewFile then
          local file=runtime.characterPreviewFile; local identity=Catalog.characterIdentity(file)
          love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,W,H)
          drawMenuFrame(185,115,590,500,1,1)
          love.graphics.setColor(colors.cream); textBox("TRAVELER PROFILE",205,136,550,38,1.15,"center")
          local img=characterImages[file]
          if img then local s=math.min(180/img:getWidth(),205/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,330,300,0,s,s,img:getWidth()/2,img:getHeight()/2) end
          love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(file),435,188,310,44,1.05)
          love.graphics.setColor(colors.brass); textBox("ROLE: "..identity.role,435,236,310,27,.78)
          textBox("TRAIT: "..identity.trait.name,435,268,310,27,.8)
          love.graphics.setColor(colors.cream); textBox(identity.trait.description,435,297,310,52,.8)
          love.graphics.setColor(colors.brass); textBox("ABILITY: "..identity.ability.name,435,358,310,27,.8)
          love.graphics.setColor(colors.cream); textBox(identity.ability.description,435,390,310,59,.8)
          textBox("Your chosen traveler becomes the player. The others can be met along the journey.",220,455,525,51,.8,"center")
          ui.characterConfirm=button("CHOOSE THIS TRAVELER",mobile and 260 or 275,520,mobile and 280 or 250,mobile and 66 or 48,true,.78)
          ui.characterCancel=button("BACK",mobile and 565 or 555,520,mobile and 135 or 130,mobile and 66 or 48,true,.82)
      else ui.characterConfirm=nil; ui.characterCancel=nil end
  end


  function ui.drawResource(name, value, x, color, width, capacity)
      width=width or 150
      capacity=capacity or 20
      if mobileEnabled() then
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,18,width,61,7,7)
          love.graphics.setColor(colors.cream); textBox(name,x+12,25,width*.45-12,35,1.04)
          textBox(value.." / "..capacity,x+width*.45,25,width*.55-12,35,1.15,"right")
          love.graphics.setColor(color); love.graphics.rectangle("fill",x+12,68,(width-24)*math.max(0,math.min(1,value/capacity)),5,2,2)
          return
      end
      local barWidth=math.max(20,width-66)
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,20,width,34,7,7)
      love.graphics.setColor(color); love.graphics.rectangle("fill",x+58,29,math.max(0,math.min(barWidth,value*barWidth/capacity)),16,4,4)
      love.graphics.setColor(colors.cream); love.graphics.print(name.." "..value.."/"..capacity,x+6,28,0,.78,.78)
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
      local merchant=source.relationshipId or source.merchant or runtime.tradeNPC or runtime.saveData.currentNPC
      local terms=MerchantTrade.terms(runtime.saveData,source)
      local availableBudget=MerchantTrade.availableBudget(runtime.saveData,source)
      do
          love.graphics.setColor(0,0,0,.86); love.graphics.rectangle("fill",0,0,W,H)
          drawMenuFrame(60,42,840,640,1,1)
          love.graphics.setColor(colors.cream); textBox(source.title or Util.titleFromFile(merchant).."'S TRADING POST",85,59,790,45,1.2,"center")
          textBox("YOUR SCRAP "..runtime.saveData.scrap.." / MERCHANT BUDGET "..math.max(0,availableBudget),85,108,790,27,.9,"center")
          love.graphics.setColor(colors.brass); textBox(runtime.tradeMessage or (terms.tier.." terms / "..math.floor(terms.discount*100+.5).."% buying discount"),85,139,790,32,.82,"center")
          local stockIndices,occupied={},{}
          for index in pairs(source.stock or {}) do if type(index)=="number" and MerchantTrade.stockItem(source,index) then stockIndices[#stockIndices+1]=index end end
          table.sort(stockIndices)
          for index=1,(runtime.saveData.inventoryCapacity or 6) do if runtime.saveData.inventory[index] then occupied[#occupied+1]=index end end
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
                  if gift then ui.tradeGive[ownedIndex]=button("GIVE",716,y+49,146,56,true,.95) end
              end
          end
          ui.tradeBuyPrev=button("<",90,559,65,52,runtime.tradeBuyPage>0)
          ui.tradeBuyNext=button(">",382,559,65,52,runtime.tradeBuyPage<buyPages)
          ui.tradePrev=button("<",490,559,65,52,runtime.tradeSellPage>0)
          ui.tradeNext=button(">",797,559,65,52,runtime.tradeSellPage<sellPages)
          love.graphics.setColor(colors.cream)
          textBox((runtime.tradeBuyPage+1).." / "..(buyPages+1),170,559,196,52,.95,"center")
          textBox((runtime.tradeSellPage+1).." / "..(sellPages+1),570,559,212,52,.95,"center")
          ui.tradeClose=button("DONE TRADING",340,622,280,48,true,.95)
          return
      end
  end

  function ui.drawMap()
      love.graphics.setColor(0.05,0.035,0.02,0.78); love.graphics.rectangle("fill",0,0,W,H)
      love.graphics.setColor(0.76,0.59,0.34); love.graphics.rectangle("fill",70,75,820,570,18,18)
      love.graphics.setColor(0.66,0.47,0.27)
      for y=95,625,20 do for x=90+(y%37),870,43 do love.graphics.rectangle("fill",x,y,3,2) end end
      love.graphics.setColor(0.49,0.31,0.18); love.graphics.setLineWidth(8); love.graphics.rectangle("line",70,75,820,570,18,18)
      love.graphics.setColor(0.22,0.13,0.065); textBox("THE MOUSE FRONTIER TRAIL",100,90,640,50,1.25,"center")
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
          love.graphics.setColor(colors.ink); love.graphics.printf(tostring(i),p[1]-14,p[2]-7,28,"center")
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
  end

  function ui.drawDialogue()
      if not runtime.dialogue then return end
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
          if not mobile then love.graphics.setColor(colors.cream); textBox("Press 1, 2, or 3 to choose",x+45,y+h-83,w-90,22,.75,"center") end
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
      else ui.questAccept=nil; ui.questDecline=nil end
  end

  function ui.drawTravelConfirm()
      -- The gameplay renderer already drew the fitted train and its contents.
      love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,W,H)
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
  end

  function ui.drawRandomEvent()
      WorldView.begin(); drawLandscape(); WorldView.finish(); love.graphics.setColor(0,0,0,0.76); love.graphics.rectangle("fill",0,0,W,H)
      ui.eventChoices=EventUI.draw(runtime.randomEvent,scenery.eventArt,drawMenuFrame,button,colors,runtime.saveData.eventProgress or {},canChooseEvent)
  end

  local function ownsTrainCar(id) return TrainUpgradeBalance.owns(runtime.saveData,id) end
  function ui.drawTrainUpgrades()
      local mobile=mobileEnabled()
      love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,W,H)
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
      ui.trainCars={}
      for i,c in ipairs(Catalog.trainCarCatalog) do
          local y=230+(i-1)*58; local status=TrainUpgradeBalance.carStatus(runtime.saveData,c)
          love.graphics.setColor(.25,.18,.12); love.graphics.rectangle("fill",185,y,590,52,7,7)
          love.graphics.setColor(colors.cream); textBox(c.name..": "..c.description,201,y+4,394,44,.85)
          local label=status.owned and "OWNED" or (status.locked and ("UNLOCK "..status.unlockStop) or c.cost.." SCRAP")
          ui.trainCars[i]=button(label,mobile and 610 or 630,y+(mobile and 1 or 6),mobile and 155 or 125,mobile and 50 or 34,status.affordable)
      end
      local repair=repairStatus()
      local repairLabel=repair.needed and ("REPAIR EQUIPPED  "..repair.cost.." SCRAP") or "EQUIPPED WEAPONS READY"
      ui.weaponRepair=button(repairLabel,185,mobile and 578 or 594,mobile and 285 or 280,mobile and 64 or 38,repair.affordable==true)
      ui.upgradeClose=button("CLOSE",mobile and 490 or 495,mobile and 578 or 594,mobile and 285 or 280,mobile and 64 or 38,true)
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
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",80,55,800,610,20,20)
      local finale=FinaleProgression.evaluate(runtime.saveData,StopHelpProgression,Maintenance)
      love.graphics.setColor(colors.brass); textBox(finale.choice and finale.tier or "THE LAST SWITCH",110,83,740,58,1.5,"center")
      love.graphics.setColor(colors.cream); textBox(finale.reunion,145,151,670,86,.95,"center")
      love.graphics.setColor(colors.brass)
      love.graphics.printf("GOODWILL "..finale.goodwill.."  •  FAMILY CLUES "..finale.storyClues.."/10  •  MYSTERY CLUES "..finale.mysteryClues.."/5",120,245,720,"center",0,.66,.66)
      love.graphics.printf("HELP "..finale.helpCount.."  •  RIDES "..finale.rides.."  •  TRAIN "..finale.condition.."%  •  CARS "..finale.cars.."  •  LEVEL "..finale.level,120,271,720,"center",0,.66,.66)
      if not finale.choice then
          love.graphics.setColor(colors.cream); love.graphics.printf("Your family asks what comes next. Choose the legacy this journey leaves behind.",185,318,590,"center",0,.78,.78)
          ui.endingChoices={}
          for index,choice in ipairs(FinaleProgression.choices) do
              local x=115+(index-1)*245
              love.graphics.setColor(colors.cream); textBox(choice.description,x,362,220,73,.8,"center")
              ui.endingChoices[index]=button(index.."  "..choice.title,x,440,220,58,true)
              ui.endingChoices[index].id=choice.id
          end
          love.graphics.setColor(colors.cream); love.graphics.printf("All three paths are hopeful. Your choice changes the final legacy, never a good-or-evil alignment.",190,535,580,"center",0,.62,.62)
          ui.endingButton=nil
      else
          ui.endingChoices=nil
          love.graphics.setColor(colors.cream); textBox(finale.outcome,145,313,670,82,.92,"center")
          love.graphics.setColor(colors.brass); textBox(finale.tierText,155,404,650,63,.85,"center")
          local family={runtime.saveData.character,(runtime.saveData.npcRoster or {})[1],(runtime.saveData.npcRoster or {})[2]}
          for i,file in ipairs(family) do local img=characterImages[file] or npcImages[file]; if img then local s=math.min(72/img:getWidth(),96/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,380+(i-1)*100,520+math.sin(runtime.animationClock*3+i)*3,0,s,s,img:getWidth()/2,img:getHeight()/2) end end
          ui.endingButton=button("CAMPAIGN COMPLETE  •  RETURN",330,590,300,45,true)
      end
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
