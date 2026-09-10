local Sprites={FRAME_SIZE=512,ANCHOR_X=256,ANCHOR_Y=492}
local hasFFI,ffi=pcall(require,"ffi")
-- Reviewed empty pockets inside the original sources' closed tendril/tail
-- loops. They seed the same connected flood as the border; no foreground
-- color is erased globally. Coordinates belong to these immutable sources.
local matteProfiles={
    ["sludge-bandit"]={
        baseFacing=1,
        actions={{{329,91}},{{323,85}},{{338,122}},{{283,93}},{{334,204},{400,241},{434,300},{128,386}},{}},
        walk={{{337,73}},{{286,74}},{{275,72}},{{271,59}},{{344,40}},{{303,41}},{{291,38}},{{300,35}}},
        walkV5={{{333,72}},{{299,75}},{{293,74}},{{284,60}},{{318,37}},{{307,42}},{{292,38}},{{302,40}}},
    },
    ["sludge-badger-boss"]={
        baseFacing=-1,
        actions={{{249,114},{342,126},{327,313}},{{316,102},{141,293},{112,360}},{{276,105}},
            {{251,63},{152,312},{140,340}},{{293,156},{386,188},{375,223},{402,348}},{{377,76}}},
        walk={{{258,78},{349,86}},{{320,95},{364,97},{356,145}},{{263,56},{293,93},{358,107}},
            {{286,56},{334,87},{349,138}},{{285,63},{329,92}},{{272,47},{333,81},{324,101}},
            {{266,52},{346,103}},{{277,42},{329,70},{299,79}}},
        walkV4={{{218,101},{305,113},{300,264}},{{227,97},{308,107},{294,259},{337,319}},
            {{286,105},{330,178},{281,258}},{{223,96},{312,108},{291,262},{331,329}},
            {{218,69},{318,75},{299,235}},{{232,65},{314,77},{297,232},{326,290}},
            {{261,77},{305,84},{292,229},{328,304}},{{223,68},{315,84},{286,230}}},
    },
}

local function buffer(kind,count)
    return hasFFI and ffi.new(kind.."[?]",count) or {}
end

local function release(object)
    if object and object.release then object:release() end
end

local function bounds(data)
    local width,height=data:getDimensions()
    local left,top,right,bottom=width,height,-1,-1
    local opaque=0
    for y=0,height-1 do for x=0,width-1 do
        local _,_,_,a=data:getPixel(x,y)
        if a>.06 then
            left=math.min(left,x); right=math.max(right,x)
            top=math.min(top,y); bottom=math.max(bottom,y); opaque=opaque+1
        end
    end end
    if opaque==0 then return nil end
    return {left=left,top=top,right=right,bottom=bottom,width=right-left+1,height=bottom-top+1,pixels=opaque}
end

-- Only bright neutral pixels connected to a cell border or a reviewed empty
-- pocket seed are matte. Enclosed eyes, teeth, fur and glints remain intact.
function Sprites.cleanMatte(data,seeds)
    local width,height=data:getDimensions()
    local size=width*height
    local mask,queue=buffer("uint8_t",size),buffer("int32_t",size)
    for y=0,height-1 do for x=0,width-1 do
        local r,g,b,a=data:getPixel(x,y)
        local hi,lo=math.max(r,g,b),math.min(r,g,b)
        mask[y*width+x]=(a<.01 or (hi-lo<.075 and lo>.60)) and 1 or 0
    end end
    local head,tail=0,0
    local function push(index)
        if mask[index]==1 then mask[index]=2; queue[tail]=index; tail=tail+1 end
    end
    for x=0,width-1 do push(x); push((height-1)*width+x) end
    for y=1,height-2 do push(y*width); push(y*width+width-1) end
    for _,seed in ipairs(seeds or {}) do
        local x,y=math.floor(seed[1]),math.floor(seed[2])
        if x>=0 and y>=0 and x<width and y<height then push(y*width+x) end
    end
    while head<tail do
        local index=queue[head]; head=head+1
        local x=index%width
        if x>0 then push(index-1) end
        if x<width-1 then push(index+1) end
        if index>=width then push(index-width) end
        if index<size-width then push(index+width) end
    end
    local removedPixels=tail
    local components={}
    for start=0,size-1 do
        if mask[start]==1 then
            head,tail=0,1; queue[0]=start; mask[start]=3
            local sx,sy=start%width,math.floor(start/width)
            local component={seedX=sx,seedY=sy,left=sx,right=sx,top=sy,bottom=sy,pixels=0}
            local function visit(index)
                if mask[index]==1 then mask[index]=3; queue[tail]=index; tail=tail+1 end
            end
            while head<tail do
                local index=queue[head]; head=head+1
                local x,y=index%width,math.floor(index/width)
                component.left=math.min(component.left,x); component.right=math.max(component.right,x)
                component.top=math.min(component.top,y); component.bottom=math.max(component.bottom,y)
                component.pixels=component.pixels+1
                if x>0 then visit(index-1) end
                if x<width-1 then visit(index+1) end
                if index>=width then visit(index-width) end
                if index<size-width then visit(index+width) end
            end
            if component.pixels>=40 then components[#components+1]=component end
        end
    end
    local retainedNeutral=0
    data:mapPixel(function(x,y,r,g,b,a)
        local value=mask[y*width+x]
        if value==2 then return 0,0,0,0 end
        if value==3 and a>.06 then retainedNeutral=retainedNeutral+1 end
        return r,g,b,a
    end)
    return {removedPixels=removedPixels,retainedNeutralPixels=retainedNeutral,enclosedNeutralComponents=components,bounds=bounds(data)}
end

local function median(values)
    local ordered={}
    for index,value in ipairs(values) do ordered[index]=value end
    table.sort(ordered)
    local center=math.floor(#ordered/2)
    return #ordered%2==0 and (ordered[center]+ordered[center+1])/2 or ordered[center+1]
end

function Sprites.load(definition)
    assert(type(definition)=="table" and definition.actionPath,"expedition sprites require an action atlas")
    local temporary,created={},{ }
    local function keep(data) temporary[#temporary+1]=data; return data end
    local function read(path)
        return keep(definition.readImageData and definition.readImageData(path) or love.image.newImageData(path))
    end
    local profile=definition.matteSeeds or matteProfiles[definition.actionPath:gsub("\\","/"):match("([^/]+)%-action%-atlas%.png$")] or {}
    local function split(path,columns,rows,seeds)
        local source=read(path)
        local width,height=source:getDimensions()
        local frames,metrics={},{}
        for row=0,rows-1 do for column=0,columns-1 do
            -- Fractional grid boundaries cover the complete 1774x887 sources.
            local left,right=math.floor(column*width/columns),math.floor((column+1)*width/columns)
            local top,bottom=math.floor(row*height/rows),math.floor((row+1)*height/rows)
            local frame=keep(love.image.newImageData(right-left,bottom-top))
            frame:paste(source,0,0,left,top,right-left,bottom-top)
            local metric=Sprites.cleanMatte(frame,seeds and seeds[row*columns+column+1])
            assert(metric.bounds,"empty expedition sprite frame in "..path)
            frames[#frames+1]=frame; metrics[#metrics+1]=metric
        end end
        return frames,metrics
    end
    local ok,result=xpcall(function()
        local rawActions,actionMetrics=split(definition.actionPath,3,2,profile.actions)
        local rawWalk,walkMetrics={},{}
        if definition.walkPath then
            local seeds=definition.walkPath:find("%-walk%-v5%.png$") and profile.walkV5
                or (definition.walkPath:find("%-walk%-v4%.png$") and profile.walkV4)
                or (definition.walkPath:find("%-walk%-v2%.png$") and profile.walk) or nil
            rawWalk,walkMetrics=split(definition.walkPath,4,2,seeds)
        end
        local function safeScale(metrics,preferred)
            local scale=preferred
            for _,metric in ipairs(metrics) do
                scale=math.min(scale,(Sprites.FRAME_SIZE-24)/metric.bounds.width,(Sprites.ANCHOR_Y-12)/metric.bounds.height)
            end
            return scale
        end
        local actionScale=safeScale(actionMetrics,1)
        local referenceHeight=actionMetrics[1].bounds.height*actionScale
        local walkHeights={}
        for _,metric in ipairs(walkMetrics) do walkHeights[#walkHeights+1]=metric.bounds.height end
        local walkScale=#walkHeights>0 and safeScale(walkMetrics,referenceHeight/median(walkHeights)) or 1
        local asset={actions={},walkFrames={},anchors={actions={},walk={}},referenceHeight=referenceHeight,
            baseFacing=definition.baseFacing or profile.baseFacing or 1,
            pixelsPerFrame=definition.pixelsPerFrame or (definition.boss and 9 or 8),
            audit={mattePolicy="border-and-reviewed-pocket-connected-neutral",actionScale=actionScale,walkScale=walkScale,
                actionFrames=actionMetrics,walkFrames=walkMetrics,pilot=true,fullDirectionalAcceptance=false}}
        local function normalize(raw,metrics,scale,images,anchors)
            for index,source in ipairs(raw) do
                local sourceBounds=metrics[index].bounds
                local sourceAnchorX=(sourceBounds.left+sourceBounds.right)/2
                local sourceAnchorY=sourceBounds.bottom
                local frame=keep(love.image.newImageData(Sprites.FRAME_SIZE,Sprites.FRAME_SIZE))
                local width,height=source:getDimensions()
                frame:mapPixel(function(x,y)
                    local sx=math.floor((x-Sprites.ANCHOR_X)/scale+sourceAnchorX+.5)
                    local sy=math.floor((y-Sprites.ANCHOR_Y)/scale+sourceAnchorY+.5)
                    if sx<0 or sy<0 or sx>=width or sy>=height then return 0,0,0,0 end
                    return source:getPixel(sx,sy)
                end)
                local normalizedBounds=bounds(frame)
                metrics[index].normalizedBounds=normalizedBounds
                metrics[index].sourceEdgeContact=sourceBounds.left<2 or sourceBounds.top<2 or sourceBounds.right>=width-2 or sourceBounds.bottom>=height-2
                assert(normalizedBounds.bottom==Sprites.ANCHOR_Y,"expedition sprite ground anchor drift")
                local image=love.graphics.newImage(frame); image:setFilter("nearest","nearest")
                created[#created+1]=image; images[index]=image
                anchors[index]={x=Sprites.ANCHOR_X,y=Sprites.ANCHOR_Y}
            end
        end
        normalize(rawActions,actionMetrics,actionScale,asset.actions,asset.anchors.actions)
        normalize(rawWalk,walkMetrics,walkScale,asset.walkFrames,asset.anchors.walk)
        for index,image in ipairs(asset.actions) do asset[index]=image end
        return asset
    end,debug.traceback)
    for _,data in ipairs(temporary) do release(data) end
    if not ok then for _,image in ipairs(created) do release(image) end; error(result) end
    return result
end

function Sprites.release(asset)
    if not asset or asset.released then return end
    local seen={}
    for _,images in ipairs({asset.actions or asset,asset.walkFrames or {}}) do
        for _,image in ipairs(images) do if not seen[image] then seen[image]=true; release(image) end end
    end
    asset.released=true
end

return Sprites
