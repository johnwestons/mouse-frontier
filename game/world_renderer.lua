local WeaponAttachment = require("game.weapon_attachment")

local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"world renderer requires "..name)
  if expected then assert(type(value)==expected,"world renderer "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","world renderer requires a context")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local backgroundImages=required(context,"backgroundImages","table")
  local scenery=required(context,"scenery","table")
  local car=required(context,"car","table")
  local colors=required(context,"colors","table")
  local getCharacterAnimations=required(context,"getCharacterAnimations","function")
  local characterImages=required(context,"characterImages","table")
  local characterWalkImages=required(context,"characterWalkImages","table")
  local characterActionImages=required(context,"characterActionImages","table")
  local itemIdleImages=required(context,"itemIdleImages","table")
  local npcImages=required(context,"npcImages","table")
  local npcWalkImages=required(context,"npcWalkImages","table")
  local familyImages=required(context,"familyImages","table")
  local mobImages=required(context,"mobImages","table")
  local mobIdleImages=required(context,"mobIdleImages","table")
  local mobWalkImages=required(context,"mobWalkImages","table")
  local mobHitImages=required(context,"mobHitImages","table")
  local mobDeathImages=required(context,"mobDeathImages","table")
  local drawStopSludges=required(context,"drawStopSludges","function")
  local drawStopActivity=required(context,"drawStopActivity","function")
  local drawWildlife=required(context,"drawWildlife","function")
  local Train=required(context,"train","table")
  local CharacterAnimation=required(context,"characterAnimation","table")
  local Catalog=required(context,"catalog","table")
  local Family=required(context,"family","table")
  local Settlements=required(context,"settlements","table")
  local Stops=required(context,"stops","table")
  local Util=required(context,"util","table")
  local ui=required(context,"ui","table")
  local itemIsHere=required(context,"itemIsHere","function")
  local pendingMailHere=required(context,"pendingMailHere","function")
  local ensureStopLayout=required(context,"ensureStopLayout","function")

  local function drawLandscape()
      local backgroundCount=#backgroundImages
      local image = backgroundCount>0 and backgroundImages[((runtime.saveData.location-1)%backgroundCount)+1] or nil
      if image then
          local s=math.max(W/image:getWidth(), H/image:getHeight())
          local iw=image:getWidth()*s; local offset=runtime.landscapeOffset%iw; love.graphics.setColor(0.78,0.78,0.78)
          for x=offset-iw, W+iw, iw do love.graphics.draw(image,x,0,0,s,s) end
      else love.graphics.clear(0.55,0.37,0.20) end
  end

  local function sludgeImages()
      local generated=scenery.sludgeAnimations or {}
      return {
          idle=generated.idle or mobIdleImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
          walk=generated.walk or mobWalkImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
          attack=generated.attack,
          hit=generated.hit or mobHitImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"],
          death=generated.death or mobDeathImages["sludge-crawler.png"] or mobImages["sludge-crawler.png"]
      }
  end

  local function drawTracks()
      if Train.drawTracks(scenery.track,W) then return end
      -- Fallback track uses the same rail baseline as the artwork-backed path.
      local railY=Train.railY
      local farRailY=railY-(414-300)*(W/2172)
      love.graphics.setColor(0.16,0.12,0.09); love.graphics.rectangle("fill",0,farRailY-2,W,12); love.graphics.rectangle("fill",0,railY-2,W,12)
      love.graphics.setColor(0.28,0.20,0.12)
      for x=runtime.sceneryOffset%70-70, W,70 do love.graphics.rectangle("fill",x,farRailY-12,18,railY-farRailY+34) end
      love.graphics.setColor(0.52,0.48,0.42); love.graphics.rectangle("fill",0,farRailY+2,W,5); love.graphics.rectangle("fill",0,railY+2,W,5)
  end

  local function drawLocomotive()
      local frames=scenery.worldTrainFrames or {}; local frameIndex=(math.floor(runtime.trainAnimationClock)%3)+1; local image=frames[frameIndex] or scenery.worldTrain
      if not image then return end
      Train.drawLocomotive(image,frames[frameIndex] and frameIndex or nil,car)
  end

  local function drawTrainCar(index)
      local x=car.x; local y=car.y
      local carId=runtime.saveData.trainCars and runtime.saveData.trainCars[index]
      local carImage=carId and scenery.trainCarImages and scenery.trainCarImages[carId]
      if carImage then
          Train.drawCarImage(carImage,car)
          if index==1 then
              if scenery.boiler then local s=150/scenery.boiler:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.boiler,x+165,y+244,0,s,s,scenery.boiler:getWidth()/2,scenery.boiler:getHeight()/2) end
              local fireFrame=scenery.fireFrames and scenery.fireFrames[(math.floor(runtime.animationClock/0.55)%#scenery.fireFrames)+1] or scenery.fire
              if fireFrame then local s=48/fireFrame:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(fireFrame,x+165,y+252,0,s,s,fireFrame:getWidth()/2,fireFrame:getHeight()/2) end
          end
          return
      end
      love.graphics.setColor(0.10,0.09,0.08); love.graphics.circle("fill",x+35,y+car.h+13,22); love.graphics.circle("fill",x+car.w-35,y+car.h+13,22)
      love.graphics.setColor(colors.brass); love.graphics.circle("line",x+35,y+car.h+13,13); love.graphics.circle("line",x+car.w-35,y+car.h+13,13)
      love.graphics.setColor(colors.trim); love.graphics.polygon("fill",x-8,y+18,x+8,y,x+car.w-18,y,x+car.w+8,y+18,x+car.w+8,y+car.h,x-8,y+car.h)
      love.graphics.setColor(colors.wall); love.graphics.polygon("fill",x,y+18,x+car.w,y+18,x+car.w,y+car.h-10,x+12,y+car.h-10,x,y+car.h-32)
      for wx=x+25,x+car.w-60,110 do
          love.graphics.setColor(colors.trim); love.graphics.rectangle("fill",wx-4,y+30,48,76,5,5)
          love.graphics.setColor(0.52,0.72,0.76); love.graphics.rectangle("fill",wx,y+34,40,68,3,3)
          love.graphics.setColor(1,1,1,0.18); love.graphics.rectangle("fill",wx+5,y+39,7,55)
          if scenery.curtain then local cs=84/scenery.curtain:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.curtain,wx+20,y+68,0,cs,cs,scenery.curtain:getWidth()/2,scenery.curtain:getHeight()/2) end
      end
      local fy=y+118; love.graphics.setColor(colors.floorA); love.graphics.rectangle("fill",x+10,fy,car.w-20,car.h-128)
      if scenery.homeTexture then love.graphics.setColor(1,1,1); love.graphics.draw(scenery.homeTexture,x+10,fy,0,(car.w-20)/scenery.homeTexture:getWidth(),(car.h-128)/scenery.homeTexture:getHeight())
      else love.graphics.setColor(colors.floorB); for yy=fy, y+car.h-10,25 do love.graphics.rectangle("fill",x+10,yy,car.w-20,3) end end
      love.graphics.setColor(0.20,0.22,0.23); love.graphics.rectangle("line",x+10,fy,car.w-20,car.h-128)
      love.graphics.setColor(colors.brass); for rx=x+20,x+car.w-18,36 do love.graphics.circle("fill",rx,fy+5,2) end
      love.graphics.setColor(colors.trim); love.graphics.rectangle("fill",x-5,y+143,12,72); love.graphics.rectangle("fill",x+car.w-7,y+143,12,72)
      if index==1 then
          if scenery.boiler then local s=150/scenery.boiler:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.boiler,x+105,y+194,0,s,s,scenery.boiler:getWidth()/2,scenery.boiler:getHeight()/2)
          else love.graphics.setColor(0.12,0.10,0.08); love.graphics.rectangle("fill",x+38,y+135,135,118,12,12) end
          local fireFrame=scenery.fireFrames and scenery.fireFrames[(math.floor(runtime.animationClock/0.55)%#scenery.fireFrames)+1] or scenery.fire
          if fireFrame then local s=48/fireFrame:getHeight(); love.graphics.setColor(1,1,1); love.graphics.draw(fireFrame,x+105,y+202,0,s,s,fireFrame:getWidth()/2,fireFrame:getHeight()/2) end
      end
  end

  local function drawAnimatedCharacter(file,action,x,y,maxW,maxH,facing,phase)
      return CharacterAnimation.draw(getCharacterAnimations(),file,action,x,y,maxW,maxH,facing,phase,runtime.animationClock)
  end

  local function drawPlayer()
      if not runtime.player.image then return end
      if getCharacterAnimations()[runtime.saveData.character] then
          if runtime.player.moving and runtime.actionTimer<=0 then
              love.graphics.setColor(0,0,0,0.28); love.graphics.ellipse("fill",runtime.player.x,runtime.player.y+28,20,7)
              if drawAnimatedCharacter(runtime.saveData.character,"walk",runtime.player.x,runtime.player.y+34,82,104,runtime.player.facing,runtime.animationClock) then return end
          end
          if not runtime.player.moving or runtime.actionTimer>0 then
              local action=runtime.actionTimer>0 and (runtime.actionKind or "use") or (runtime.playerPose=="sit" and "sit" or (runtime.playerPose=="lay" and "lay" or "idle"))
              love.graphics.setColor(0,0,0,0.28); love.graphics.ellipse("fill",runtime.player.x,runtime.player.y+28,20,7)
              local actionPhase=runtime.actionTimer>0 and math.max(0,.35-runtime.actionTimer) or runtime.animationClock
              drawAnimatedCharacter(runtime.saveData.character,action,runtime.player.x,runtime.player.y+34,82,104,runtime.player.facing,actionPhase)
              if runtime.actionTimer>0 and runtime.actionHeldItem then
                  local combat=Catalog.weaponCombat[runtime.actionHeldItem]
                  local attached=combat and (action=="melee" or action=="ranged") and WeaponAttachment.draw(
                      getCharacterAnimations(),runtime.saveData.character,runtime.actionHeldItem,
                      WeaponAttachment.itemSprite(ui,runtime.actionHeldItem),runtime.player.x,runtime.player.y+34,
                      82,104,runtime.player.facing,actionPhase,action,combat
                  )
                  if not attached then ui.drawItem(runtime.actionHeldItem,{x=runtime.player.x+(runtime.player.facing==1 and 12 or -42),y=runtime.player.y-22,w=32,h=32}) end
              end
              return
          end
      end
      local actionImage=runtime.actionTimer>0 and characterActionImages[runtime.saveData.character]
      local image,drawFacing,scale=actionImage or runtime.player.image,-runtime.player.facing,runtime.player.scale
      -- Action sheets use much more of their canvas than the idle portraits. Match
      -- their visible body size, not only the PNG canvas height.
      if actionImage then scale=((runtime.player.image:getHeight()*runtime.player.scale)/actionImage:getHeight())*.78 end
      if runtime.player.moving and runtime.actionTimer<=0 then
          local walk=characterWalkImages[runtime.saveData.character]
          if walk then image=walk; drawFacing=-runtime.player.facing; scale=math.min(0.075,90/image:getHeight()) end
      end
      local bob=0
      love.graphics.setColor(0,0,0,0.28); love.graphics.ellipse("fill",runtime.player.x,runtime.player.y+28,20,7)
      local rotation,scaleY,yOffset=0,scale,0
      if runtime.playerPose=="sit" then scaleY=scale*.72; yOffset=10 elseif runtime.playerPose=="lay" then rotation=math.pi/2; scaleY=scale*.82; yOffset=16 end
      love.graphics.setColor(1,1,1); love.graphics.draw(image,runtime.player.x,runtime.player.y+bob+yOffset,rotation,scale*drawFacing,scaleY,image:getWidth()/2,image:getHeight()/2)
  end

  local function drawDroppedItems(carIndex)
      local cacheKey=carIndex and ("train:"..tostring(carIndex)) or (runtime.scene..":"..tostring(runtime.saveData.location)..":"..tostring(runtime.saveData.activeHouseDoor or 0))
      local revision=ui.itemOrderRevision or 0
      ui.itemOrderCache=ui.itemOrderCache or {}
      local cached=ui.itemOrderCache[cacheKey]
      local ordered
      if cached and cached.revision==revision then ordered=cached.items else
          ordered={}
          for i,item in ipairs(runtime.saveData.droppedItems) do
              local visible=carIndex and item.scene=="train" and (item.carIndex or 1)==carIndex or (not carIndex and itemIsHere(item))
              if visible then ordered[#ordered+1]={index=i,item=item} end
          end
          table.sort(ordered,function(a,b) return (a.item.layer or a.index)<(b.item.layer or b.index) end)
          ui.itemOrderCache[cacheKey]={revision=revision,items=ordered}
      end
      for _,entry in ipairs(ordered) do local i,item=entry.index,entry.item
          local img=ui.propImages[item.name]; local scale=item.scale or 1; local rotation=item.rotation or 0
          if img then
              local idleFrames=itemIdleImages[item.name]
              if idleFrames and not runtime.editMode then img=idleFrames[(math.floor(runtime.animationClock/1.05)%#idleFrames)+1] or img end
              local s=math.min(58/img:getWidth(),58/img:getHeight())*scale
              local plant=not idleFrames and (item.name:find("tree") or item.name:find("plant") or item.name:find("potted") or item.name:find("flower") or item.name:find("sprout") or item.name:find("fern") or item.name:find("shrub") or item.name:find("reeds") or item.name:find("herb") or item.name:find("mushroom"))
              love.graphics.setColor(1,1,1)
              local tintShader=ui.objectTintShader
              if tintShader then tintShader:send("hueShift",item.hue or 0); tintShader:send("saturation",item.saturation or 1); love.graphics.setShader(tintShader) end
              if plant and not runtime.editMode then
                  local phase=(item.x*.017+item.y*.011); local sway=math.sin(runtime.animationClock*.85+phase)*math.rad(.75); local bob=math.sin(runtime.animationClock*1.05+phase)*.45
                  local bottom=item.y+img:getHeight()*s/2
                  love.graphics.draw(img,item.x,bottom+bob,rotation+sway,s,s,img:getWidth()/2,img:getHeight())
              else love.graphics.draw(img,item.x,item.y,rotation,s,s,img:getWidth()/2,img:getHeight()/2) end
              if tintShader then love.graphics.setShader() end
          else ui.drawItem(item.name,{x=item.x-30*scale,y=item.y-30*scale,w=60*scale,h=60*scale}) end
          if item.name=="mailbox-reward" and item.mailUnread and ui.propImages["family-letter"] and not runtime.editMode then
              local mail=ui.propImages["family-letter"]; local ms=28/math.max(mail:getWidth(),mail:getHeight())
              love.graphics.setColor(1,1,1); love.graphics.draw(mail,item.x,item.y-48+math.sin(runtime.animationClock*3)*3,0,ms,ms,mail:getWidth()/2,mail:getHeight()/2)
          end
          if runtime.editMode and (not carIndex or carIndex==(runtime.saveData.activeCar or 1)) then local hx,hy=item.x+31,item.y+31; love.graphics.setColor(1,.78,.1); love.graphics.rectangle("fill",hx-7,hy-7,14,14); love.graphics.setColor(colors.ink); love.graphics.rectangle("line",hx-7,hy-7,14,14); if runtime.editedItem==i then love.graphics.setColor(colors.brass); love.graphics.setLineWidth(3); love.graphics.circle("line",item.x,item.y,38); love.graphics.setLineWidth(1) end end
      end
  end

  local function trainItemAt(x,y)
      local best,bestLayer=nil,-math.huge
      for i,item in ipairs(runtime.saveData.droppedItems) do
          if itemIsHere(item) then
              local hx,hy=item.x+31,item.y+31
              if math.abs(x-hx)<=14 and math.abs(y-hy)<=14 and (item.layer or i)>bestLayer then best,bestLayer=i,item.layer or i end
          end
      end
      return best
  end

  local function drawNPC()
      local npcFile=runtime.saveData.currentNPC; local img=npcFile and (npcImages[npcFile] or characterImages[npcFile])
      if not (img and runtime.npcActor) then return end
      local idle=0
      if runtime.npcActor.targetX and getCharacterAnimations()[npcFile] then
          love.graphics.setColor(0,0,0,0.24); love.graphics.ellipse("fill",runtime.npcActor.x,runtime.npcActor.y+28,20,7)
          if drawAnimatedCharacter(npcFile,"walk",runtime.npcActor.x,runtime.npcActor.y+34,82,104,runtime.npcActor.facing or 1,runtime.animationClock) then
              love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(npcFile),runtime.npcActor.x-100,runtime.npcActor.y+50,200,"center")
              Family.draw(runtime.npcActor,familyImages,runtime.animationClock)
              return
          end
      elseif runtime.npcActor.targetX and (npcWalkImages[npcFile] or characterWalkImages[npcFile]) then img=npcWalkImages[npcFile] or characterWalkImages[npcFile] end
      local s=math.min(0.075,90/img:getHeight()); local facing=-(runtime.npcActor.facing or 1)
      if runtime.npcActor.targetX and (npcWalkImages[npcFile] or characterWalkImages[npcFile]) then facing=-facing end
      love.graphics.setColor(0,0,0,0.24); love.graphics.ellipse("fill",runtime.npcActor.x,runtime.npcActor.y+28,20,7)
      if not runtime.npcActor.targetX and drawAnimatedCharacter(npcFile,"idle",runtime.npcActor.x,runtime.npcActor.y+34,82,104,facing) then else love.graphics.setColor(1,1,1); love.graphics.draw(img,runtime.npcActor.x,runtime.npcActor.y+idle,0,s*facing,s,img:getWidth()/2,img:getHeight()/2) end
      love.graphics.setColor(colors.cream); love.graphics.printf(Util.titleFromFile(npcFile),runtime.npcActor.x-100,runtime.npcActor.y+50,200,"center")
      if pendingMailHere() and ui.propImages["family-letter"] then local mail=ui.propImages["family-letter"]; local ms=34/math.max(mail:getWidth(),mail:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(mail,runtime.npcActor.x,runtime.npcActor.y-82+math.sin(runtime.animationClock*4)*3,0,ms,ms,mail:getWidth()/2,mail:getHeight()/2) end
      Family.draw(runtime.npcActor,familyImages,runtime.animationClock)
  end

  local function drawPassengers(carIndex)
      local visibleCar=carIndex or (runtime.saveData.activeCar or 1)
      for i,passenger in ipairs(runtime.saveData.passengers or {}) do
          if (passenger.carIndex or 1)==visibleCar then
          local moving=passenger.targetX~=nil; local legacyWalk=moving and (npcWalkImages[passenger.npc] or characterWalkImages[passenger.npc]); local img=legacyWalk or npcImages[passenger.npc] or characterImages[passenger.npc]
          if img then local s=math.min(.075,90/img:getHeight()); local face=passenger.facing or 1; love.graphics.setColor(0,0,0,0.22); love.graphics.ellipse("fill",passenger.x,passenger.y+28,20,7); if drawAnimatedCharacter(passenger.npc,moving and "walk" or (passenger.pose or "idle"),passenger.x,passenger.y+34,82,104,face,runtime.animationClock+i*.2) then else love.graphics.setColor(1,1,1); love.graphics.draw(img,passenger.x,passenger.y,0,s*(legacyWalk and -face or -face),s,img:getWidth()/2,img:getHeight()/2) end end
          end
      end
  end

  local function drawGround()
      if scenery.stopGround then
          local atlas=scenery.stopGround; local index=((runtime.saveData.location-1)%4)+1
          love.graphics.setColor(1,1,1)
          -- Draw one continuous surface. Repeating this non-seamless artwork in
          -- 320-pixel strips exposed the left/right borders of every copy.
          love.graphics.draw(atlas.image,atlas.quads[index],0,360,0,W/atlas.w,360/atlas.h)
          return
      end
      love.graphics.setColor(0.27,0.38,0.16); love.graphics.rectangle("fill",0,430,W,290)
      love.graphics.setColor(0.34,0.48,0.20)
      for y=442,710,24 do for x=(y/24%2)*18,950,36 do love.graphics.rectangle("fill",x,y,3,7) end end
      love.graphics.setColor(0.55,0.45,0.28)
      love.graphics.polygon("fill",120,720,255,590,440,548,610,520,960,555,960,635,650,590,460,610,300,655,230,720)
      love.graphics.setColor(0.66,0.56,0.36)
      for x=245,900,75 do love.graphics.rectangle("fill",x,590-math.sin(x)*25,18,8) end
  end

  local function drawStop()
      if scenery.settlements and Settlements.draw(scenery.settlements,runtime.saveData.location,W,H) then
          local trainX,trainY=Settlements.trainPoint(runtime.saveData.location)
          if scenery.redTrain then
              local image=scenery.redTrain; local scale=52/math.max(image:getWidth(),image:getHeight())
              love.graphics.setColor(1,1,1,.92)
              love.graphics.draw(image,trainX,trainY-8,0,scale,scale,image:getWidth()/2,image:getHeight()/2)
          end
          love.graphics.setColor(1,.78,.12,.78)
          love.graphics.circle("line",trainX,trainY+math.sin(runtime.animationClock*3)*2,12)
          love.graphics.setColor(colors.cream)
          love.graphics.printf("Q",trainX-12,trainY-5,24,"center",0,.7,.7)
          drawStopActivity()
          drawDroppedItems()
          drawStopSludges(sludgeImages())
          drawWildlife(ensureStopLayout())
          drawNPC(); drawPlayer(); return
      end
      drawGround()
      local env=scenery.environment or {}
      local homes={"house-overgrown","house-purple","house-shed","home-water-tower","home-roadside-diner","home-burrow-mound","home-general-store","home-signal-cabin"}
      local trees={"tree-broadleaf","tree-flowering","tree-dead-cloth","tree-cottonwood","tree-mushroom","tree-burned-regrowth","tree-apple-swing"}
      local layout=(runtime.scene=="house" and Stops.ensureDoor(runtime.saveData,Catalog,runtime.saveData.activeHouseDoor or runtime.saveData.lastStopDoor)) or ensureStopLayout()
      local decorations={}; for i,decoration in ipairs(layout.decorations or {}) do decorations[i]=decoration end; table.sort(decorations,function(a,b) return a.y<b.y end)
      for _,decoration in ipairs(decorations) do
          local pool=decoration.kind=="wildlife" and scenery.stopWildlife or scenery.stopProps; local image=pool and pool[decoration.name]
          if image then
              local name=decoration.name or ""; local wildlife=decoration.kind=="wildlife"; local plant=not wildlife and (name:find("tree") or name:find("birch") or name:find("flower") or name:find("shrub") or name:find("fern") or name:find("reeds") or name:find("herb") or name:find("mushroom") or name:find("bush") or name:find("cactus"))
              local phase=decoration.x*.019+decoration.y*.013
              local feeding=scenery.stopWildlifeFeeding and scenery.stopWildlifeFeeding[name]
              if wildlife and feeding then local cycle=(runtime.animationClock+phase)%6.4; if cycle>=2.2 and cycle<5.4 then image=feeding end end
              local sway=plant and math.sin(runtime.animationClock*.72+phase)*math.rad(name:find("tree") and .85 or .55) or 0
              local bob=plant and math.sin(runtime.animationClock*.9+phase)*.55 or 0
              love.graphics.setColor(1,1,1); love.graphics.draw(image,decoration.x,decoration.y+bob,sway,decoration.scale,decoration.scale,image:getWidth()/2,image:getHeight())
          end
      end
      local house=env[homes[layout.house or 1]]
      local treeA,treeB=env[trees[layout.tree or 1]],env[trees[((layout.tree or 1)%#trees)+1]]
      if treeA then local x=layout.treeA or 135; local s=210/treeA:getHeight(); local sway=math.sin(runtime.animationClock*.64+x*.021)*math.rad(.9); love.graphics.setColor(1,1,1); love.graphics.draw(treeA,x,480,sway,s,s,treeA:getWidth()/2,treeA:getHeight()) end
      if treeB then local x=layout.treeB or 830; local s=180/treeB:getHeight(); local sway=math.sin(runtime.animationClock*.67+x*.019+1.7)*math.rad(.8); love.graphics.draw(treeB,x,495,sway,s,s,treeB:getWidth()/2,treeB:getHeight()) end
      if house then local s=280/house:getHeight(); love.graphics.draw(house,layout.houseX or 520,515,0,s,s,house:getWidth()/2,house:getHeight()) end
      if scenery.redTrain then local s=74/math.max(scenery.redTrain:getWidth(),scenery.redTrain:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(scenery.redTrain,145,405,0,s,s,scenery.redTrain:getWidth()/2,scenery.redTrain:getHeight()/2) end
      love.graphics.setColor(1,.78,.12,.72); love.graphics.circle("line",145,425+math.sin(runtime.animationClock*3)*2,11); love.graphics.setColor(colors.cream); love.graphics.printf("Q",133,421,24,"center",0,.7,.7)
      drawStopActivity()
      drawDroppedItems()
      drawStopSludges(sludgeImages())
      drawWildlife(layout)
      drawNPC(); drawPlayer()
  end

  local function drawHouse()
      drawLandscape()
      local layout=ensureStopLayout()
      local interior=ui.assetStreamer and ui.assetStreamer:getInterior(layout.interior or 1)
      if interior then
          love.graphics.setColor(1,1,1)
          love.graphics.draw(interior,105,205,0,750/interior:getWidth(),445/interior:getHeight())
      else
          love.graphics.setColor(0.23,0.14,0.09); love.graphics.rectangle("fill",105,205,750,445,12,12)
          love.graphics.setColor(0.63,0.48,0.29); love.graphics.rectangle("fill",125,225,710,405)
          if scenery.homeTexture then love.graphics.setColor(1,1,1); love.graphics.draw(scenery.homeTexture,125,225,0,710/scenery.homeTexture:getWidth(),405/scenery.homeTexture:getHeight()) end
      end
      drawDroppedItems(); drawNPC(); drawPlayer()
  end
  
  local function drawTrainView(focusIndex,offsetX,playerCar,playerX,playerY)
      love.graphics.push(); love.graphics.translate(offsetX or 0,0)
      if focusIndex==1 then
          drawLocomotive()
      end
      drawTrainCar(focusIndex); drawDroppedItems(focusIndex); drawPassengers(focusIndex)
      if playerCar==focusIndex then
          love.graphics.push(); love.graphics.translate((playerX or runtime.player.x)-runtime.player.x,(playerY or runtime.player.y)-runtime.player.y); drawPlayer(); love.graphics.pop()
      end
      love.graphics.pop()
  end

  return {
    drawLandscape=drawLandscape,
    drawTracks=drawTracks,
    drawLocomotive=drawLocomotive,
    drawTrainCar=drawTrainCar,
    drawAnimatedCharacter=drawAnimatedCharacter,
    drawPlayer=drawPlayer,
    drawDroppedItems=drawDroppedItems,
    trainItemAt=trainItemAt,
    drawNPC=drawNPC,
    drawPassengers=drawPassengers,
    drawGround=drawGround,
    drawStop=drawStop,
    drawHouse=drawHouse,
    drawTrainView=drawTrainView
  }
end

return {new=new}
