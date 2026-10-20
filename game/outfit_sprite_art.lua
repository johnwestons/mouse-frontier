-- Authored PNG sprites: selecting, positioning and scaling existing artwork.
local Definitions=require("game.outfit_catalog")
local Art={}
local root="assets/sprites/outfit-crafting/"
local sheets={
    controls={file="bench-controls-v1.png",columns=4,rows=5,tight=true},
    supplies={file="supplies-tools-v1.png",columns=4,rows=5,tight=true},
    upgrades={file="upgrades-v1.png",columns=3,rows=3,tight=true},
    soft={file="soft-workpieces-v2.png",columns=4,rows=3,tight=true},
    hard={file="hard-workpieces-v3.png",columns=4,rows=3,tight=true},
    metalFile={file="metal-file-v1.png",columns=1,rows=1,tight=true},
    metalPunch={file="metal-punch-mallet-v1.png",columns=1,rows=1,tight=true},
}
local sprites={}
local function register(sheet,ids)
    for index,id in ipairs(ids) do sprites[id]={sheet=sheet,index=index} end
end
register("controls",{"paper","card","card-selected","button","button-selected","button-disabled",
    "marker-idle","marker-next","marker-done","marker-pointer","chalk-dash","stitch",
    "meter-track","meter-fill","quality-usable","quality-fine","quality-masterwork","icon-left","icon-right","icon-close"})
register("supplies",{"thread-spool","fabric-scraps","canvas-bundle","wool-batting",
    "leather-pieces","metal-sheet","waxed-thread","chalk","scissors","pins","needle","awl",
    "hand-snips","file","punch-and-mallet","clips","two-needles","sewing-kit","pocket-tool-roll","thread-loop"})
sprites.file={sheet="metalFile",index=1}
sprites["punch-and-mallet"]={sheet="metalPunch",index=1}
for index,recipe in ipairs(Definitions.recipes) do sprites[recipe.id]={sheet="upgrades",index=index} end
for _,entry in ipairs({{"fabric","soft",1},{"canvas","soft",2},{"wool","soft",3},
    {"leather","hard",1},{"metal","hard",2},{"gusset","hard",3}}) do
    for phase=1,4 do sprites["work-"..entry[1].."-"..phase]={sheet=entry[2],index=(entry[3]-1)*4+phase} end
end

local function loadSheet(name)
    local sheet=assert(sheets[name],"Unknown outfit sprite sheet: "..tostring(name))
    if sheet.image then return sheet end
    local pixels=love.image.newImageData(root..sheet.file)
    local width,height=pixels:getDimensions()
    assert(width>=sheet.columns and height>=sheet.rows,
        "Outfit sprite sheet is smaller than its frame grid: "..sheet.file)
    sheet.image=love.graphics.newImage(pixels); sheet.image:setFilter("nearest","nearest")
    sheet.frames={}
    for index=1,sheet.columns*sheet.rows do
        local col,row=(index-1)%sheet.columns,math.floor((index-1)/sheet.columns)
        -- Mobile image packing resizes the complete sheet, so derive each
        -- frame from the decoded bounds instead of assuming authored pixels.
        local x,y=math.floor(col*width/sheet.columns),math.floor(row*height/sheet.rows)
        local right,bottom=math.floor((col+1)*width/sheet.columns)-1,math.floor((row+1)*height/sheet.rows)-1
        local left,top=x,y
        if sheet.tight then
            -- Measure alpha bounds as metadata; never alter authored pixels.
            local minX,minY,maxX,maxY=right,bottom,x,y
            local found=false
            for py=y,bottom do for px=x,right do
                local _,_,_,alpha=pixels:getPixel(px,py)
                if alpha>=32/255 then
                    found=true; minX=math.min(minX,px); minY=math.min(minY,py)
                    maxX=math.max(maxX,px); maxY=math.max(maxY,py)
                end
            end end
            if found then left=math.max(x,minX-2); top=math.max(y,minY-2); right=math.min(right,maxX+2); bottom=math.min(bottom,maxY+2) end
        end
        local w,h=right-left+1,bottom-top+1
        sheet.frames[index]={quad=love.graphics.newQuad(left,top,w,h,width,height),x=left,y=top,w=w,h=h}
    end
    pixels:release()
    return sheet
end

function Art.has(id) return sprites[id]~=nil or Definitions.upgrades[id]~=nil end
local panels={paper=true,card=true,["card-selected"]=true,button=true,["button-selected"]=true,["button-disabled"]=true}
local function drawPanel(sheet,frame,rect)
    if not frame.slices then
        frame.slices={}
        local bx,by=math.floor(frame.w*.18),math.floor(frame.h*.18)
        local xs,ys={0,bx,frame.w-bx,frame.w},{0,by,frame.h-by,frame.h}
        for row=1,3 do for col=1,3 do
            local w,h=xs[col+1]-xs[col],ys[row+1]-ys[row]
            frame.slices[(row-1)*3+col]={w=w,h=h,quad=love.graphics.newQuad(frame.x+xs[col],frame.y+ys[row],w,h,sheet.image:getDimensions())}
        end end
    end
    local border=math.min(14,rect.w*.18,rect.h*.24)
    local xs,ys={0,border,rect.w-border,rect.w},{0,border,rect.h-border,rect.h}
    for row=1,3 do for col=1,3 do
        local part=frame.slices[(row-1)*3+col]
        love.graphics.draw(sheet.image,part.quad,rect.x+xs[col],rect.y+ys[row],0,
            (xs[col+1]-xs[col])/part.w,(ys[row+1]-ys[row])/part.h)
    end end
end
function Art.draw(id,rect,options)
    options=options or {}
    local profile=Definitions.upgrades[id]
    local sprite=sprites[profile and profile.recipeId or id]
    if not sprite then return false end
    local sheet=loadSheet(sprite.sheet)
    local frame=sheet.frames[sprite.index]
    local sx,sy=rect.w/frame.w,rect.h/frame.h
    if not options.stretch then sx=math.min(sx,sy); sy=sx end
    local g=love.graphics
    g.push("all"); g.setColor(1,1,1,options.alpha or 1)
    if panels[id] and options.stretch and not options.rotation then drawPanel(sheet,frame,rect)
    else g.draw(sheet.image,frame.quad,rect.x+rect.w/2,rect.y+rect.h/2,options.rotation or 0,sx,sy,frame.w/2,frame.h/2) end
    g.pop()
    if profile and not options.noBadge then
        local size=math.min(rect.w,rect.h)*.34
        Art.draw("quality-"..profile.quality,{x=rect.x+rect.w-size,y=rect.y+rect.h-size,w=size,h=size})
    end
    return true
end

local background
function Art.background(rect)
    if not background then background=love.graphics.newImage(root.."bench-background-v1.png"); background:setFilter("nearest","nearest") end
    local g=love.graphics; g.push("all"); g.setColor(1,1,1,1)
    g.draw(background,rect.x,rect.y,0,rect.w/background:getWidth(),rect.h/background:getHeight()); g.pop()
end
function Art.segment(id,x1,y1,x2,y2,width)
    local dx,dy=x2-x1,y2-y1
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance<.5 then return end
    local angle=math.atan2(dy,dx)
    local unit=id=="stitch" and 12 or 10
    local count=math.max(1,math.ceil(distance/unit))
    for index=1,count do
        local fraction=(index-.5)/count
        local length=math.min(unit*.72,distance/count*.72)
        Art.draw(id,{x=x1+dx*fraction-length/2,y=y1+dy*fraction-(width or 3)/2,w=length,h=width or 3},{stretch=true,rotation=angle})
    end
end
function Art.workpiece(recipe,stage,rect)
    local material=stage and stage.material or "fabric"
    if recipe.icon=="gusset" then material="gusset"
    elseif recipe.id=="segmented-metal-insert" then material="metal"
    elseif recipe.id:find("leather",1,true) then material="leather"
    elseif recipe.id:find("wool",1,true) or recipe.id:find("weather",1,true) then material="wool"
    elseif recipe.id:find("canvas",1,true) then material="canvas" end
    local operation=stage and stage.operation
    local phase=not stage and 4 or ({mark=1,cut=2,pin=3,punch=3,deburr=2,stitch=3,quilt=3,bind=4,tension=4,secure=4,complete=4})[operation] or 1
    if material=="metal" and operation=="deburr" and (stage.stageIndex or 0)>4 then phase=3 end
    return Art.draw("work-"..material.."-"..phase,{x=rect.x+rect.w*.19,y=rect.y+rect.h*.18,w=rect.w*.62,h=rect.h*.64},{stretch=true})
end
local toolIds={["Chalk"]="chalk",["Scissors"]="scissors",["Pins"]="pins",["Needle"]="needle",["Awl"]="awl",
    ["Hand snips"]="hand-snips",["File"]="file",["Punch and mallet"]="punch-and-mallet",["Clips"]="clips",
    ["Two needles"]="two-needles",["Thread"]="thread-loop"}
function Art.tool(stage,rect) return Art.draw(toolIds[stage and stage.tool] or "needle",rect) end
return Art
