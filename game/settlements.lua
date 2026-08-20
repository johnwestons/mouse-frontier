local Settlements = {}

Settlements.count = 55
Settlements.walkway = {left=120,right=840,top=395,bottom=650}

-- Authored against settlement-wide-01 using the player's marked reference
-- (1147 x 648).  The large polygon follows the highlighted courtyard and
-- lower paths; the smaller polygons add the raised side paths.  Holes keep
-- the well, crop beds, and fenced pen solid.
local referenceW,referenceH=1147,648
local maskStops={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true,[17]=true,[18]=true,[19]=true,[20]=true,[21]=true,[22]=true,[23]=true,[24]=true,[25]=true,[26]=true,[27]=true,[28]=true,[29]=true,[30]=true,[31]=true,[32]=true,[33]=true,[34]=true,[35]=true,[36]=true,[37]=true,[38]=true,[39]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,[46]=true,[47]=true,[48]=true,[49]=true,[50]=true,[51]=true}
local stop01Walkable={
    -- Stop 1's revised purple walk mask: the broad central courtyard and
    -- every connected plank/dirt branch marked in the latest reference.
    {{145,390},{205,350},{300,326},{395,334},{470,309},{560,322},{650,315},
     {745,326},{835,344},{930,355},{1035,389},{1115,445},{1128,505},{1065,532},
     {970,526},{885,545},{810,579},{745,620},{650,626},{575,602},{505,570},
     {420,579},{340,560},{260,526},{190,480},{140,430}},
    -- Left house approach and porch boards.
    {{180,375},{230,330},{292,300},{340,315},{360,350},{320,385},{275,410},{225,430}},
    -- Center house steps and the boardwalk branch to the garden.
    {{420,330},{470,292},{535,280},{595,302},{610,345},{575,374},{520,360},{470,382}},
    {{585,362},{650,340},{720,350},{770,380},{746,410},{680,397},{625,420}},
    -- Right house approach.
    {{835,350},{900,330},{975,345},{1035,382},{1020,430},{975,445},{930,415},{870,405}},
    -- Upper-right fenced clearing, joined to the courtyard by its narrow path.
    {{790,180},{850,145},{940,138},{1015,160},{1050,205},{1025,250},{960,265},
     {900,245},{850,270},{805,245}},
    {{735,285},{770,258},{825,250},{860,275},{830,315},{785,320}},
    -- Far-left porch/outer path visible in the revised mask.
    {{72,330},{130,315},{188,340},{214,382},{190,430},{135,448},{82,420},{70,378}},
    -- Lower-left and lower-edge paths around the fenced perimeter.
    {{92,470},{160,465},{230,500},{300,545},{355,585},{335,632},{250,642},{180,620},{115,585},{78,535}},
    {{350,585},{430,565},{510,578},{595,612},{690,625},{760,650},{690,670},{555,661},{455,645},{380,625}},
    -- Right-hand return path and the raised upper-right clearing.
    {{850,405},{920,390},{1000,402},{1080,430},{1140,470},{1135,525},{1060,535},{985,510},{920,475},{860,455}}
}

-- comma repair for the extended stop 1 walk polygons is kept above
local stop01Blocked={
    -- Building footprints: only their stairs/porches are included in the
    -- walkable polygons above.
    {{35,55},{325,60},{342,184},{318,298},{280,330},{215,315},{150,285},{85,250}},
    {{385,78},{760,70},{800,170},{785,285},{735,320},{640,305},{560,290},{470,305},{400,260}},
    {{875,205},{1100,220},{1140,350},{1090,430},{1035,430},{1005,360},{940,345},{880,320}},
    -- Stone well and raised crop beds.
    {{430,430},{485,402},{540,425},{555,475},{525,510},{470,507},{430,480}},
    {{650,360},{755,340},{835,375},{865,430},{830,485},{745,510},{665,485},{635,425}},
    -- Lower fenced garden/pen; the path remains outside the fence.
    {{720,530},{1115,515},{1140,585},{765,620},{700,585}}
}

local function pointInPolygon(x,y,polygon)
    local inside=false
    local j=#polygon
    for i=1,#polygon do
        local xi,yi=polygon[i][1],polygon[i][2]
        local xj,yj=polygon[j][1],polygon[j][2]
        if ((yi>y)~=(yj>y)) and x < (xj-xi)*(y-yi)/(yj-yi)+xi then inside=not inside end
        j=i
    end
    return inside
end

local function settlementNumber(index)
    return ((index or 1)-1)%Settlements.count+1
end

local function stop01Point(x,y)
    local sx,sy=x/960*referenceW,y/720*referenceH
    local inside=false
    for _,polygon in ipairs(stop01Walkable) do
        if pointInPolygon(sx,sy,polygon) then inside=true; break end
    end
    if not inside then return false end
    for _,polygon in ipairs(stop01Blocked) do
        if pointInPolygon(sx,sy,polygon) then return false end
    end
    return true
end

function Settlements.isWalkable(index,x,y)
    local mask=Settlements.walkMasks and Settlements.walkMasks[settlementNumber(index)]
    if mask then
        local mw,mh=mask:getDimensions()
        local function sample(px,py)
            local ix=math.max(0,math.min(mw-1,math.floor(px/960*mw)))
            local iy=math.max(0,math.min(mh-1,math.floor(py/720*mh)))
            return select(1,mask:getPixel(ix,iy))>.5
        end
        local radius=6
        return sample(x,y) and sample(x-radius,y) and sample(x+radius,y)
            and sample(x,y-radius) and sample(x,y+radius)
    end
    if settlementNumber(index)~=1 then
        local w=Settlements.walkway
        return x>=w.left and x<=w.right and y>=w.top and y<=w.bottom
    end
    -- Sample around the feet as well as at their center, preventing the
    -- character from visually stepping through a wall at polygon corners.
    local radius=7
    return stop01Point(x,y) and stop01Point(x-radius,y) and stop01Point(x+radius,y)
        and stop01Point(x,y-radius*.55) and stop01Point(x,y+radius*.55)
end

function Settlements.load(loadImage)
    -- Keep only the current stop resident.  Full-screen settlement PNGs are
    -- among the largest textures in the game, so decoding all of them during
    -- love.load made startup and GPU allocation grow with every new stop.
    local result={wide={},paths={},loadImage=loadImage,active=nil,walkMasks={}}
    local root="assets/sprites/stops"
    if love.filesystem.getInfo(root) then
        local highest=0
        for _,file in ipairs(love.filesystem.getDirectoryItems(root)) do
            local number=tonumber(file:match("^settlement%-wide%-(%d+)%.png$"))
            if number then result.paths[number]=root.."/"..file; highest=math.max(highest,number) end
        end
        if highest>0 then Settlements.count=highest end
    end
    for index in pairs(maskStops) do
        local ok,mask=pcall(love.image.newImageData,string.format("assets/sprites/stops/walkmask-%02d.png",index))
        if ok then result.walkMasks[index]=mask end
    end
    Settlements.walkMasks=result.walkMasks
    return result
end

local function releaseImage(image)
    if image and image.release then pcall(image.release,image) end
end

function Settlements.activate(images,index)
    if not images then return nil end
    local number=settlementNumber(index)
    if images.active==number and images.wide[number] then return images.wide[number] end
    for key,image in pairs(images.wide or {}) do
        if key~=number then releaseImage(image); images.wide[key]=nil end
    end
    images.active=number
    if not images.wide[number] and images.loadImage then
        local path=images.paths[number] or string.format("assets/sprites/stops/settlement-wide-%02d.png",number)
        local image=images.loadImage(path)
        if image then image:setFilter("linear","linear"); images.wide[number]=image end
    end
    return images.wide[number]
end

function Settlements.release(images)
    if not images then return end
    for key,image in pairs(images.wide or {}) do releaseImage(image); images.wide[key]=nil end
    images.active=nil
end

function Settlements.draw(images,index,W,H)
    local wide=Settlements.activate(images,index)
    if wide then
        love.graphics.setColor(1,1,1)
        love.graphics.draw(wide,0,0,0,W/wide:getWidth(),H/wide:getHeight())
        return true
    end
    local image=images and images[((index-1)%Settlements.count)+1]
    if not image then return false end
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,0,0,0,W/image:getWidth(),H/image:getHeight())
    return true
end

function Settlements.clamp(x,y,index)
    local w=Settlements.walkway
    if not Settlements.walkMasks or not Settlements.walkMasks[settlementNumber(index)] then
        if settlementNumber(index)~=1 then
        return math.max(w.left,math.min(w.right,x)),math.max(w.top,math.min(w.bottom,y))
        end
    end
    if Settlements.isWalkable(index,x,y) then return x,y end
    -- Used for old saves and wandering NPC targets that land off-path.
    for radius=6,720,6 do
        for step=0,47 do
            local angle=step/48*math.pi*2
            local nx,ny=x+math.cos(angle)*radius,y+math.sin(angle)*radius
            if Settlements.isWalkable(index,nx,ny) then return nx,ny end
        end
    end
    return 270,490
end

function Settlements.move(index,oldX,oldY,newX,newY)
    if Settlements.isWalkable(index,newX,newY) then return newX,newY end
    -- Preserve smooth wall-sliding instead of snapping or teleporting.
    if Settlements.isWalkable(index,newX,oldY) then return newX,oldY end
    if Settlements.isWalkable(index,oldX,newY) then return oldX,newY end
    return oldX,oldY
end

local stop01Doors={
    -- Interaction anchors sit on the highlighted step/porch immediately in
    -- front of each green-marked door.
    {x=234,y=406},
    {x=465,y=350},
    {x=853,y=433},
}
local markedDoors={
    [2]={{x=274,y=346},{x=529,y=224},{x=670,y=341}},
    [3]={{x=169,y=361},{x=620,y=214},{x=434,y=567},{x=799,y=430}},
    [4]={{x=268,y=311},{x=635,y=112},{x=681,y=339}},
    [5]={{x=220,y=512},{x=406,y=302},{x=630,y=384}},
    [6]={{x=291,y=298},{x=470,y=303},{x=737,y=310}},
    [7]={{x=258,y=290},{x=429,y=196},{x=674,y=309}},
    [8]={{x=263,y=470},{x=412,y=192},{x=689,y=345}},
    [9]={{x=280,y=198},{x=690,y=265},{x=395,y=506}},
    [10]={{x=433,y=216},{x=751,y=252},{x=785,y=497}},
    [11]={{x=486,y=218},{x=674,y=299},{x=708,y=540}},
    [12]={{x=182,y=404},{x=585,y=321},{x=712,y=497}},
    [13]={{x=231,y=369},{x=689,y=265},{x=733,y=540}},
    [14]={{x=361,y=279},{x=273,y=463},{x=744,y=462}},
    [15]={{x=198,y=299},{x=470,y=193},{x=594,y=258},{x=807,y=388}},
    [16]={{x=481,y=221},{x=627,y=306},{x=818,y=487}},
    [17]={{x=321,y=377},{x=572,y=253},{x=718,y=451}},
    [18]={{x=219,y=449},{x=400,y=294},{x=692,y=351},{x=831,y=434},{x=190,y=617},{x=635,y=618}},
    [19]={{x=337,y=213},{x=669,y=233}},
    [20]={{x=250,y=306},{x=836,y=432},{x=192,y=561}},
    [21]={{x=510,y=219},{x=634,y=216},{x=773,y=232},{x=337,y=406},{x=719,y=465},{x=919,y=490}},
    [22]={{x=203,y=314},{x=505,y=223},{x=784,y=340}},
    [23]={{x=191,y=436},{x=432,y=399},{x=758,y=436}},
    [24]={{x=270,y=638},{x=740,y=315},{x=766,y=529},{x=428,y=653}},
    [25]={{x=277,y=242},{x=727,y=319},{x=775,y=497}},
    [26]={{x=175,y=396},{x=330,y=516},{x=624,y=290},{x=666,y=474},{x=791,y=617}},
    [27]={{x=170,y=481},{x=270,y=477},{x=507,y=252},{x=620,y=419},{x=806,y=467},{x=689,y=621}},
    [28]={{x=295,y=295},{x=535,y=303},{x=815,y=285},{x=189,y=574},{x=441,y=610},{x=700,y=540}},
    [29]={{x=273,y=570},{x=459,y=226},{x=665,y=363}},
    [30]={{x=159,y=440},{x=446,y=295},{x=754,y=309},{x=773,y=467}},
    [31]={{x=279,y=213},{x=486,y=247},{x=173,y=309},{x=362,y=512},{x=553,y=500},{x=786,y=594}},
    [32]={{x=208,y=251},{x=452,y=224},{x=800,y=334},{x=719,y=602}},
    [33]={{x=301,y=249},{x=567,y=119},{x=744,y=145},{x=788,y=333},{x=682,y=624}},
    [34]={{x=341,y=315},{x=265,y=442},{x=590,y=370},{x=693,y=464},{x=209,y=571}},
    [35]={{x=204,y=299},{x=326,y=261},{x=449,y=159},{x=719,y=338},{x=758,y=485}},
    [36]={{x=280,y=215},{x=298,y=322},{x=479,y=247},{x=674,y=354},{x=785,y=344},{x=360,y=572},{x=637,y=560}},
    [37]={{x=247,y=442},{x=407,y=319},{x=492,y=276},{x=619,y=362},{x=812,y=456}},
    [38]={{x=327,y=322},{x=471,y=401},{x=686,y=260},{x=799,y=392},{x=676,y=605}},
    [39]={{x=315,y=285},{x=503,y=210},{x=681,y=295},{x=613,y=510}},
    [40]={{x=453,y=265},{x=804,y=294},{x=239,y=480}},
    [41]={{x=269,y=244},{x=304,y=348},{x=531,y=247},{x=747,y=431}},
    [42]={{x=367,y=265},{x=543,y=254},{x=765,y=344},{x=154,y=439}},
    [43]={{x=360,y=207},{x=628,y=188},{x=156,y=396},{x=737,y=405}},
    [44]={{x=274,y=346},{x=536,y=263},{x=785,y=331}},
    [45]={{x=313,y=239},{x=596,y=312},{x=141,y=502}},
    [46]={{x=596,y=199},{x=206,y=394},{x=802,y=385}},
    [47]={{x=262,y=291},{x=483,y=290},{x=640,y=193},{x=765,y=345},{x=153,y=327}},
    [48]={{x=431,y=168},{x=346,y=444},{x=639,y=513}},
    [49]={{x=283,y=192},{x=478,y=394},{x=667,y=634}},
    [50]={{x=145,y=165},{x=428,y=214},{x=833,y=156},{x=261,y=407},{x=750,y=434}},
    [51]={{x=145,y=209},{x=699,y=252},{x=599,y=568}},
}

function Settlements.doorPoint(index,doorIndex)
    local marked=markedDoors[settlementNumber(index)]
    if marked then
        local door=marked[math.max(1,math.min(#marked,doorIndex or 1))]
        return door.x,door.y
    end
    if settlementNumber(index)==1 then
        local door=stop01Doors[math.max(1,math.min(#stop01Doors,doorIndex or 1))]
        return door.x,door.y
    end
    local doors={{x=300,y=430},{x=660,y=430}}
    local door=doors[math.max(1,math.min(#doors,doorIndex or 1))]
    return door.x,door.y
end

function Settlements.nearDoor(x,y,index)
    local marked=markedDoors[settlementNumber(index)]
    if marked then
        for i,door in ipairs(marked) do
            if math.abs(x-door.x)<68 and math.abs(y-door.y)<58 then return i end
        end
        return nil
    end
    if settlementNumber(index)==1 then
        for i,door in ipairs(stop01Doors) do
            if math.abs(x-door.x)<62 and math.abs(y-door.y)<54 then return i end
        end
        return nil
    end
    -- Two door approaches are reserved on every generated settlement sprite.
    local doors={{x=300,y=430},{x=660,y=430}}
    for i,door in ipairs(doors) do
        if math.abs(x-door.x)<72 and math.abs(y-door.y)<58 then return i end
    end
end

function Settlements.trainPoint(index)
    if settlementNumber(index)==1 then return 198,688 end
    if settlementNumber(index)==2 then return 568,672 end
    if settlementNumber(index)==3 then return 121,646 end
    if settlementNumber(index)==4 then return 62,467 end
    if settlementNumber(index)==5 then return 55,608 end
    if settlementNumber(index)==6 then return 94,642 end
    if settlementNumber(index)==7 then return 255,692 end
    if settlementNumber(index)==8 then return 134,553 end
    if settlementNumber(index)==9 then return 24,645 end
    if settlementNumber(index)==10 then return 679,177 end
    if settlementNumber(index)==11 then return 34,561 end
    if settlementNumber(index)==12 then return 537,697 end
    if settlementNumber(index)==13 then return 350,200 end
    if settlementNumber(index)==14 then return 514,675 end
    if settlementNumber(index)==15 then return 220,653 end
    if settlementNumber(index)==16 then return 34,571 end
    if settlementNumber(index)==17 then return 506,683 end
    if settlementNumber(index)==18 then return 400,678 end
    if settlementNumber(index)==19 then return 242,544 end
    if settlementNumber(index)==20 then return 291,689 end
    if settlementNumber(index)==21 then return 634,689 end
    if settlementNumber(index)==22 then return 14,280 end
    if settlementNumber(index)==23 then return 592,214 end
    if settlementNumber(index)==24 then return 237,599 end
    if settlementNumber(index)==25 then return 416,672 end
    if settlementNumber(index)==26 then return 395,683 end
    if settlementNumber(index)==27 then return 259,679 end
    if settlementNumber(index)==28 then return 929,502 end
    if settlementNumber(index)==29 then return 29,621 end
    if settlementNumber(index)==30 then return 378,689 end
    if settlementNumber(index)==31 then return 925,384 end
    if settlementNumber(index)==32 then return 455,687 end
    if settlementNumber(index)==33 then return 240,685 end
    if settlementNumber(index)==34 then return 525,702 end
    if settlementNumber(index)==35 then return 35,620 end
    if settlementNumber(index)==36 then return 923,395 end
    if settlementNumber(index)==37 then return 85,638 end
    if settlementNumber(index)==38 then return 305,690 end
    if settlementNumber(index)==39 then return 70,670 end
    if settlementNumber(index)==40 then return 550,690 end
    if settlementNumber(index)==41 then return 497,690 end
    if settlementNumber(index)==42 then return 209,670 end
    if settlementNumber(index)==43 then return 675,700 end
    if settlementNumber(index)==44 then return 137,672 end
    if settlementNumber(index)==45 then return 736,683 end
    if settlementNumber(index)==46 then return 303,688 end
    if settlementNumber(index)==47 then return 56,262 end
    if settlementNumber(index)==48 then return 102,662 end
    if settlementNumber(index)==49 then return 32,663 end
    if settlementNumber(index)==50 then return 35,580 end
    if settlementNumber(index)==51 then return 24,406 end
    return 145,405
end

function Settlements.nearTrain(x,y,index)
    if settlementNumber(index)<=51 then
        local tx,ty=Settlements.trainPoint(index)
        return math.abs(x-tx)<58 and math.abs(y-ty)<42
    end
    return x<215 and y<430
end

return Settlements
