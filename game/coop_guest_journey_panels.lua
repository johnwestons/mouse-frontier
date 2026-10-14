-- Read-only guest map/journal: no campaign writer, mutating world getter,
-- input callback or network command.
-- Rendering below is extracted from screen_ui.drawMap and gameplay_hud's
-- drawJourneyLog; models use only checked public facts and private scroll.
-- draw* runs inside the caller's 960x720 viewport. Context supplies private
-- controls, colors, mobileEnabled(), textBox(), button(), optional scenery;
-- journal also requires drawMenuFrame(). Returned rectangles retain Source
-- map/journeyLog UIStyle scopes; invert those scopes before hit testing.
local Style=require('game.ui_layout')
local Util=require('game.util')
local Quest=require('game.quest_progression')
local Areas=require('game.expedition_areas')
local Panels={}
local biomes={'Desert','Wetland','Canyon','Ruins','Badlands','Forest','Old City','River','Deep Woods','Pale City','Autumn Wood','Wastes'}
local helpStates={accepted=true,investigating=true,active=true}
local function whole(value,fallback,low,high)
    if type(value)~='number' or value~=value or value==math.huge or value==-math.huge then value=fallback end
    return math.max(low,math.min(high,math.floor(value)))
end
local function summary(data)
    -- Quest.summary is read-only. HelpQuest.summary repairs saved records and
    -- is intentionally not called by a detached presentation.
    local result=Quest.summary(data);local sessions={}
    for _,session in pairs(data.helpQuestSessions or {}) do
        if type(session)=='table' and helpStates[session.state] and type(session.id)=='string'
            and type(session.title)=='string' and type(session.objective)=='string' then
            sessions[#sessions+1]=session
        end
    end
    table.sort(sessions,function(a,b)
        if (a.id==data.activeHelpQuestId)~=(b.id==data.activeHelpQuestId) then return a.id==data.activeHelpQuestId end
        if a.location==b.location then return a.id<b.id end
        return (a.location or data.location or 1)<(b.location or data.location or 1)
    end)
    local first=sessions[1]
    result.count=result.count+#sessions
    if first then result.first=first.title..': '..first.objective end
    result.help={sessions=sessions}
    return result
end
function Panels.trail(data,scroll)
    data=data or {};local location=whole(data.location,1,1,50)
    local visited=data.visitedStops or {};local stops={};local highest=1
    for stop=1,50 do
        if visited[stop]==true or visited[tostring(stop)]==true then stops[#stops+1]=stop;highest=math.max(highest,stop) end
    end
    local maxScroll=math.max(0,math.floor((highest-1)/6)-2)
    scroll=whole(scroll,math.max(0,math.floor((location-1)/6)-2),0,maxScroll)
    local points,segments,current={},{},nil
    local previous
    for _,stop in ipairs(stops) do
        local col=(stop-1)%6;local row=math.floor((stop-1)/6)
        local px=145+col*132;if row%2==1 then px=805-col*132 end
        local point={px,215+(row-scroll)*155+math.sin(stop*1.73)*42,
            stop=stop,current=stop==location,biome=biomes[((stop-1)%#biomes)+1]}
        points[#points+1]=point
        if previous and previous.stop+1==stop then segments[#segments+1]={a=previous,b=point,stop=stop} end
        if point.current then current=point end
        previous=point
    end
    local enc=current and data.encounters and data.encounters[tostring(location)]
    local status=not enc and 'Unexplored stop' or (enc.hasMob and not enc.resolved and 'Danger nearby' or (enc.hasMob and 'Mob cleared' or 'Peaceful stop'))
    local quests=summary(data)
    return {location=location,scroll=scroll,maxScroll=maxScroll,points=points,segments=segments,current=current,
        biome=current and biomes[((location-1)%#biomes)+1] or 'Unexplored stop',status=status,
        questLine=quests.count>0 and ('ACTIVE: '..quests.first..(quests.count>1 and ('  +'..(quests.count-1)..' more') or ''))
            or 'No active deliveries or passengers.'}
end
function Panels.journal(data,scene,objective,scroll)
    data=data or {};local location=whole(data.location,1,1,50);local quests=summary(data)
    local rows,matchedMail={},{}
    if scene=='expedition' and type(objective)=='table' then
        rows[#rows+1]={kind='expedition',title=tostring(objective.title or 'EXPEDITION'),destination=location,
            objective=tostring(objective.text or 'Explore the current area.'),detail=tostring(objective.status or 'CURRENT EXPEDITION'),active=true}
    end
    for _,entry in ipairs(quests.objectives or {}) do
        local destination=whole(entry.destination,location,1,50)
        if entry.kind=='mail' then
            local recipient,origin
            for index,mail in ipairs(data.mailQuests or {}) do
                if not matchedMail[index] and not mail.complete and whole(mail.destination,50,1,50)==destination then
                    matchedMail[index]=true;recipient=mail.recipient and Util.titleFromFile(mail.recipient);origin=tonumber(mail.origin);break
                end
            end
            rows[#rows+1]={kind='mail',title='MAIL DELIVERY',destination=destination,
                objective=recipient and ('Deliver the letter to '..recipient..' at Stop '..destination..'.') or ('Deliver mail to Stop '..destination..'.'),
                detail=origin and ('LETTER  •  FROM STOP '..math.floor(origin)) or 'LETTER DELIVERY'}
        elseif entry.kind=='supplies' then
            local label=tostring(entry.label or 'SUPPLY DELIVERY');local title=label:match('^(.-) to Stop') or 'SUPPLY DELIVERY'
            local cargo=label:match('%((.-)%)')
            rows[#rows+1]={kind='supplies',title=title,destination=destination,
                objective=cargo and ('Deliver '..cargo..' to Stop '..destination..'.') or label,detail='SUPPLY DELIVERY'}
        end
    end
    for _,session in ipairs(quests.help.sessions) do
        rows[#rows+1]={kind='help',title=session.title,destination=whole(session.location,location,1,50),objective=session.objective,
            detail=string.upper(session.state)..'  •  STEP '..tostring(session.stage or 1)..' / '..tostring(session.stageCount or 1),
            active=session.id==data.activeHelpQuestId}
    end
    for _,passenger in ipairs(data.passengers or {}) do
        local name=Util.titleFromFile(passenger.npc or 'Passenger');local destination=whole(passenger.destination,location,1,50)
        local origin=tonumber(passenger.origin);local job=passenger.job and Util.titleFromFile(passenger.job)
        local detail=origin and ('FROM STOP '..math.floor(origin)) or 'ONBOARD PASSENGER'
        if job then detail=detail..'  •  '..string.upper(job) end
        rows[#rows+1]={kind='passenger',title='PASSENGER  •  '..string.upper(name),destination=destination,
            objective='Bring '..name..' to Stop '..destination..'.',detail=detail}
    end
    -- Source assigns explicit false to inactive help rows and nil to ordinary
    -- tasks. Normalize private row flags so the sort stays transitive.
    for _,row in ipairs(rows)do row.active=row.active==true end
    table.sort(rows,function(a,b)
        if a.active~=b.active then return a.active==true end
        local ad,bd=math.abs(a.destination-location),math.abs(b.destination-location)
        if ad~=bd then return ad<bd end
        if a.destination~=b.destination then return a.destination<b.destination end
        return a.title<b.title
    end)
    return {location=location,rows=rows,passengers=#(data.passengers or {}),scroll=whole(scroll,0,0,1000000),
        currentObjective=scene=='expedition' and objective and tostring(objective.text or 'Explore the current area.')
            or rows[1] and rows[1].objective or 'No active objectives right now.'}
end

function Panels.expeditionObjective(data)
    if not data or data.scene~='expedition' then return nil end
    local area=Areas.current(data)
    local state=area and data.expeditions and data.expeditions[area.id]
    if not state then return nil end
    local gates=state.gates or {};local defeated=0
    for _,mob in pairs(state.mobs or {})do if mob.dead then defeated=defeated+1 end end
    local objectives=area.objectives or {}
    local text=state.completed and objectives.complete
        or area.kind=='surface' and objectives.surface
        or area.progressType=='survey' and objectives.explore
        or gates.bossDefeated and objectives.complete
        or gates.bossGateOpen and objectives.bossReady
        or objectives.gateClosed
        or 'Explore the area and follow the route.'
    local status='CLEARED '..defeated..'/'..#area.mobs
    if area.progressType=='survey' then
        local marked=0
        for _,id in ipairs(area.completionRequiredMarkers or {})do
            if state.markers and state.markers[id] then marked=marked+1 end
        end
        status='CAIRNS '..marked..'/'..#(area.completionRequiredMarkers or {})
    end
    return {title=area.name,text=text,status=status}
end

function Panels.drawTrail(context,model)
    local W,H=960,720;local ui=assert(context.controls);local colors=assert(context.colors)
    local scenery=context.scenery or {};local textBox=assert(context.textBox);local button=assert(context.button)
    local mobileEnabled=assert(context.mobileEnabled)
      love.graphics.setColor(0.05,0.035,0.02,0.78); love.graphics.rectangle("fill",0,0,W,H)
      return Style.scope("map",{x=70,y=75,w=820,h=570},function()
      love.graphics.setColor(0.76,0.59,0.34); love.graphics.rectangle("fill",70,75,820,570,18,18)
      love.graphics.setColor(0.66,0.47,0.27)
      for y=95,625,20 do for x=90+(y%37),870,43 do love.graphics.rectangle("fill",x,y,3,2) end end
      love.graphics.setColor(0.49,0.31,0.18); love.graphics.setLineWidth(8); love.graphics.rectangle("line",70,75,820,570,18,18)
      love.graphics.setColor(0.22,0.13,0.065); textBox("THE MOUSE FRONTIER TRAIL",100,90,640,50,1.25,"center")
      -- A guest overlay does not draw the ordinary Source HUD. Keep Source's
      -- existing map dismiss control on both desktop and touch presentations.
      ui.map=button("CLOSE MAP",746,82,128,mobileEnabled() and 50 or 38,true,.72)
      local points=model.points;local maxScroll=model.maxScroll
      -- Revealed terrain sketches around every visited stop.
      for i,p in ipairs(points) do if p[2]>175 and p[2]<535 then
          local kind=((p.stop-1)%4)+1; love.graphics.setColor(0.42,0.34,0.20,0.9)
          if kind==1 then for k=-2,2 do love.graphics.polygon("fill",p[1]+k*15,p[2]-35,p[1]+k*15-8,p[2]-20,p[1]+k*15+8,p[2]-20) end
          elseif kind==2 then love.graphics.setLineWidth(4); love.graphics.arc("line","open",p[1],p[2]-22,35,0.1,3.0)
          elseif kind==3 then for k=-2,2 do love.graphics.line(p[1]+k*13,p[2]-42,p[1]+k*13,p[2]-24); love.graphics.circle("fill",p[1]+k*13,p[2]-45,6) end
          else love.graphics.rectangle("line",p[1]-28,p[2]-53,55,27); love.graphics.polygon("fill",p[1]-32,p[2]-53,p[1],p[2]-72,p[1]+32,p[2]-53) end
      end end
      local current=model.current
      if current and current[2]>175 and current[2]<535 and scenery.redTrain then
          local s=72/scenery.redTrain:getWidth(); love.graphics.setColor(1,1,1)
          love.graphics.draw(scenery.redTrain,current[1]+36,current[2]-64,0,-s,s)
      end
      -- Dotted, winding path instead of straight route segments.
      love.graphics.setColor(0.61,0.16,0.12)
      for _,segment in ipairs(model.segments) do local a,b=segment.a,segment.b;local i=segment.stop
          if (a[2]>160 and a[2]<550) or (b[2]>160 and b[2]<550) then for step=0,12 do if step%2==0 then
              local t=step/12;local bend=math.sin(t*math.pi)*((i%2==0) and 22 or -22)
              love.graphics.circle('fill',a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t+bend,4)
          end end end
      end
      for i,p in ipairs(points) do if p[2]>175 and p[2]<535 then
          love.graphics.setColor(p.current and colors.red or colors.cream); love.graphics.circle("fill",p[1],p[2],p.current and 13 or 9)
          love.graphics.setColor(colors.ink); textBox(tostring(p.stop),p[1]-14,p[2]-7,28,14,.72,"center")
          love.graphics.setColor(0.22,0.13,0.065); textBox(p.biome,p[1]-58,p[2]+16,116,37,.84,"center")
      end end
      love.graphics.setColor(0.39,0.25,0.14,0.92); love.graphics.rectangle("fill",105,548,750,78,8,8)
      love.graphics.setColor(colors.cream); textBox("STOP "..model.location.." / "..model.biome.." / "..model.status,120,552,720,29,.88,"center")
      textBox(model.questLine,120,582,720,38,.8,"center")
      local mobile=mobileEnabled()
      ui.mapUp=button("^",mobile and 790 or 805,mobile and 148 or 132,mobile and 68 or 42,mobile and 64 or 36,model.scroll>0)
      ui.mapDown=button("v",mobile and 790 or 805,mobile and 224 or 182,mobile and 68 or 42,mobile and 64 or 36,model.scroll<maxScroll)
      love.graphics.setColor(colors.ink); textBox((model.scroll+1).."/"..(maxScroll+1),790,mobile and 300 or 232,68,30,.85,"center")
      love.graphics.setLineWidth(1)
      end)
end

function Panels.drawJournal(context,model)
    local W,H=960,720;local ui=assert(context.controls);local colors=assert(context.colors)
    local textIn=assert(context.textBox);local button=assert(context.button);local drawMenuFrame=assert(context.drawMenuFrame)
    local mobileEnabled=assert(context.mobileEnabled);local scroll
      local rows=model.rows
      local mobile=mobileEnabled()
      local bounds=mobile and {x=28,y=24,w=904,h=672} or {x=145,y=36,w=670,h=648}
      ui.journeyLogBounds=bounds
      love.graphics.setColor(0.015,0.012,0.018,.78); love.graphics.rectangle("fill",0,0,W,H)
      return Style.scope("journeyLog",bounds,function()
          local x,y,w,h=bounds.x,bounds.y,bounds.w,bounds.h
          drawMenuFrame(x,y,w,h,2,.99)
          love.graphics.setColor(colors.brass); textIn("JOURNEY LOG",x+28,y+15,w-230,38,mobile and 1.22 or 1.08)
          love.graphics.setColor(colors.cream)
          textIn("STOP "..tostring(model.location).."  •  "..#rows.." ACTIVE OBJECTIVES  •  "..model.passengers.." PASSENGERS",
              x+30,y+51,w-60,27,mobile and .82 or .72,"center")
          ui.journeyLogClose=button("CLOSE",x+w-142,y+15,112,mobile and 48 or 38,true,mobile and .92 or .72)

          local currentObjective=model.currentObjective
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
          scroll=math.max(0,math.min(maxScroll,model.scroll))
          ui.journeyLogScroll=scroll
          ui.journeyLogPageSize=visible
          ui.journeyLogMaxScroll=maxScroll
          local start=scroll+1
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
          ui.journeyLogUp=button("UP",x+w-205,footerY-2,76,34,scroll>0,.66)
          ui.journeyLogDown=button("DOWN",x+w-116,footerY-2,86,34,scroll<maxScroll,.62)
          textIn("USE CLOSE TO RETURN",x+30,y+h-28,210,18,.54)
      end)
end
return Panels
