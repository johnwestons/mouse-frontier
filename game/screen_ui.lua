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
  local writeSave=required(context,"writeSave","function")
  local screenToGame=required(context,"screenToGame","function")
  local ensureStopLayout=required(context,"ensureStopLayout","function")
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
  end

  function ui.drawJourneyHUD()
      -- Consolidate the loose journey text into the same brass-and-iron visual
      -- language as the rest of the interface.
      drawMenuFrame(10,58,410,132,4,.90)
      love.graphics.setColor(colors.brass)
      love.graphics.rectangle("fill",25,91,378,2)
      love.graphics.setColor(colors.cream)
      love.graphics.print("STOP "..runtime.saveData.location,26,70,0,1.05,1.05)
      love.graphics.printf((runtime.saveData.trait and runtime.saveData.trait.name or "Survivor").."  •  CARS "..#(runtime.saveData.trainCars or {}),145,72,255,"right",0,.76,.76)
      local mobile=mobileEnabled()
      love.graphics.print("MOVE",26,99,0,.70,.70)
      love.graphics.print(mobile and "TOUCH JOYSTICK" or "WASD / ARROWS",80,98,0,mobile and .70 or .80,mobile and .70 or .80)
      ui.drawHealthBar("HP",runtime.saveData.health,runtime.saveData.maxHealth,25,119,220)

      local progression=PlayerProgression.status(runtime.saveData)
      local level,xp,nextXP=progression.level,progression.xp,progression.nextXP
      love.graphics.setColor(colors.cream)
      love.graphics.print("LV "..level.."  ABILITY R"..progression.abilityRank,265,119,0,.66,.66)
      love.graphics.printf(progression.maximum and "MAX" or (xp.." / "..nextXP.." XP"),265,135,130,"center",0,.58,.58)
      love.graphics.setColor(.08,.06,.045,.92); love.graphics.rectangle("fill",265,149,130,12,3,3)
      local progress=progression.maximum and 1 or math.min(1,xp/math.max(1,nextXP))
      love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",267,151,126*progress,8,2,2)
      love.graphics.setColor(colors.cream); love.graphics.printf("LEVEL BONUS  AIM +"..progression.bonuses.attack.."  ARM +"..progression.bonuses.armor.."  MOVE +"..progression.bonuses.move,25,169,370,"center",0,.50,.50)

      local ammoParts={}
      for i=1,2 do
          local weapon=runtime.saveData.equipment[i]; local combat=weapon and Catalog.weaponCombat[weapon]
          if combat and combat.ammo then ammoParts[#ammoParts+1]=Util.titleFromFile(combat.ammo).."  "..(runtime.saveData.ammo[combat.ammo] or 0) end
      end
      if #ammoParts>0 then
          drawMenuFrame(500,143,225,42,4,.90)
          love.graphics.setColor(colors.brass); love.graphics.print("AMMO",516,156,0,.66,.66)
          love.graphics.setColor(colors.cream); love.graphics.printf(table.concat(ammoParts,"   •   "),568,155,140,"center",0,.66,.66)
      end
  end

  local function button(text, x, y, w, h, active, textScale)
      if ui.menuFrames and ui.menuFrames[4] then drawMenuFrame(x-3,y-3,w+6,h+6,4,active and 1 or .55) else love.graphics.setColor(active and colors.brass or colors.panel); love.graphics.rectangle("fill", x, y, w, h, 8, 8) end
      local scale=textScale or 1
      if mobileEnabled() then scale=math.max(scale,.78) end
      love.graphics.setColor(colors.cream); love.graphics.printf(text, x+5, y+h/2-8*scale, w-10, "center",0,scale,scale)
      return {x=x,y=y,w=w,h=h}
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
      love.graphics.printf(title,290,290,380,"center",0,1.25,1.25)
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
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill", mobile and 160 or 210, y, mobile and 640 or 540, mobile and 126 or 96, 12, 12)
          love.graphics.setColor(colors.cream); love.graphics.print("SAVE "..i, mobile and 182 or 232, y+18, 0, 1.3, 1.3)
          love.graphics.print(data and (Util.titleFromFile(data.character).."  •  Stop "..tostring(data.location or 1)) or "New journey", mobile and 182 or 232, y+52)
          if data and mobile then
              ui.slots[i]=button("CONTINUE",475,y+31,135,64,true)
              ui.slotNew[i]=button("NEW",620,y+31,82,64,true)
              ui.slotDelete[i]=button("DELETE",712,y+31,76,64,true,.78)
          elseif data then
              ui.slots[i]=button("CONTINUE",500,y+16,105,32,true)
              ui.slotNew[i]=button("NEW",612,y+16,52,32,true)
              ui.slotDelete[i]=button("DELETE",671,y+16,65,32,true)
          else ui.slotNew[i]=button("NEW GAME",mobile and 555 or 585,y+(mobile and 31 or 25),mobile and 220 or 138,mobile and 64 or 46,true) end
      end
  end

  function ui.drawCharacterSelect()
      love.graphics.clear(0.09, 0.06, 0.04); love.graphics.setColor(colors.cream)
      love.graphics.printf("CHOOSE YOUR TRAVELER", 0, 34, W, "center", 0, 1.6, 1.6)
      love.graphics.printf("Everyone else will remain available as an NPC.", 0, 70, W, "center")
      ui.characters = {}
      local rows=math.ceil(#characters/5); local maxScroll=math.max(0,rows-3); runtime.characterScroll=math.max(0,math.min(maxScroll,runtime.characterScroll))
      local hoveredFile
      local mouseX,mouseY=screenToGame(love.mouse.getPosition())
      for i, file in ipairs(characters) do
          local col, row = (i-1)%5, math.floor((i-1)/5); local x, y = 42+col*182, 100+(row-runtime.characterScroll)*198
          local r={x=x,y=y,w=150,h=180}; ui.characters[i]=r
          if y>78 and y<700 then
          love.graphics.setColor(colors.panel); love.graphics.rectangle("fill", x,y,r.w,r.h,10,10)
          local img=characterImages[file]
          if img then local s=math.min(112/img:getWidth(),120/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,x+75,y+68,0,s,s,img:getWidth()/2,img:getHeight()/2) end
          love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(file),x+5,y+142,r.w-10,"center",0,0.82,0.82)
          if Util.pointIn(mouseX,mouseY,r) then hoveredFile=file end
          end
      end
      if hoveredFile then
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
      local mobile=mobileEnabled()
      ui.characterUp=button("^",mobile and 876 or 905,110,mobile and 68 or 38,mobile and 70 or 42,runtime.characterScroll>0); ui.characterDown=button("v",mobile and 876 or 905,mobile and 565 or 590,mobile and 68 or 38,mobile and 70 or 42,runtime.characterScroll<maxScroll)
      love.graphics.setColor(colors.cream); love.graphics.print("SCROLL",898,165,0,0.65,0.65)
  end


  function ui.drawResource(name, value, x, color, width, capacity)
      width=width or 150
      capacity=capacity or 20
      local barWidth=math.max(20,width-66)
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,20,width,34,7,7)
      love.graphics.setColor(color); love.graphics.rectangle("fill",x+58,29,math.max(0,math.min(barWidth,value*barWidth/capacity)),16,4,4)
      love.graphics.setColor(colors.cream); love.graphics.print(name.." "..value.."/"..capacity,x+6,28,0,.78,.78)
  end

  function ui.drawHealthBar(label,value,maxValue,x,y,w)
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",x,y,w,30,6,6)
      love.graphics.setColor(0.25,0.08,0.07); love.graphics.rectangle("fill",x+55,y+8,w-65,14,3,3)
      love.graphics.setColor(0.78,0.18,0.16); love.graphics.rectangle("fill",x+55,y+8,(w-65)*math.max(0,value)/math.max(1,maxValue),14,3,3)
      love.graphics.setColor(colors.cream); love.graphics.print(label.." "..value.."/"..maxValue,x+7,y+7)
  end

  local function drawTrade()
      local layout=ensureStopLayout(); layout.tradeStock=layout.tradeStock or {}
      local mobile=mobileEnabled()
      love.graphics.setColor(0,0,0,.72); love.graphics.rectangle("fill",0,0,W,H)
      drawMenuFrame(90,65,780,600,1,1); love.graphics.setColor(colors.cream)
      love.graphics.printf(Util.titleFromFile(runtime.tradeNPC or runtime.saveData.currentNPC).."'S TRADING POST",110,95,740,"center",0,1.35,1.35)
      love.graphics.printf("YOUR SCRAP: "..(runtime.saveData.scrap or 0).."   •   Buy supplies, sell gear, or give your ally a weapon",120,135,720,"center",0,.82,.82)
      ui.tradeBuy={}; love.graphics.print("FOR SALE",135,180)
      for i=1,4 do local name=layout.tradeStock[i]; if name then local y=210+(i-1)*82; local price=Inventory.scrapPrice(name,Catalog); ui.drawItem(name,{x=135,y=y,w=62,h=62}); love.graphics.setColor(colors.cream); love.graphics.print(Util.titleFromFile(name),210,y+8,0,.82,.82); love.graphics.print(price.." SCRAP",210,y+35,0,.72,.72); ui.tradeBuy[i]=button("BUY",mobile and 345 or 365,y+(mobile and 2 or 12),mobile and 115 or 90,mobile and 58 or 38,runtime.saveData.scrap>=price and Inventory.firstEmptySlot(runtime.saveData)~=nil) end end
      love.graphics.print("YOUR ITEMS",500,180); love.graphics.print("NPC BUDGET: "..(layout.tradeBudget or 0).." SCRAP",500,202); ui.tradeSell={}; ui.tradeGive={}
      local row=0; for i=1,(runtime.saveData.inventoryCapacity or 6) do local name=runtime.saveData.inventory[i]; if name and row<5 then local y=210+row*72; ui.drawItem(name,{x=495,y=y,w=54,h=54}); love.graphics.setColor(colors.cream); love.graphics.print(Util.titleFromFile(name),555,y+5,0,.72,.72); local weapon=isWeapon(name); ui.tradeSell[i]=button("SELL +"..Inventory.resalePrice(name,Catalog,runtime.saveData),mobile and 675 or 700,y+(mobile and 1 or 5),mobile and (weapon and 105 or 140) or 110,mobile and 58 or 30,true); if weapon then ui.tradeGive[i]=button("GIVE",mobile and 790 or 700,y+(mobile and 1 or 37),mobile and 70 or 110,mobile and 58 or 28,true) end; row=row+1 end end
      ui.tradeClose=button("DONE TRADING",mobile and 360 or 375,mobile and 590 or 605,mobile and 240 or 210,mobile and 64 or 40,true)
  end

  function ui.drawMap()
      love.graphics.setColor(0.05,0.035,0.02,0.78); love.graphics.rectangle("fill",0,0,W,H)
      love.graphics.setColor(0.76,0.59,0.34); love.graphics.rectangle("fill",70,75,820,570,18,18)
      love.graphics.setColor(0.66,0.47,0.27)
      for y=95,625,20 do for x=90+(y%37),870,43 do love.graphics.rectangle("fill",x,y,3,2) end end
      love.graphics.setColor(0.49,0.31,0.18); love.graphics.setLineWidth(8); love.graphics.rectangle("line",70,75,820,570,18,18)
      love.graphics.setColor(0.35,0.23,0.13); love.graphics.printf("THE MOUSE FRONTIER TRAIL",70,96,820,"center",0,1.5,1.5)
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
          love.graphics.setColor(0.30,0.19,0.11); love.graphics.printf(biomes[((i-1)%#biomes)+1],p[1]-52,p[2]+16,104,"center",0,0.78,0.78)
      end end
      local enc=runtime.saveData.encounters[tostring(runtime.saveData.location)]; local status=not enc and "Unexplored stop" or (enc.hasMob and not enc.resolved and "Danger nearby" or (enc.hasMob and "Mob cleared" or "Peaceful stop"))
      love.graphics.setColor(0.39,0.25,0.14,0.92); love.graphics.rectangle("fill",105,548,750,62,8,8)
      love.graphics.setColor(colors.cream); love.graphics.printf("CURRENT: Stop "..runtime.saveData.location.." - "..biomes[((runtime.saveData.location-1)%#biomes)+1].." - "..status,120,562,720,"center")
      local quests=questSummary()
      local questLine=quests.count>0 and ("ACTIVE: "..quests.first..(quests.count>1 and ("  +"..(quests.count-1).." more") or "")) or "No active deliveries or passengers."
      love.graphics.printf(questLine,120,586,720,"center",0,0.8,0.8)
      local mobile=mobileEnabled()
      ui.mapUp=button("^",mobile and 790 or 805,105,mobile and 68 or 42,mobile and 64 or 36,runtime.mapScroll>0); ui.mapDown=button("v",mobile and 790 or 805,mobile and 181 or 155,mobile and 68 or 42,mobile and 64 or 36,runtime.mapScroll<maxScroll)
      love.graphics.setColor(colors.ink); love.graphics.print("PAGE "..(runtime.mapScroll+1).."/"..(maxScroll+1),720,130,0,0.75,0.75)
      love.graphics.setLineWidth(1)
  end

  function ui.drawDialogue()
      if not runtime.dialogue then return end
      local x,y,w,h=230,115,500,105
      drawMenuFrame(x-6,y-6,w+12,h+12,1,1)
      love.graphics.setColor(colors.cream); love.graphics.print(runtime.dialogue.speaker or "Traveler",x+20,y+17,0,1.15,1.15); love.graphics.printf(runtime.dialogue.text,x+20,y+49,w-40,"left")
      if runtime.dialogue.choice and runtime.questOffer then
          local agreeing=runtime.questOffer.kind=="trade" and "YES, AGREE TO TRADE" or "YES, I'LL HELP"
          local declining=runtime.questOffer.kind=="trade" and "NO, DECLINE TRADE" or "SORRY, NO"
          local mobile=mobileEnabled()
          ui.questAccept=button(agreeing,x+(mobile and 35 or 70),y+h+12,mobile and 205 or 165,mobile and 62 or 40,true); ui.questDecline=button(declining,x+(mobile and 260 or 265),y+h+12,mobile and 205 or 165,mobile and 62 or 40,true)
      else ui.questAccept=nil; ui.questDecline=nil end
  end

  function ui.drawTravelConfirm()
      drawLandscape(); drawTracks(); drawLocomotive(); drawTrainCar(1); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,W,H)
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",255,185,450,330,16,16)
      local cost=travelCost(); love.graphics.setColor(colors.cream); love.graphics.printf("TRAVEL TO STOP "..(runtime.saveData.location+1),275,220,410,"center",0,1.5,1.5)
      love.graphics.printf("Distance, terrain, passengers, and train condition shape this leg.\nThis journey will consume:",300,275,360,"center")
      love.graphics.printf(cost.food.." FOOD     "..cost.water.." WATER     "..cost.coal.." COAL",280,350,400,"center",0,1.2,1.2)
      local terrain=TrainUpgradeBalance.revealsTerrain(runtime.saveData) and string.upper(cost.terrain or "plains") or "UNCHARTED — NAVIGATOR REQUIRED"
      if (cost.navigatorSaved or 0)>0 then terrain=terrain.."  •  SAVES 1 COAL" end
      love.graphics.printf("TERRAIN: "..terrain,280,377,400,"center",0,.78,.78)
      if cost.passengers>0 then love.graphics.printf(cost.passengers.." passenger"..(cost.passengers==1 and "" or "s").." add "..cost.passengerLoad.." food and water.",280,385,400,"center",0,0.82,0.82) end
      if cost.maintenanceCoal>0 then love.graphics.setColor(colors.red); love.graphics.printf("LOW MAINTENANCE ADDS +"..cost.maintenanceCoal.." COAL",280,404,400,"center",0,.68,.68) end
      local enough=runtime.saveData.resources.food>=cost.food and runtime.saveData.resources.water>=cost.water and runtime.saveData.resources.coal>=cost.coal
      local mobile=mobileEnabled()
      ui.travelYes=button(enough and "CONFIRM JOURNEY" or "NOT ENOUGH SUPPLIES",mobile and 275 or 305,420,mobile and 270 or 220,mobile and 68 or 48,enough); ui.travelNo=button("CANCEL",mobile and 565 or 545,420,mobile and 150 or 110,mobile and 68 or 48,true)
  end

  function ui.drawRandomEvent()
      drawLandscape(); love.graphics.setColor(0,0,0,0.76); love.graphics.rectangle("fill",0,0,W,H)
      ui.eventChoices=EventUI.draw(runtime.randomEvent,scenery.eventArt,drawMenuFrame,button,colors,runtime.saveData.eventProgress or {},canChooseEvent)
  end

  local function ownsTrainCar(id) return TrainUpgradeBalance.owns(runtime.saveData,id) end
  function ui.drawTrainUpgrades()
      local mobile=mobileEnabled()
      love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,W,H)
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",150,70,660,580,16,16)
      love.graphics.setColor(colors.brass); love.graphics.printf("TRAIN WORKSHOP",150,95,660,"center",0,1.7,1.7)
      local engine=EngineUpgrades.profile(runtime.saveData.engineLevel); local engineStatus=TrainUpgradeBalance.engineStatus(runtime.saveData,EngineUpgrades); local nextEngine=engineStatus.entry
      love.graphics.setColor(colors.cream); love.graphics.printf("Scrap: "..runtime.saveData.scrap.."   •   Buy cars and improve your locomotive",170,132,620,"center")
      love.graphics.setColor(.25,.18,.12); love.graphics.rectangle("fill",185,158,590,62,7,7)
      love.graphics.setColor(colors.brass); love.graphics.print("ENGINE  "..engine.name,205,166,0,.88,.88)
      love.graphics.setColor(colors.cream); love.graphics.print("Fuel "..math.floor(engine.coal*100).."%  •  Provisions "..math.floor(engine.supplies*100).."%  •  Speed "..math.floor(engine.speed*100).."%",205,190,0,.68,.68)
      local engineLabel=engineStatus.maximum and "MAX LEVEL" or (engineStatus.locked and ("UNLOCK "..engineStatus.unlockStop) or (nextEngine.cost.." SCRAP"))
      ui.engineUpgrade=button(engineLabel,mobile and 610 or 630,mobile and 162 or 170,mobile and 155 or 125,mobile and 54 or 36,engineStatus.affordable==true)
      ui.trainCars={}
      for i,c in ipairs(Catalog.trainCarCatalog) do local y=230+(i-1)*58; local status=TrainUpgradeBalance.carStatus(runtime.saveData,c); love.graphics.setColor(.25,.18,.12); love.graphics.rectangle("fill",185,y,590,52,7,7); love.graphics.setColor(colors.cream); love.graphics.printf(c.name.."  —  "..c.description,205,y+8,400,"left",0,.68,.68); local label=status.owned and "OWNED" or (status.locked and ("UNLOCK "..status.unlockStop) or c.cost.." SCRAP"); ui.trainCars[i]=button(label,mobile and 610 or 630,y+(mobile and 1 or 6),mobile and 155 or 125,mobile and 50 or 34,status.affordable) end
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
      drawLandscape(); love.graphics.setColor(0.08,0.05,0.03,0.72); love.graphics.rectangle("fill",0,0,W,H)
      love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",120,90,720,540,20,20)
      love.graphics.setColor(colors.brass); love.graphics.printf("CALIFORNIA",120,135,720,"center",0,2.2,2.2)
      love.graphics.setColor(colors.cream); love.graphics.printf("After 50 stops, the Mouse Frontier finally reaches the end of the line.",205,215,550,"center",0,1.15,1.15)
      love.graphics.printf("You found your family. The old train became a lifeline for every critter you met along the way—and your journey west became a story they will tell for generations.",220,285,520,"center")
      local family={runtime.saveData.character,(runtime.saveData.npcRoster or {})[1],(runtime.saveData.npcRoster or {})[2]}
      for i,file in ipairs(family) do local img=characterImages[file] or npcImages[file]; if img then local s=math.min(105/img:getWidth(),145/img:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(img,360+(i-1)*120,475+math.sin(runtime.animationClock*3+i)*3,0,s,s,img:getWidth()/2,img:getHeight()/2) end end
      ui.endingButton=button("RETURN TO SAVE FILES",350,560,260,48,true)
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
