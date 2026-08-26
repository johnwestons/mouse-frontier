local FirstAid={}

FirstAid.zones={
    {x=380,y=300,label="CLEAN"},
    {x=585,y=350,label="PRESS"},
    {x=475,y=480,label="WRAP"},
}
FirstAid.sequences={{1,2,3},{2,3,1},{3,1,2},{1,3,2},{2,1,3},{3,2,1}}

function FirstAid.new(options)
    options=options or {}; local location=math.max(1,math.floor(tonumber(options.location) or 1))
    return {npc=options.npc,itemName=options.itemName,itemSlot=options.itemSlot,location=location,
        sequence=FirstAid.sequences[((location-1)%#FirstAid.sequences)+1],stage=1,misses=0,maximumMisses=3}
end

function FirstAid.choose(session,index)
    if not session then return nil end
    if index==session.sequence[session.stage] then
        session.stage=session.stage+1
        if session.stage>#session.sequence then return "complete" end
        return "progress"
    end
    session.misses=session.misses+1
    if session.misses>=session.maximumMisses then return "failed" end
    return "miss"
end

function FirstAid.mousepressed(session,x,y)
    if x>=350 and x<=610 and y>=590 and y<=640 then return "cancelled" end
    for index,zone in ipairs(FirstAid.zones) do
        local dx,dy=x-zone.x,y-zone.y
        if dx*dx+dy*dy<=46*46 then return FirstAid.choose(session,index) end
    end
    session.misses=session.misses+1
    return session.misses>=session.maximumMisses and "failed" or "miss"
end

function FirstAid.keypressed(session,key)
    if key=="escape" or key=="q" then return "cancelled" end
    local index=tonumber(key)
    if index and index>=1 and index<=3 then return FirstAid.choose(session,index) end
end

function FirstAid.draw(session,colors)
    if not session then return end
    love.graphics.setColor(0,0,0,.76); love.graphics.rectangle("fill",0,0,960,720)
    love.graphics.setColor(colors.panel); love.graphics.rectangle("fill",155,70,650,585,18,18)
    love.graphics.setColor(colors.brass); love.graphics.printf("FIRST AID",155,105,650,"center",0,1.55,1.55)
    love.graphics.setColor(colors.cream); love.graphics.printf("Treat the wound in order. Tap the glowing treatment marker.",230,155,500,"center",0,.82,.82)
    love.graphics.printf("MEDICAL SUPPLY: "..tostring(session.itemName or "none"):gsub("%-"," "):upper(),230,188,500,"center",0,.68,.68)
    love.graphics.setColor(.24,.18,.14); love.graphics.ellipse("fill",480,390,115,175)
    love.graphics.setColor(.34,.25,.19); love.graphics.circle("fill",480,235,68)
    local active=session.sequence[session.stage]
    for index,zone in ipairs(FirstAid.zones) do
        local isActive=index==active
        love.graphics.setColor(isActive and colors.brass or {.28,.22,.18})
        love.graphics.circle("fill",zone.x,zone.y,isActive and 46 or 38)
        love.graphics.setColor(colors.cream); love.graphics.printf(index.."\n"..zone.label,zone.x-42,zone.y-17,84,"center",0,.62,.62)
    end
    love.graphics.setColor(colors.cream); love.graphics.printf("STEP "..session.stage.." / 3   •   MISSES "..session.misses.." / "..session.maximumMisses,250,545,460,"center",0,.82,.82)
    love.graphics.setColor(colors.brass); love.graphics.rectangle("fill",350,590,260,50,7,7)
    love.graphics.setColor(colors.cream); love.graphics.printf("CANCEL",350,606,260,"center",0,.82,.82)
end

function FirstAid.audit()
    local complete=FirstAid.new({location=2,itemName="field-bandage-roll",itemSlot=1})
    local results={}
    for _,index in ipairs(complete.sequence) do results[#results+1]=FirstAid.choose(complete,index) end
    local failed=FirstAid.new({location=1}); local wrong=failed.sequence[1]%3+1
    local failure
    for _=1,failed.maximumMisses do failure=FirstAid.choose(failed,wrong) end
    return {ready=results[1]=="progress" and results[2]=="progress" and results[3]=="complete" and failure=="failed",
        stages=#complete.sequence,maximumMisses=failed.maximumMisses,keyboard=true,touch=true}
end

return FirstAid
