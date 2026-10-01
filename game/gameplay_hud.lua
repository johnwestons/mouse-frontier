local WorldView=require("game.world_view")
local AudioCatalog = require("game.audio_catalog")
local Accessibility = require("game.accessibility")
local WorldPause = require("game.world_pause")
local Typography = require("game.typography")
local TrainView = require("game.train_view")
local WideLayout = require("game.wide_layout")
local UIStyle = require("game.ui_layout")

local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"gameplay HUD requires "..name)
  if expected then assert(type(value)==expected,"gameplay HUD "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","gameplay HUD requires a context")
  local runtime=required(context,"runtime","table")
  local W=required(context,"width","number")
  local H=required(context,"height","number")
  local ui=required(context,"ui","table")
  local colors=required(context,"colors","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local HOLD_PICKUP_SECONDS=required(context,"holdPickupSeconds","number")
  local getCloudLayer=required(context,"getCloudLayer","function")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local TrainUpgradeBalance=required(context,"trainUpgradeBalance","table")
  local Clouds=required(context,"clouds","table")
  local Maintenance=required(context,"maintenance","table")
  local FirstAid=required(context,"firstAid","table")
  local ShootingRange=required(context,"shootingRange","table")
  local LastStand=required(context,"lastStand","table")
  local Catalog=required(context,"catalog","table")
  local scenery=required(context,"scenery","table")
  local npcImages=required(context,"npcImages","table")
  local Util=required(context,"util","table")
  local Train=required(context,"train","table")
  local button=required(context,"button","function")
  local drawMenuFrame=required(context,"drawMenuFrame","function")
  local drawTrade=required(context,"drawTrade","function")
  local isFurnitureItem=required(context,"isFurnitureItem","function")
  local containerValue=required(context,"containerValue","function")
  local travelStatus=required(context,"travelStatus","function")
  local questSummary=required(context,"questSummary","function")
  local screenToGame=required(context,"screenToGame","function")
  local getTrainView=required(context,"getTrainView","function")
  local pointerPosition=required(context,"pointerPosition","function")
  local getAudioStatus=required(context,"getAudioStatus","function")
  local drawLandscape=required(context,"drawLandscape","function")
  local drawTracks=required(context,"drawTracks","function")
  local drawTrainView=required(context,"drawTrainView","function")
  local drawHouse=required(context,"drawHouse","function")
  local drawStop=required(context,"drawStop","function")
  local drawExpedition=required(context,"drawExpedition","function")
  local expeditionObjective=required(context,"expeditionObjective","function")
  local drawExpeditionLocalMap=required(context,"drawExpeditionLocalMap","function")
  local drawCaravan=required(context,"drawCaravan","function")
  local controlBindings=required(context,"controlBindings","table")

  local function textIn(text,x,y,width,height,scale,align)
      return Typography.drawText(love.graphics,text,x,y,width,height,{
          scale=(scale or 1)*Accessibility.textScale(runtime.saveData or ui.menuSettings or {}),
          minScale=mobileEnabled() and .85 or .65,align=align or "left",valign="center",
      })
  end

  local function optionsData()
      local data=runtime.saveData or ui.menuSettings
      data.audio=data.audio or {station="chill",musicVolume=.10,sfxVolume=.55,rainVolume=.20,rainEnabled=true,musicPaused=false,musicMuted=false}
      Accessibility.ensure(data)
      return data
  end

  local function drawOptionsRaw()
      if not ui.optionsOpen then return end
      local settings=optionsData()
      ui.musicDown=nil; ui.musicUp=nil; ui.sfxDown=nil; ui.sfxUp=nil; ui.rainDown=nil; ui.rainUp=nil
      ui.musicPrevious=nil; ui.musicPause=nil; ui.musicNext=nil; ui.musicMute=nil
      ui.optionsStation8bit=nil; ui.optionsStationChill=nil; ui.optionsStationVibes=nil; ui.optionsStationRain=nil
      ui.optionsAudioTab=nil; ui.optionsAccessTab=nil; ui.optionsControlsTab=nil; ui.optionsBack=nil; ui.controlsEditorButton=nil
      ui.controlsKeyboardTab=nil; ui.controlsControllerTab=nil; ui.controlsTouchTab=nil
      ui.controlsButtonsTab=nil; ui.controlsAxesTab=nil; ui.controlBindingRows=nil
      ui.controlBindingVisibleRows=nil
      ui.controlsReset=nil; ui.controlsScrollUp=nil; ui.controlsScrollDown=nil
      ui.accessTextSize=nil; ui.accessHighContrast=nil; ui.accessReducedMotion=nil
      ui.accessControlHints=nil; ui.accessTouchFeedback=nil; ui.accessLargeTouchTargets=nil
      runtime.optionsPage=runtime.optionsPage or "audio"
      local mobile=mobileEnabled()
      local expanded=runtime.optionsPage=="controls"
      local panelX,panelY,panelW,panelH
      if expanded then panelX,panelY,panelW,panelH=42,26,876,668
      else panelX,panelY,panelW,panelH=mobile and 90 or 485,mobile and 55 or 125,mobile and 780 or 460,mobile and 615 or 525 end
      drawMenuFrame(panelX,panelY,panelW,panelH,2,.99); love.graphics.setColor(colors.cream)
      textIn("SETTINGS",panelX+20,panelY+18,panelW-(mobile and 185 or 150),38,mobile and 1.28 or .90,"left")
      ui.optionsBack=button("BACK",panelX+panelW-(mobile and 160 or 120),panelY+14,mobile and 130 or 96,mobile and 52 or 34,true,mobile and 1 or .72)
      local tabW=(panelW-100)/3
      ui.optionsAudioTab=button("AUDIO",panelX+35,panelY+68,tabW,mobile and 58 or 42,runtime.optionsPage=="audio",mobile and .90 or .66)
      ui.optionsAccessTab=button("ACCESSIBILITY",panelX+50+tabW,panelY+68,tabW,mobile and 58 or 42,runtime.optionsPage=="accessibility",mobile and .84 or .62)
      ui.optionsControlsTab=button("CONTROLS",panelX+65+tabW*2,panelY+68,tabW,mobile and 58 or 42,runtime.optionsPage=="controls",mobile and .90 or .66)
      if runtime.optionsPage=="audio" then
          local labelX=panelX+65; local downX=panelX+panelW-250; local upX=panelX+panelW-135
          local row1,row2,row3=panelY+155,panelY+225,panelY+295
          love.graphics.setColor(colors.cream); textIn("MUSIC  "..math.floor((settings.audio.musicVolume or .10)*100).."%",labelX,row1,downX-labelX-20,mobile and 58 or 40,1)
          ui.musicDown=button("-",downX,row1,mobile and 95 or 58,mobile and 58 or 40,true); ui.musicUp=button("+",upX,row1,mobile and 95 or 58,mobile and 58 or 40,true)
          textIn("SOUND FX  "..math.floor((settings.audio.sfxVolume or .55)*100).."%",labelX,row2,downX-labelX-20,mobile and 58 or 40,1)
          ui.sfxDown=button("-",downX,row2,mobile and 95 or 58,mobile and 58 or 40,true); ui.sfxUp=button("+",upX,row2,mobile and 95 or 58,mobile and 58 or 40,true)
          textIn("RAIN  "..math.floor((settings.audio.rainVolume or .20)*100).."%",labelX,row3,downX-labelX-20,mobile and 58 or 40,1)
          ui.rainDown=button("-",downX,row3,mobile and 95 or 58,mobile and 58 or 40,true); ui.rainUp=button("+",upX,row3,mobile and 95 or 58,mobile and 58 or 40,true)
          local stationLabel=AudioCatalog.stationLabel(settings.audio.station or "chill")
          textIn("MUSIC STATION: "..stationLabel,labelX,panelY+338,panelW-130,28,mobile and .92 or .68)
          local stationX=panelX+45; local stationY=panelY+370; local stationGap=mobile and 10 or 8
          local stationW=(panelW-90-stationGap*3)/4; local stationH=mobile and 46 or 34
          ui.optionsStation8bit=button("8-BIT",stationX,stationY,stationW,stationH,settings.audio.station=="8bit",mobile and .88 or .62)
          ui.optionsStationChill=button("CHILL",stationX+stationW+stationGap,stationY,stationW,stationH,settings.audio.station=="chill",mobile and .88 or .62)
          ui.optionsStationVibes=button("VIBES",stationX+(stationW+stationGap)*2,stationY,stationW,stationH,settings.audio.station=="vibes",mobile and .88 or .62)
          ui.optionsStationRain=button("RAIN",stationX+(stationW+stationGap)*3,stationY,stationW,stationH,settings.audio.rainEnabled,mobile and .88 or .62)
          local audioStatus=getAudioStatus()
          local status=audioStatus.available and (audioStatus.lastError and ("ERROR: "..audioStatus.lastError) or (audioStatus.nowPlaying and ("PLAYING: "..Util.titleFromFile(audioStatus.nowPlaying:match("[^/]+$") or audioStatus.nowPlaying)) or "STARTING MUSIC...")) or "AUDIO UNAVAILABLE"
          love.graphics.setColor(audioStatus.lastError and colors.red or colors.cream); textIn(status,labelX,panelY+(mobile and 422 or 410),panelW-130,mobile and 42 or 42,mobile and .82 or .55)
          local controlsY=panelY+(mobile and 475 or 465); local bw=(panelW-90)/4
          ui.musicPrevious=button(mobile and "PREV" or "|<",panelX+30,controlsY,bw,mobile and 58 or 42,true); ui.musicPause=button(settings.audio.musicPaused and "PLAY" or "PAUSE",panelX+40+bw,controlsY,bw,mobile and 58 or 42,true,mobile and 1 or .72)
          ui.musicNext=button(mobile and "NEXT" or ">|",panelX+50+bw*2,controlsY,bw,mobile and 58 or 42,true); ui.musicMute=button(settings.audio.musicMuted and "UNMUTE" or "MUTE",panelX+60+bw*3,controlsY,bw,mobile and 58 or 42,true,mobile and 1 or .72)
      elseif runtime.optionsPage=="accessibility" then
          local access=Accessibility.ensure(settings)
          local labels={
              {"TEXT SIZE",Accessibility.textLabel(settings),"accessTextSize"},
              {"HIGH CONTRAST",access.highContrast and "ON" or "OFF","accessHighContrast"},
              {"REDUCED MOTION",access.reducedMotion and "ON" or "OFF","accessReducedMotion"},
              {"CONTROL HINTS",access.controlHints and "ON" or "OFF","accessControlHints"},
              {"TOUCH FEEDBACK",access.touchFeedback and "ON" or "OFF","accessTouchFeedback"},
              {"LARGE TOUCH TARGETS",access.largeTouchTargets and "ON" or "OFF","accessLargeTouchTargets"},
          }
          local startY=panelY+150; local rowGap=mobile and 64 or 55
          for index,entry in ipairs(labels) do
              local y=startY+(index-1)*rowGap; love.graphics.setColor(colors.cream)
              textIn((mobile and "" or (index.."  "))..entry[1],panelX+45,y,panelW-(mobile and 310 or 235),mobile and 58 or 42,mobile and 1 or .72)
              ui[entry[3]]=button(entry[2],panelX+panelW-(mobile and 245 or 180),y,mobile and 195 or 140,mobile and 58 or 42,true,mobile and 1 or .72)
          end
          local note=mobile and (runtime.saveData and "Settings save with this journey."
              or "These preferences apply now; journey settings load with a save.")
              or (runtime.saveData and "1–6 change settings  •  TAB switches tabs  •  Saved with this journey."
              or "1–6 change settings  •  TAB switches tabs  •  Preferences apply now.")
          love.graphics.setColor(colors.cream); textIn(note,panelX+45,panelY+panelH-(mobile and 67 or 47),panelW-90,mobile and 54 or 40,mobile and .90 or .60,"center")
      else
          local device=runtime.optionsControlDevice or "keyboard"
          runtime.optionsControlDevice=device
          ui.controlsKeyboardTab=button("KEYBOARD",panelX+32,panelY+116,205,40,device=="keyboard",.70)
          ui.controlsControllerTab=button("CONTROLLER",panelX+250,panelY+116,205,40,device=="controller",.70)
          ui.controlsTouchTab=button("TOUCH LAYOUT",panelX+468,panelY+116,205,40,device=="touch",.70)
          ui.controlBindingRows={}; ui.controlsReset=nil; ui.controlsScrollUp=nil; ui.controlsScrollDown=nil
          if device=="touch" then
              love.graphics.setColor(colors.cream)
              textIn("MOVE AND POSITION EVERY ON-SCREEN CONTROL",panelX+60,panelY+210,panelW-120,46,.94,"center")
              textIn("Drag the stick, action buttons, menu, back, and backpack controls. Their positions and opacity save on this device.",
                  panelX+100,panelY+268,panelW-200,76,.76,"center")
              ui.controlsEditorButton=button("OPEN TOUCH LAYOUT EDITOR",panelX+195,panelY+386,panelW-390,62,true,.82)
          else
              ui.controlsEditorButton=nil
              local list,controlDevice
              if device=="keyboard" then
                  list=controlBindings:keyActions(); controlDevice="key"
              elseif runtime.optionsControllerSection=="axes" then
                  list=controlBindings:axisActions(); controlDevice="axis"
                  ui.controlsButtonsTab=button("BUTTONS",panelX+70,panelY+163,145,34,false,.62)
                  ui.controlsAxesTab=button("STICKS + TRIGGERS",panelX+225,panelY+163,210,34,true,.62)
              else
                  list=controlBindings:buttonActions(); controlDevice="button"
                  ui.controlsButtonsTab=button("BUTTONS",panelX+70,panelY+163,145,34,true,.62)
                  ui.controlsAxesTab=button("STICKS + TRIGGERS",panelX+225,panelY+163,210,34,false,.62)
              end
              if device=="keyboard" then ui.controlsButtonsTab=nil; ui.controlsAxesTab=nil end
              local firstY=device=="controller" and panelY+207 or panelY+174
              local rowGap=mobile and 39 or (device=="controller" and 27 or 28)
              local rowHeight=mobile and 34 or (device=="controller" and 24 or 25)
              local footerY=panelY+panelH-54
              local visible=math.max(1,math.floor((footerY-firstY-8)/rowGap))
              ui.controlBindingVisibleRows=visible
              local scroll=math.max(0,tonumber(runtime.optionsControlScroll) or 0)
              scroll=math.min(scroll,math.max(0,#list-visible)); runtime.optionsControlScroll=scroll
              for offset=1,visible do
                  local index=scroll+offset; local entry=list[index]
                  if not entry then break end
                  local y=firstY+(offset-1)*rowGap
                  local prefix=entry.group and (string.upper(entry.group).."   ") or ""
                  textIn(prefix..entry.label,panelX+34,y,310,rowHeight,.63,"left")
                  local field={x=panelX+354,y=y,w=342,h=rowHeight,entryId=entry.id,device=controlDevice}
                  local capturing=controlBindings.capture and controlBindings.capture.device==controlDevice
                      and controlBindings.capture.id==entry.id
                  local value=capturing and (controlDevice=="key" and "PRESS A KEY..." or "PRESS / MOVE INPUT...")
                      or controlBindings:display(controlDevice,entry.id)
                  field.rect=button(value,field.x,field.y,field.w,field.h,capturing,.56,.9)
                  field.clear=button("CLEAR",panelX+704,y,82,rowHeight,false,.52,.78)
                  ui.controlBindingRows[#ui.controlBindingRows+1]=field
              end
              ui.controlsReset=button("RESET DEFAULTS",panelX+28,footerY,190,34,true,.60,.82)
              ui.controlsScrollUp=button("▲",panelX+panelW-110,footerY,34,34,scroll>0,.60,.82)
              ui.controlsScrollDown=button("▼",panelX+panelW-67,footerY,34,34,scroll<#list-visible,.60,.82)
              local message=controlBindings.notice or (device=="controller"
                  and (controlBindings:hasGamepad() and "Buttons and analog inputs can be remapped separately."
                      or "Connect a controller to capture its inputs.")
                  or "Select a binding, then press its new key. Escape cancels capture.")
              love.graphics.setColor(colors.cream); textIn(message,panelX+234,footerY,panelW-365,34,.58,"center")
          end
      end
  end

  local function drawOptions()
      local mobile=mobileEnabled()
      local bounds=runtime.optionsPage=="controls" and {x=42,y=26,w=876,h=668}
          or {x=mobile and 90 or 485,y=mobile and 55 or 125,w=mobile and 780 or 460,h=mobile and 615 or 525}
      return UIStyle.scope("options",bounds,drawOptionsRaw)
  end

  local function drawExpeditionProgress()
      if runtime.scene~="expedition" or runtime.mapOpen or WorldPause.isPaused(runtime,ui,maintenanceSession) then return end
      local objective=expeditionObjective()
      if not objective then return end
      return UIStyle.scope("expeditionHud",{x=16,y=16,w=300,h=58},function()
      local x,y,width,height=16,16,300,58
      ui.expeditionHudBounds={x=x,y=y,w=width,h=height}
      local health=math.max(0,tonumber(runtime.saveData.health) or 0)
      local maxHealth=math.max(1,tonumber(runtime.saveData.maxHealth) or 1)
      love.graphics.setColor(.025,.02,.016,.76)
      love.graphics.rectangle("fill",x,y,width,height,8,8)
      love.graphics.setColor(colors.brass[1],colors.brass[2],colors.brass[3],.82)
      love.graphics.rectangle("fill",x,y,3,height,2,2)
      love.graphics.setColor(colors.brass)
      textIn(objective.title or "EXPEDITION",x+12,y+4,width-24,22,.82)
      love.graphics.setColor(colors.cream)
      textIn("HP "..health.." / "..maxHealth,x+12,y+29,78,20,.64)
      love.graphics.setColor(.22,.08,.055,1)
      love.graphics.rectangle("fill",x+94,y+36,100,6,3,3)
      love.graphics.setColor(.93,.27,.20,1)
      love.graphics.rectangle("fill",x+94,y+36,100*math.max(0,math.min(1,health/maxHealth)),6,3,3)
      love.graphics.setColor(.56,.91,.84,1)
      textIn(objective.status or "",x+201,y+29,91,20,.54,"right")
      end)
  end

  local function drawMobileRadio()
      drawMenuFrame(90,62,780,610,2,.99)
      love.graphics.setColor(colors.cream); textIn("RADIO",118,80,724,40,1.30,"center")
      if ui.radioFace then
          -- The radio remains a visual prop; text sits on its own opaque display.
          love.graphics.setColor(1,1,1)
          love.graphics.draw(ui.radioFace,250,124,0,460/ui.radioFace:getWidth(),258/ui.radioFace:getHeight())
      end
      love.graphics.setColor(.055,.038,.028,.98); love.graphics.rectangle("fill",118,320,724,128,8,8)
      local audioStatus=getAudioStatus()
      local track=audioStatus.nowPlaying and Util.titleFromFile(audioStatus.nowPlaying:match("[^/]+$") or audioStatus.nowPlaying) or "Starting music..."
      love.graphics.setColor(colors.brass); textIn("NOW PLAYING",138,331,684,26,.9,"center")
      love.graphics.setColor(colors.cream); textIn(track,138,359,684,46,1.05,"center")
      textIn(AudioCatalog.stationLabel(runtime.saveData.audio.station).."  •  "..(runtime.saveData.audio.rainEnabled and "RAIN ON" or "RAIN OFF"),138,411,684,26,.9,"center")
      local stationKeys={"radio8bit","radioChill","radioVibes","radioRain","radioClose"}
      local stationLabels={"8-BIT","CHILL","VIBES","RAIN","CLOSE"}
      for index,key in ipairs(stationKeys) do
          local rect=button(stationLabels[index],118+(index-1)*148,466,132,66,true,1)
          ui[key]=rect
          local selected=(index==1 and runtime.saveData.audio.station=="8bit") or (index==2 and runtime.saveData.audio.station=="chill")
              or (index==3 and runtime.saveData.audio.station=="vibes") or (index==4 and runtime.saveData.audio.rainEnabled)
          if selected then
              love.graphics.setColor(colors.brass); love.graphics.setLineWidth(4)
              love.graphics.rectangle("line",rect.x+3,rect.y+3,rect.w-6,rect.h-6,5,5); love.graphics.setLineWidth(1)
          end
      end
      ui.radioPrevious=button("PREVIOUS",118,560,166,66,true)
      ui.radioPause=button(runtime.saveData.audio.musicPaused and "PLAY" or "PAUSE",304,560,166,66,true)
      ui.radioNext=button("NEXT",490,560,166,66,true)
      ui.radioMute=button(runtime.saveData.audio.musicMuted and "UNMUTE" or "MUTE",676,560,166,66,true)
  end

  local function journeyLogRows()
      local data=runtime.saveData or {}
      local summary=questSummary() or {}
      local rows={}
      local matchedMail={}
      if runtime.scene=="expedition" then
          local expedition=expeditionObjective()
          if expedition then
              rows[#rows+1]={kind="expedition",title=tostring(expedition.title or "EXPEDITION"),
                  destination=math.floor(tonumber(data.location) or 1),objective=tostring(expedition.text or "Explore the current area."),
                  detail=tostring(expedition.status or "CURRENT EXPEDITION"),active=true}
          end
      end
      for _,objective in ipairs(summary.objectives or {}) do
          local destination=math.floor(tonumber(objective.destination) or tonumber(data.location) or 1)
          if objective.kind=="mail" then
              local recipient,origin
              for index,mail in ipairs(data.mailQuests or {}) do
                  if not matchedMail[index] and not mail.complete and math.floor(tonumber(mail.destination) or 50)==destination then
                      matchedMail[index]=true
                      recipient=mail.recipient and Util.titleFromFile(mail.recipient) or nil
                      origin=tonumber(mail.origin)
                      break
                  end
              end
              rows[#rows+1]={kind="mail",title="MAIL DELIVERY",destination=destination,
                  objective=recipient and ("Deliver the letter to "..recipient.." at Stop "..destination..".") or ("Deliver mail to Stop "..destination.."."),
                  detail=origin and ("LETTER  •  FROM STOP "..math.floor(origin)) or "LETTER DELIVERY"}
          elseif objective.kind=="supplies" then
              local label=tostring(objective.label or "SUPPLY DELIVERY")
              local title=label:match("^(.-) to Stop") or "SUPPLY DELIVERY"
              local cargo=label:match("%((.-)%)")
              rows[#rows+1]={kind="supplies",title=title,destination=destination,
                  objective=cargo and ("Deliver "..cargo.." to Stop "..destination..".") or label,
                  detail="SUPPLY DELIVERY"}
          end
      end
      for _,session in ipairs(summary.help and summary.help.sessions or {}) do
          local destination=math.floor(tonumber(session.location) or tonumber(data.location) or 1)
          rows[#rows+1]={kind="help",title=tostring(session.title or "HELP TASK"),destination=destination,
              objective=tostring(session.objective or "Continue the active task."),
              detail=string.upper(tostring(session.state or "active")).."  •  STEP "..tostring(session.stage or 1).." / "..tostring(session.stageCount or 1),
              active=session.id==data.activeHelpQuestId}
      end
      local passengers=data.passengers or {}
      for _,passenger in ipairs(passengers) do
          local name=Util.titleFromFile(passenger.npc or "Passenger")
          local destination=math.floor(tonumber(passenger.destination) or tonumber(data.location) or 1)
          local origin=tonumber(passenger.origin)
          local job=passenger.job and Util.titleFromFile(passenger.job) or nil
          local detail=origin and ("FROM STOP "..math.floor(origin)) or "ONBOARD PASSENGER"
          if job then detail=detail.."  •  "..string.upper(job) end
          rows[#rows+1]={kind="passenger",title="PASSENGER  •  "..string.upper(name),destination=destination,
              objective="Bring "..name.." to Stop "..destination..".",detail=detail}
      end
      local current=tonumber(data.location) or 1
      table.sort(rows,function(a,b)
          if a.active~=b.active then return a.active==true end
          local ad,bd=math.abs(a.destination-current),math.abs(b.destination-current)
          if ad~=bd then return ad<bd end
          if a.destination~=b.destination then return a.destination<b.destination end
          return a.title<b.title
      end)
      return rows
  end

  local function drawJourneyLog()
      if not runtime.journeyLogOpen then
          ui.journeyLogBounds=nil
          ui.journeyLogClose,ui.journeyLogUp,ui.journeyLogDown=nil,nil,nil
          ui.journeyLogMaxScroll=nil
          return
      end
      local rows=journeyLogRows()
      local mobile=mobileEnabled()
      local bounds=mobile and {x=28,y=24,w=904,h=672} or {x=145,y=36,w=670,h=648}
      ui.journeyLogBounds=bounds
      love.graphics.setColor(0.015,0.012,0.018,.78); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("journeyLog",bounds,function()
          local x,y,w,h=bounds.x,bounds.y,bounds.w,bounds.h
          drawMenuFrame(x,y,w,h,2,.99)
          love.graphics.setColor(colors.brass); textIn("JOURNEY LOG",x+28,y+15,w-230,38,mobile and 1.22 or 1.08)
          love.graphics.setColor(colors.cream)
          textIn("STOP "..tostring(runtime.saveData.location or 1).."  •  "..#rows.." ACTIVE OBJECTIVES  •  "..#(runtime.saveData.passengers or {}).." PASSENGERS",
              x+30,y+51,w-60,27,mobile and .82 or .72,"center")
          ui.journeyLogClose=button("CLOSE",x+w-142,y+15,112,mobile and 48 or 38,true,mobile and .92 or .72)

          local expedition=runtime.scene=="expedition" and expeditionObjective() or nil
          local currentObjective=expedition and tostring(expedition.text or "Explore the current area.")
              or (rows[1] and rows[1].objective or "No active objectives right now.")
          love.graphics.setColor(.055,.038,.028,.96); love.graphics.rectangle("fill",x+26,y+88,w-52,65,8,8)
          love.graphics.setColor(colors.brass); textIn("CURRENT OBJECTIVE",x+40,y+94,190,20,.67)
          love.graphics.setColor(colors.cream); textIn(currentObjective,x+40,y+115,w-80,30,mobile and .88 or .75)

          local listX,listY=x+26,y+166
          local listW=w-52
          local cardHeight=104
          local cardGap=9
          local footerY=y+h-58
          local visible=math.max(1,math.floor((footerY-listY+cardGap)/(cardHeight+cardGap)))
          local maxScroll=math.max(0,#rows-visible)
          runtime.journeyLogScroll=math.max(0,math.min(maxScroll,math.floor(tonumber(runtime.journeyLogScroll) or 0)))
          ui.journeyLogPageSize=visible
          ui.journeyLogMaxScroll=maxScroll
          local start=runtime.journeyLogScroll+1
          if #rows==0 then
              love.graphics.setColor(colors.cream); textIn("No active tasks or passengers. New journey objectives will appear here.",listX+18,listY+42,listW-36,70,.90,"center")
          else
              for offset=0,visible-1 do
                  local row=rows[start+offset]
                  if row then
                      local cy=listY+offset*(cardHeight+cardGap)
                      love.graphics.setColor(.08,.055,.038,.96); love.graphics.rectangle("fill",listX,cy,listW,cardHeight,8,8)
                      local accent=colors.brass
                      if row.kind=="mail" then accent=colors.blue
                      elseif row.kind=="supplies" then accent=colors.green
                      elseif row.kind=="passenger" then accent=colors.brass
                      elseif row.kind=="expedition" then accent=colors.blue
                      elseif row.kind=="help" then accent=colors.red end
                      love.graphics.setColor(accent); love.graphics.rectangle("fill",listX+7,cy+9,5,cardHeight-18,3,3)
                      love.graphics.setColor(colors.cream)
                      textIn(row.title,listX+22,cy+8,listW-222,26,mobile and .88 or .72)
                      love.graphics.setColor(accent)
                      textIn("DESTINATION  •  STOP "..row.destination,listX+listW-190,cy+8,176,26,mobile and .76 or .62,"right")
                      love.graphics.setColor(colors.cream)
                      textIn(row.objective,listX+22,cy+39,listW-44,34,mobile and .88 or .72)
                      love.graphics.setColor(.82,.72,.54,1)
                      textIn(row.detail or "ACTIVE OBJECTIVE",listX+22,cy+76,listW-44,19,.62)
                  end
              end
          end
          love.graphics.setColor(colors.cream)
          textIn(#rows>visible and ("OBJECTIVE "..start.."–"..math.min(start+visible-1,#rows).." OF "..#rows) or "ALL ACTIVE OBJECTIVES SHOWN",
              x+30,footerY,w-250,30,.64)
          ui.journeyLogUp=button("UP",x+w-205,footerY-2,76,34,runtime.journeyLogScroll>0,.66)
          ui.journeyLogDown=button("DOWN",x+w-116,footerY-2,86,34,runtime.journeyLogScroll<maxScroll,.62)
          textIn(mobile and "USE CLOSE TO RETURN" or "J CLOSE  •  ESC MENU",x+30,y+h-28,210,18,.54)
      end)
  end

  local function drawGame()
      local quest=runtime.lastStand
      if quest and quest.capture and quest.mode~="offer" then
          UIStyle.scope("lastStand",{x=0,y=0,w=W,h=H},function() LastStand:draw() end)
          if (quest.mode=="backyard" or quest.mode=="interior") and not quest.paused and not quest.treatment then
              ui.drawJourneyHUD()
          end
          return
      end
      local cloudLayer=getCloudLayer()
      local windowWidth,windowHeight=love.graphics.getDimensions()
      local layout=WideLayout.measure(W,H,windowWidth,windowHeight)
      local expeditionScene=runtime.scene=="expedition"
      ui.expeditionHudBounds=nil
      ui.expeditionMapObjectiveBounds=nil
      if expeditionScene then ui.mobileHeaderBounds=nil end
      ui.sideHudLayout=layout.sidePanels and runtime.scene~="train" and not expeditionScene and layout or nil
      ui.returnDoor,ui.returnTrain,ui.returnStop,ui.exitHome=nil,nil,nil,nil
      WorldView.begin()
      if runtime.scene=="train" then
          drawLandscape()
          local trainView=getTrainView()
          love.graphics.push(); TrainView.apply(trainView)
          drawTracks(trainView)
          local tx=0
          local slide=trainView.transitionDistance
          if runtime.travelTransition then
              local t=runtime.travelTransition.t; local timing=EngineUpgrades.timings(runtime.saveData.engineLevel,runtime.travelTransition.maintenanceCondition or Maintenance.condition(runtime.saveData))
              if t<timing.depart then local p=t/timing.depart; tx=-slide*(p*p*p)
              elseif t<timing.arrive then tx=-slide
              else local p=math.min(1,(t-timing.arrive)/timing.arrivalDuration); local eased=1-(1-p)^3; tx=slide*(1-eased) end
          end
          love.graphics.push(); love.graphics.translate(tx,0)
          if runtime.carTransition then
              local p=math.min(1,runtime.carTransition.t/runtime.carTransition.duration); local eased=p*p*(3-2*p); local direction=runtime.carTransition.to>runtime.carTransition.from and -1 or 1
              drawTrainView(runtime.carTransition.from,direction*slide*eased,runtime.carTransition.from,runtime.player.x,runtime.player.y)
              drawTrainView(runtime.carTransition.to,direction*slide*(eased-1),nil)
          else drawTrainView(runtime.saveData.activeCar or 1,0,runtime.saveData.activeCar or 1,runtime.player.x,runtime.player.y) end
          love.graphics.pop()
          love.graphics.pop()
      elseif runtime.scene=="house" then drawHouse()
      elseif runtime.scene=="expedition" then drawExpedition()
      elseif runtime.scene=="caravan" then drawCaravan()
      else drawStop() end
      if runtime.scene=="train" or runtime.scene=="stop" then Clouds.draw(cloudLayer,runtime.scene,W,H,runtime.sceneryOffset,runtime.saveData.location) end
      WorldView.finish()
      if not expeditionScene and not mobileEnabled() then
          if not ui.sideHudLayout then
              UIStyle.scope("resourceHud",{x=20,y=20,w=470,h=34},function()
              ui.drawResource("FOOD",runtime.saveData.resources.food,20,colors.green,110,TrainUpgradeBalance.resourceCapacity(runtime.saveData,"food")); ui.drawResource("WATER",runtime.saveData.resources.water,140,colors.blue,110,TrainUpgradeBalance.resourceCapacity(runtime.saveData,"water"))
              ui.drawResource("COAL",runtime.saveData.resources.coal,260,colors.red,110,TrainUpgradeBalance.resourceCapacity(runtime.saveData,"coal")); ui.drawResource("OIL",runtime.saveData.resources.oil,380,colors.brass,110,Maintenance.oilCapacity(runtime.saveData))
              end)
          end
          ui.drawJourneyHUD()
      elseif not expeditionScene and not WorldPause.isPaused(runtime,ui,maintenanceSession) then ui.drawJourneyHUD() end
      drawExpeditionProgress()
      local travel=travelStatus()
      local cost=travel.cost
      local travelLabel=runtime.saveData.location>=50 and "JOURNEY COMPLETE"
        or ((travel.affordable and "TRAVEL" or "NEED").."  "..cost.food.."F  "..cost.water.."W  "..cost.coal.."C")
      local mobile=mobileEnabled()
      ui.travel,ui.leaveTrain,ui.returnTrain,ui.returnStop,ui.backpack,ui.map,ui.journeyLog,ui.editMode,ui.trainUpgrade,ui.maintenance,ui.pose,ui.pauseMenu,ui.stopAttack,ui.trainCarTabs,ui.exitHome=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
      if expeditionScene and runtime.inventoryOpen then
          -- Inventory panels occupy the normal desktop toolbar. Keep one
          -- close target in the clear strip above the ammo panel and hide
          -- unrelated expedition controls until the player returns to play.
          local closeBounds=mobile and {x=W/2-58,y=0,w=116,h=44} or {x=W-132,y=2,w=116,h=30}
          UIStyle.scope("sceneControls",closeBounds,function()
          ui.backpack=mobile and button("CLOSE PACK",W/2-58,0,116,44,true,.78)
              or button("CLOSE PACK",W-132,2,116,30,true,.64)
          end)
      elseif mobile then
          if ui.mobileMenuOpen then
              love.graphics.setColor(0,0,0,.64); love.graphics.rectangle("fill",0,0,W,H)
              UIStyle.scope("journeyMenu",{x=90,y=62,w=780,h=610},function()
              drawMenuFrame(90,62,780,610,2,.99)
              love.graphics.setColor(colors.cream); textIn("JOURNEY MENU",118,80,724,38,1.35,"center")
              love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",118,126,724,3)
              local canTravel=runtime.scene=="train" and runtime.saveData.location<50 and travel.affordable
              ui.travel=runtime.scene=="train" and button(travelLabel,118,150,724,66,canTravel) or nil
              ui.returnTrain=runtime.scene=="stop" and button("RETURN TO TRAIN",118,150,724,66,true) or nil
              ui.returnStop=runtime.scene=="caravan" and button("RETURN TO STOP",118,150,724,66,true) or nil
              ui.backpack=button("BACKPACK",118,236,348,66,true)
              ui.map=button(runtime.scene=="expedition" and "AREA MAP" or "TRAIL MAP",494,236,348,66,true)
              ui.trainUpgrade=runtime.scene=="train" and button("TRAIN UPGRADES",118,322,348,66,true) or nil
              ui.editMode=runtime.scene=="train" and button("MOVE / SCALE",494,322,348,66,true) or nil
              ui.maintenance=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and not runtime.travelTransition and button("MAINTENANCE  "..math.floor(Maintenance.condition(runtime.saveData)).."%",118,408,348,66,true) or nil
              ui.pose=button("CHARACTER POSES",494,408,348,66,true)
              ui.pauseMenu=button("PAUSE MENU",118,494,348,66,true)
              ui.leaveTrain=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and button("LEAVE TRAIN",494,494,348,66,true) or nil
              ui.stopAttack=runtime.scene=="stop" and button("ATTACK",494,494,348,66,true) or nil
              ui.journeyLog=button("JOURNEY LOG  •  "..#journeyLogRows().." OBJECTIVES  •  "..#(runtime.saveData.passengers or {}).." PASSENGERS",118,580,724,42,true,.82)
              textIn("Tap CLOSE to return",118,624,724,26,.90,"center")
              end)
          end
      elseif ui.sideHudLayout then
          local x,w=ui.sideHudLayout.rightX,ui.sideHudLayout.panelWidth
          UIStyle.scope("sceneControls",{x=x,y=18,w=w,h=620},function()
          local y,gap=18,42
          ui.map=button(runtime.mapOpen and "CLOSE MAP" or (runtime.scene=="expedition" and "AREA MAP" or "MAP"),x,y,w,36,true,.80); y=y+gap
          ui.backpack=button(runtime.inventoryOpen and "CLOSE PACK" or "BACKPACK",x,y,w,36,true,.80); y=y+gap
          ui.pose=button(runtime.poseMenu and "CLOSE POSES" or "POSES",x,y,w,36,true,.80); y=y+gap
          ui.travel=runtime.scene=="train" and button(travelLabel,x,y,w,38,runtime.saveData.location<50 and travel.affordable,.76) or nil; y=y+gap
          ui.trainUpgrade=runtime.scene=="train" and button("UPGRADE",x,y,w,36,true,.80) or nil; y=y+gap
          ui.editMode=runtime.scene=="train" and button(runtime.editMode and "EDITING" or "MOVE / SCALE",x,y,w,36,true,.72) or nil; y=y+gap
          ui.maintenance=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and not runtime.travelTransition and button("MAINTENANCE",x,y,w,36,true,.72) or nil; y=y+gap
          ui.leaveTrain=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and button("LEAVE TRAIN",x,y,w,36,true,.76) or nil
          ui.stopAttack=(runtime.scene=="stop" or runtime.scene=="expedition") and button("ATTACK",W-152,H-124,136,42,true,.85,.52) or nil
          end)
      else
          if expeditionScene then
              UIStyle.scope("sceneControls",{x=W-224,y=18,w=208,h=620},function()
              if not runtime.mapOpen then
                  local gap=8
                  local widths={116,84}
                  local total=widths[1]+widths[2]+gap
                  local x=W-total-16
                  ui.map=button("AREA MAP",x,18,widths[1],36,true,.78); x=x+widths[1]+gap
              end
              ui.journeyLog=button("JOURNAL  [J]",W-224,62,208,36,true,.70)
              ui.stopAttack=not runtime.mapOpen and button("ATTACK",W-152,H-70,136,38,true,.82,.82) or nil
              end)
          else
              UIStyle.scope("sceneControls",{x=510,y=20,w=415,h=668},function()
              ui.travel=runtime.scene=="train" and button(travelLabel,510,20,220,36,runtime.saveData.location<50 and travel.affordable) or nil
              -- Keep the departure control with the other scene controls without
              -- covering the train.
              ui.leaveTrain=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and button("LEAVE TRAIN",790,194,135,32,true) or nil
              ui.backpack=button(runtime.inventoryOpen and "CLOSE" or "PACK",830,20,95,36,true)
              ui.map=button(runtime.mapOpen and "CLOSE MAP" or "MAP",735,20,87,36,true,.72)
              ui.journeyLog=button("JOURNAL  [J]",745,153,180,33,true,.68)
              ui.editMode=runtime.scene=="train" and button(runtime.editMode and "EDITING" or "MOVE / SCALE",745,70,180,36,true) or nil
              ui.trainUpgrade=runtime.scene=="train" and button("UPGRADE  "..runtime.saveData.scrap.." SCRAP",510,70,220,36,true) or nil
              ui.maintenance=runtime.scene=="train" and runtime.saveData.stopped and (runtime.saveData.activeCar or 1)==1 and not runtime.travelTransition and button("MAINTENANCE  "..math.floor(Maintenance.condition(runtime.saveData)).."%",510,112,220,32,true) or nil
              ui.pose=button(runtime.poseMenu and "CLOSE" or "POSES",745,112,85,32,true)
              ui.stopAttack=runtime.scene=="stop" and button("ATTACK",790,650,135,38,true) or nil
              end)
          end
      end
      local returnTrainVisible=runtime.scene=="stop" and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue and not runtime.helpDialogue
          and not runtime.editMode and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.poseMenu
          and not ui.optionsOpen and not ui.radioOpen and not ui.mobileMenuOpen and not runtime.firstAid and not runtime.shootingRange
          and not runtime.exitPrompt and not maintenanceSession.open
      if returnTrainVisible then
          local layout=ui.sideHudLayout
          local bounds=layout and {x=layout.rightX,y=190,w=layout.panelWidth,h=50}
              or (mobile and {x=650,y=214,w=288,h=66} or {x=790,y=194,w=135,h=38})
          UIStyle.scope("returnTrain",bounds,function()
          ui.returnTrain=layout and button("RETURN TO TRAIN",layout.rightX,190,layout.panelWidth,50,true,.76)
              or (mobile and button("RETURN TO TRAIN",650,214,288,66,true) or button("RETURN TO TRAIN",790,194,135,38,true,.68))
          end)
      end
      -- The campsite exit is a safety control, not ordinary world chrome. Keep
      -- it above every modal panel; the mobile journey menu supplies its own
      -- full-width version while that menu is open.
      local returnStopVisible=runtime.scene=="caravan" and not ui.mobileMenuOpen
      local exitHomeVisible=runtime.scene=="house" and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue
          and not runtime.editMode and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.poseMenu
          and not ui.optionsOpen and not ui.radioOpen and not ui.mobileMenuOpen and not runtime.firstAid and not maintenanceSession.open
      if exitHomeVisible then
          local layout=ui.sideHudLayout
          local bounds=layout and {x=layout.rightX,y=190,w=layout.panelWidth,h=50}
              or (mobile and {x=650,y=214,w=288,h=66} or {x=790,y=194,w=135,h=38})
          UIStyle.scope("exitHome",bounds,function()
          ui.exitHome=layout and button("EXIT HOME",layout.rightX,190,layout.panelWidth,50,true,.78)
              or (mobile and button("EXIT HOME",650,214,288,66,true) or button("EXIT HOME",790,194,135,38,true,.78))
          end)
      end
      if ui.sideHudLayout then
          ui.journeyLog=button("JOURNEY LOG  [J]",ui.sideHudLayout.leftX,616,ui.sideHudLayout.panelWidth,30,true,.68)
      end
      ui.exitTrain = nil
      local nearbyFurniture=runtime.nearbyItem and isFurnitureItem(runtime.saveData.droppedItems[runtime.nearbyItem] and runtime.saveData.droppedItems[runtime.nearbyItem].name)
      local contextText,contextScale
      if Accessibility.enabled(runtime.saveData,"controlHints") and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.editMode and not runtime.carTransition and not ui.mobileMenuOpen then
          if mobile then
              if ui.nearRadio then contextText,contextScale="TAP RADIO",.78
              elseif runtime.nearPassenger or runtime.nearNPC then contextText,contextScale="TAP TALK   •   TAP GIVE",.72
              elseif runtime.nearCarNext then contextText,contextScale="TAP DOOR FOR NEXT CAR",.72
              elseif runtime.nearCarPrev then contextText,contextScale="TAP DOOR FOR PREVIOUS CAR",.66
              elseif runtime.nearMailbox then contextText,contextScale="TAP OPEN FOR REWARD MAILBOX",.66
              elseif runtime.nearChest then contextText,contextScale="TAP OPEN   •   HOLD PICK UP",.66
              elseif nearbyFurniture then contextText,contextScale="HOLD PICK UP FOR FURNITURE",.68
              elseif runtime.nearHouse then contextText,contextScale="TAP ENTER",.78
              elseif ui.interaction and ui.interaction.kind=="houseExit" then contextText,contextScale="TAP EXIT",.78
              elseif runtime.nearExpedition then contextText,contextScale="TAP  •  "..(ui.interaction.label or "EXPLORE"),.62
              elseif runtime.nearCaravan then contextText,contextScale="TAP  •  "..(ui.interaction.label or "CARAVAN"),.62
              elseif runtime.nearReturnTrain then contextText,contextScale="TAP BOARD",.78
              elseif runtime.nearFire then contextText,contextScale="TAP COAL",.78 end
          elseif ui.nearRadio then contextText,contextScale="P  OPEN RADIO",.72
          elseif runtime.nearPassenger then contextText,contextScale="E  TALK   •   G  GIVE",.72
          elseif runtime.nearCarNext then contextText,contextScale="E  ENTER NEXT CAR",.72
          elseif runtime.nearCarPrev then contextText,contextScale="E  RETURN TO PREVIOUS CAR",.66
          elseif runtime.nearNPC then contextText,contextScale="E  TALK   •   G  GIVE",.72
          elseif runtime.nearMailbox then contextText,contextScale="E / CLICK OPEN REWARD MAILBOX",.66
          elseif runtime.nearChest then contextText,contextScale="CLICK OPEN   •   HOLD E PICK UP",.66
          elseif nearbyFurniture then contextText,contextScale="HOLD E  PICK UP FURNITURE",.72
          elseif runtime.nearHouse then contextText,contextScale="E  ENTER HOME",.78
          elseif ui.interaction and ui.interaction.kind=="houseExit" then contextText,contextScale="E  LEAVE HOME",.78
          elseif runtime.nearExpedition then contextText,contextScale="E  "..(ui.interaction.label or "EXPLORE"),.68
          elseif runtime.nearCaravan then contextText,contextScale="E  "..(ui.interaction.label or "CARAVAN"),.68
          elseif runtime.nearReturnTrain then contextText,contextScale="E  BOARD TRAIN",.78
          elseif runtime.nearFire then contextText,contextScale="E  ADD COAL",.78 end
      end
      if mobile and runtime.holdPickupIndex then contextText="HOLD TO PICK UP" end
      ui.contextHint=nil
      if contextText then
          local highContrast=Accessibility.enabled(runtime.saveData,"highContrast")
          local hintX,hintY,hintW,hintH=325,300,310,40
          if ui.sideHudLayout then
              if runtime.scene=="expedition" then
                  hintX,hintY,hintW,hintH=ui.sideHudLayout.rightX,190,ui.sideHudLayout.panelWidth,48
              else
                  hintX,hintY,hintW,hintH=ui.sideHudLayout.leftX,492,ui.sideHudLayout.panelWidth,48
              end
          end
          if runtime.scene=="expedition" and not ui.sideHudLayout then
              hintX,hintY,hintW,hintH=(W-430)/2,H-50,430,34
          elseif mobile then
              if not ui.sideHudLayout then hintX,hintY,hintW,hintH=(W-440)/2,H-44,440,32 end
          end
          if runtime.scene=="train" and not mobile and not ui.sideHudLayout then
              local trainView=getTrainView()
              hintX,hintY=trainView.visibleLeft+20,214
              if #(runtime.saveData.trainCars or {})>1 then hintY=284 end
              local right=trainView.couplerX-24
              hintW=math.min(410,right-hintX)
              hintH=48
          end
          local hintAlpha=highContrast and .96 or (mobile and .42 or .50)
          ui.contextHint={x=hintX,y=hintY,w=hintW,h=hintH,alpha=hintAlpha,text=contextText}
          love.graphics.setColor(highContrast and {0,0,0,hintAlpha} or {colors.panel[1],colors.panel[2],colors.panel[3],hintAlpha}); love.graphics.rectangle("fill",hintX,hintY,hintW,hintH,6,6)
          if highContrast then love.graphics.setColor(1,.84,.28,1); love.graphics.setLineWidth(3); love.graphics.rectangle("line",hintX,hintY,hintW,hintH,6,6); love.graphics.setLineWidth(1) end
          love.graphics.setColor(colors.cream)
          if mobile then
              Typography.drawText(love.graphics,contextText,hintX+12,hintY+3,hintW-24,hintH-8,
                  {scale=.78*Accessibility.textScale(runtime.saveData),minScale=.65,singleLine=true,align="center",valign="center"})
          else textIn(contextText,hintX+14,hintY+5,hintW-28,hintH-12,contextScale,"center") end
          if runtime.holdPickupIndex then love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",hintX+22,hintY+hintH-7,(hintW-44)*math.min(1,runtime.holdPickupTime/HOLD_PICKUP_SECONDS),5,2,2) end
      end
      if runtime.scene=="train" and #(runtime.saveData.trainCars or {})>1 and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.dialogue and not runtime.editMode and not ui.mobileMenuOpen then
          local active=runtime.saveData.activeCar or 1
          ui.trainCarTabs=Train.consistLayout(W,#runtime.saveData.trainCars,{mobile=mobile})
          for index,tab in ipairs(ui.trainCarTabs) do
              if ui.sideHudLayout then
                  tab.x,tab.y,tab.w,tab.h=ui.sideHudLayout.rightX,414+(index-1)*38,ui.sideHudLayout.panelWidth,32
              elseif mobile then tab.y=214 end
              local selected=index==active
              love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",tab.x,tab.y,tab.w,tab.h,7,7)
              love.graphics.setColor(selected and colors.brass or colors.cream); love.graphics.setLineWidth(selected and 3 or 1)
              love.graphics.rectangle("line",tab.x,tab.y,tab.w,tab.h,7,7)
              textIn(ui.sideHudLayout and ("CAR "..index) or tostring(index),tab.x,tab.y,tab.w,tab.h,mobile and 1.10 or .55,"center")
          end
          love.graphics.setLineWidth(1); love.graphics.setColor(colors.cream)
          if ui.sideHudLayout then
              textIn("CAR "..active.." / "..#runtime.saveData.trainCars,ui.sideHudLayout.rightX,385,ui.sideHudLayout.panelWidth,24,.70,"center")
          elseif mobile then
              drawMenuFrame(350,280,585,32,4,.94)
              textIn("CAR "..active.." / "..#runtime.saveData.trainCars.."  •  "..Util.titleFromFile(runtime.saveData.trainCars[active]),360,282,565,28,.9,"center")
          else textIn("CAR "..active.." / "..#runtime.saveData.trainCars.."  •  "..Util.titleFromFile(runtime.saveData.trainCars[active]),10,246,400,26,.72,"center") end
      end
      ui.pickup = not mobile and runtime.nearbyItem and not nearbyFurniture and not runtime.editMode and not ui.mobileMenuOpen and button("PICK UP  [E]",390,650,180,38,true) or nil
      if runtime.inventoryOpen then if runtime.chestOpen then ui.drawChestInventory() end; ui.drawInventory() end
      if runtime.inventoryOpen and runtime.inventoryDragActive and runtime.draggedSlot and containerValue(runtime.draggedSlot) then local mx,my=screenToGame(pointerPosition()); ui.drawItem(containerValue(runtime.draggedSlot),{x=mx-32,y=my-32,w=64,h=64}) end
      ui.expeditionMapClose=nil
      if runtime.mapOpen then
          if runtime.scene=="expedition" then
              ui.mapUp,ui.mapDown=nil,nil
              drawExpeditionLocalMap()
              ui.expeditionMapClose=mobile and button("CLOSE MAP",W-252,28,220,62,true) or button("CLOSE MAP",W-194,28,150,44,true,.82)
          else ui.drawMap() end
      end
      if runtime.editMode then ui.drawEditControls() end
      ui.poseIdle=nil; ui.poseSit=nil; ui.poseLay=nil; ui.poseAction=nil; ui.poseClose=nil
      ui.musicDown=nil; ui.musicUp=nil; ui.sfxDown=nil; ui.sfxUp=nil; ui.rainDown=nil; ui.rainUp=nil; ui.musicPrevious=nil; ui.musicPause=nil; ui.musicNext=nil; ui.musicMute=nil
      ui.optionsAudioTab=nil; ui.optionsAccessTab=nil; ui.accessTextSize=nil; ui.accessHighContrast=nil; ui.accessReducedMotion=nil
      ui.accessControlHints=nil; ui.accessTouchFeedback=nil; ui.accessLargeTouchTargets=nil
      ui.radioPrevious=nil; ui.radioPause=nil; ui.radioNext=nil; ui.radioMute=nil
      if runtime.poseMenu then
          ui.poseClose=nil
          local poseBounds=mobile and {x=200,y=150,w=560,h=390} or {x=735,y=198,w=190,h=150}
          UIStyle.scope("poseMenu",poseBounds,function()
          if mobile then
              drawMenuFrame(200,150,560,390,2,.99); love.graphics.setColor(colors.cream); textIn("CHARACTER POSE",228,174,504,42,1.25,"center")
              ui.poseIdle=button("STAND",228,240,236,70,true); ui.poseSit=button("SIT",496,240,236,70,true)
              ui.poseLay=button("LAY DOWN",228,335,236,70,true); ui.poseAction=button("USE / ACTION",496,335,236,70,true)
              ui.poseClose=button("DONE",496,450,236,48,true)
          else love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",735,198,190,150,8,8); ui.poseIdle=button("STAND",750,212,75,34,true); ui.poseSit=button("SIT",835,212,75,34,true); ui.poseLay=button("LAY",750,256,75,34,true); ui.poseAction=button("USE",835,256,75,34,true); ui.poseClose=button("DONE",792,300,118,34,true,.72) end
          end)
      end
      if ui.radioOpen then
          love.graphics.setColor(0,0,0,.68); love.graphics.rectangle("fill",0,0,W,H)
          UIStyle.scope("radio",{x=90,y=62,w=780,h=610},function()
          if mobile then drawMobileRadio() else
          if ui.radioFace then love.graphics.setColor(1,1,1); love.graphics.draw(ui.radioFace,130,95,0,700/ui.radioFace:getWidth(),450/ui.radioFace:getHeight()) else drawMenuFrame(130,95,700,450,2,1) end
          ui.radio8bit={x=248,y=468,w=82,h=54}; ui.radioChill={x=343,y=468,w=82,h=54}; ui.radioVibes={x=438,y=468,w=82,h=54}
          ui.radioRain={x=533,y=468,w=82,h=54}; ui.radioClose={x=628,y=468,w=82,h=54}
          local radioButtons={ui.radio8bit,ui.radioChill,ui.radioVibes,ui.radioRain,ui.radioClose}
          local radioLabels={"8-BIT","CHILL","VIBES","RAIN","CLOSE"}
          for i,r in ipairs(radioButtons) do
              if ui.radioButtonsImage and ui.radioButtonQuads then love.graphics.setColor(1,1,1); local iw,ih=ui.radioButtonsImage:getDimensions(); local q=((i-1)%3)+1; love.graphics.draw(ui.radioButtonsImage,ui.radioButtonQuads[q],r.x,r.y,0,r.w/(iw/3),r.h/ih) else button("",r.x,r.y,r.w,r.h,true) end
              local selected=(i==1 and runtime.saveData.audio.station=="8bit") or (i==2 and runtime.saveData.audio.station=="chill") or (i==3 and runtime.saveData.audio.station=="vibes") or (i==4 and runtime.saveData.audio.rainEnabled)
              love.graphics.setColor(selected and colors.brass or colors.cream); love.graphics.setLineWidth(selected and 4 or 2); love.graphics.rectangle("line",r.x,r.y,r.w,r.h,5,5)
              textIn(radioLabels[i],r.x+2,r.y+18,r.w-4,30,.58,"center")
          end
          love.graphics.setLineWidth(1)
          local audioStatus=getAudioStatus()
          local track=audioStatus.nowPlaying and Util.titleFromFile(audioStatus.nowPlaying:match("[^/]+$") or audioStatus.nowPlaying) or "Starting music..."
          love.graphics.setColor(colors.cream); textIn("NOW PLAYING:  "..track,220,385,520,24,.72,"center")
          textIn(AudioCatalog.stationLabel(runtime.saveData.audio.station).."   •   "..(runtime.saveData.audio.rainEnabled and "RAIN ON" or "RAIN OFF"),260,420,440,24,.82,"center")
          drawMenuFrame(230,552,500,62,4,.94)
          ui.radioPrevious=button("|<  PREV",242,560,110,46,true,.72)
          ui.radioPause=button(runtime.saveData.audio.musicPaused and "PLAY" or "PAUSE",364,560,110,46,true,.72)
          ui.radioNext=button("NEXT  >|",486,560,110,46,true,.72)
          ui.radioMute=button(runtime.saveData.audio.musicMuted and "UNMUTE" or "MUTE",608,560,110,46,true,.72)
          local mx,my=screenToGame(pointerPosition()); mx,my=UIStyle.inversePoint(mx,my,"radio",{x=90,y=62,w=780,h=610}); local tip
          if Util.pointIn(mx,my,ui.radio8bit) then tip="Scene-based 8-bit score"
          elseif Util.pointIn(mx,my,ui.radioChill) then tip="Chill Radio"
          elseif Util.pointIn(mx,my,ui.radioVibes) then tip="Vibes Radio"
          elseif Util.pointIn(mx,my,ui.radioRain) then tip=runtime.saveData.audio.rainEnabled and "Turn rain ambience off" or "Turn rain ambience on"
          elseif Util.pointIn(mx,my,ui.radioClose) then tip="Close radio" end
          if tip then love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.86); love.graphics.rectangle("fill",mx-85,my-42,170,30,5,5); love.graphics.setColor(colors.cream); textIn(tip,mx-80,my-34,160,20,.72,"center") end
          end
          end)
      end
      local inventoryResult=runtime.dialogue and runtime.dialogue.inventoryResult
      if not (expeditionScene and runtime.inventoryOpen and not inventoryResult) then ui.drawDialogue() end
      if runtime.trainUpgradeOpen then ui.drawTrainUpgrades() end
      if runtime.tradeOpen then drawTrade() end
      if maintenanceSession.open then
          maintenanceSession.mouseX,maintenanceSession.mouseY=screenToGame(pointerPosition())
          maintenanceSession.mouseX,maintenanceSession.mouseY=UIStyle.inversePoint(maintenanceSession.mouseX,maintenanceSession.mouseY,"maintenance",{x=0,y=0,w=W,h=H})
          UIStyle.scope("maintenance",{x=0,y=0,w=W,h=H},function()
              Maintenance.draw(maintenanceSession,runtime.saveData)
          end)
      end
      if runtime.firstAid then
          local firstAidAssets=scenery.firstAidAssets or {}
          local assets={
              npc=npcImages[runtime.firstAid.npc],medical=ui.propImages[runtime.firstAid.itemName],
              wound=firstAidAssets.wound,disinfectant=firstAidAssets.disinfectant,
              rag=firstAidAssets.rag,swab=firstAidAssets.swab,gauze=firstAidAssets.gauze,
              bandage=firstAidAssets.bandage,bandageStrips=firstAidAssets.bandageStrips,
              drawFrame=ui.menuFrames and next(ui.menuFrames) and drawMenuFrame or nil,
          }
          love.graphics.setColor(0,0,0,.78); love.graphics.rectangle("fill",0,0,W,H)
          UIStyle.scope("firstAid",{x=105,y=40,w=750,h=635},function()
              FirstAid.draw(runtime.firstAid,colors,assets,true)
          end)
      end
      if runtime.shootingRange then
          UIStyle.scope("shootingRange",{x=0,y=0,w=W,h=H},function()
              ShootingRange.draw(runtime.shootingRange,runtime.saveData,scenery.shootingRangeAssets or {},ui,Catalog,mobile)
          end)
      end
      -- Keep the campsite exit above its greeting and trading overlays so leaving
      -- never requires closing another panel first.
      if returnStopVisible then
          local bounds=mobile and {x=700,y=642,w=238,h=66} or {x=780,y=670,w=145,h=34}
          UIStyle.scope("returnStop",bounds,function()
          ui.returnStop=mobile and button("RETURN TO STOP",700,642,238,66,true,.82) or button("RETURN TO STOP",780,670,145,34,true,.68)
          end)
      end
      if runtime.lastStand then UIStyle.scope("lastStand",{x=0,y=0,w=W,h=H},function() LastStand:draw() end) end
      drawJourneyLog()
  end

  return {draw=drawGame,drawOptions=drawOptions}
end

return {new=new}
