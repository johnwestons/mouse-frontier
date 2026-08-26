local Grid={}

Grid.COLS=9
Grid.ROWS=6
Grid.ORIGIN_X=450
Grid.ORIGIN_Y=92
Grid.STEP_X=48
Grid.STEP_Y=25
Grid.TILE_SCALE=.30
Grid.obstacleKinds={"dead-tree","rusty-car","ruined-shack","boulders","barricade","rail-cart"}
Grid.obstacleProfiles={
    ["dead-tree"]={sprite=1,blocksMovement=true,blocksSight=true,cover=3},
    ["rusty-car"]={sprite=2,blocksMovement=true,blocksSight=true,cover=3},
    ["ruined-shack"]={sprite=3,blocksMovement=true,blocksSight=true,cover=4},
    boulders={sprite=4,blocksMovement=true,blocksSight=true,cover=3},
    barricade={sprite=5,blocksMovement=true,blocksSight=false,cover=3},
    ["rail-cart"]={sprite=6,blocksMovement=true,blocksSight=false,cover=2},
}

local function key(q,r) return tostring(q)..":"..tostring(r) end

function Grid.boardToScreen(zoom,q,r)
    zoom=zoom or 1
    local x=Grid.ORIGIN_X+(q-r)*Grid.STEP_X
    local y=Grid.ORIGIN_Y+(q+r)*Grid.STEP_Y
    return Grid.ORIGIN_X+(x-Grid.ORIGIN_X)*zoom,Grid.ORIGIN_Y+(y-Grid.ORIGIN_Y)*zoom
end

function Grid.screenToBoardSpace(battle,zoom,x,y)
    zoom=zoom or 1
    x=Grid.ORIGIN_X+(x-Grid.ORIGIN_X)/zoom; y=Grid.ORIGIN_Y+(y-Grid.ORIGIN_Y)/zoom
    for q=0,Grid.COLS do for r=1,Grid.ROWS do if Grid.isBoardSpace(battle,q,r) then
        local bx=Grid.ORIGIN_X+(q-r)*Grid.STEP_X; local by=Grid.ORIGIN_Y+(q+r)*Grid.STEP_Y
        if math.abs(x-bx)/(Grid.STEP_X*.96)+math.abs(y-by)/(Grid.STEP_Y*.88)<=1 then return q,r end
    end end end
end

function Grid.distance(a,b) return math.abs(a.q-b.q)+math.abs(a.r-b.r) end
function Grid.isBoardSpace(battle,q,r) return battle and battle.tiles and battle.tiles[q] and battle.tiles[q][r]~=nil or false end
function Grid.obstacleAt(battle,q,r) return battle and battle.obstacles and battle.obstacles[key(q,r)] or nil end
function Grid.profile(obstacle) return obstacle and Grid.obstacleProfiles[obstacle.kind] or nil end
function Grid.blocksMovement(battle,q,r) local p=Grid.profile(Grid.obstacleAt(battle,q,r)); return p and p.blocksMovement or false end

local directions={{1,0},{0,-1},{-1,0},{0,1}}
Grid.directions=directions

local function occupied(battle,q,r,ignoreUnit)
    for _,unit in ipairs(battle and battle.units or {}) do if unit~=ignoreUnit and unit.hp>0 and unit.q==q and unit.r==r then return true end end
    return false
end

function Grid.reachable(battle,unit,maximum)
    local result={[key(unit.q,unit.r)]={q=unit.q,r=unit.r,cost=0}}
    local queue={{q=unit.q,r=unit.r,cost=0}}; local head=1
    while queue[head] do
        local current=queue[head]; head=head+1
        if current.cost<maximum then for _,direction in ipairs(directions) do
            local q,r=current.q+direction[1],current.r+direction[2]; local k=key(q,r)
            if not result[k] and Grid.isBoardSpace(battle,q,r) and not Grid.blocksMovement(battle,q,r) and not occupied(battle,q,r,unit) then
                result[k]={q=q,r=r,cost=current.cost+1}; queue[#queue+1]=result[k]
            end
        end end
    end
    return result
end

function Grid.canMove(battle,unit,q,r,maximum)
    local node=Grid.reachable(battle,unit,maximum)[key(q,r)]
    return node~=nil and not (q==unit.q and r==unit.r),node
end

function Grid.lineOfSight(battle,a,b)
    local dq,dr=b.q-a.q,b.r-a.r; local steps=math.max(math.abs(dq),math.abs(dr))
    if steps<=1 then return true,nil,0 end
    local checked={}; local cover=0
    for index=1,steps-1 do
        local q=math.floor(a.q+dq*index/steps+.5); local r=math.floor(a.r+dr*index/steps+.5); local k=key(q,r)
        if not checked[k] then
            checked[k]=true; local profile=Grid.profile(Grid.obstacleAt(battle,q,r))
            if profile then
                cover=math.max(cover,profile.cover or 0)
                if profile.blocksSight then return false,Grid.obstacleAt(battle,q,r),cover end
            end
        end
    end
    return true,nil,cover
end

function Grid.bestAdvance(battle,unit,target,maximum,preferred)
    local reachable=Grid.reachable(battle,unit,maximum); local best={q=unit.q,r=unit.r,cost=0}; local bestScore=math.huge
    for _,node in pairs(reachable) do
        local distance=Grid.distance(node,target); local sight=Grid.lineOfSight(battle,node,target)
        local score=math.abs(distance-preferred)*10+(distance<preferred and 8 or 0)+(sight and 0 or 5)-node.cost*.05
        if score<bestScore then best,bestScore=node,score end
    end
    return best
end

function Grid.generateObstacles(location,tier,rng)
    rng=rng or function(low,high) return love.math.random(low,high) end
    local desired=tier=="hard" and 7 or (tier=="medium" and 6 or 5)
    local result,candidates={},{ }
    for q=2,Grid.COLS-2 do for r=1,Grid.ROWS do
        if not (q==math.floor(Grid.COLS/2) and r==math.ceil(Grid.ROWS/2)) then candidates[#candidates+1]={q=q,r=r} end
    end end
    local offset=rng(1,#candidates)-1
    for index=1,desired do
        local candidate=candidates[((offset+(index-1)*5)%#candidates)+1]; local q,r=candidate.q,candidate.r
        local kind=Grid.obstacleKinds[((location+q*3+r*5+index)%#Grid.obstacleKinds)+1]
        result[key(q,r)]={q=q,r=r,kind=kind}
    end
    return result
end

function Grid.audit()
    local battle={tiles={},units={},obstacles={}}
    for q=0,Grid.COLS do battle.tiles[q]={}; for r=1,Grid.ROWS do battle.tiles[q][r]=1 end end
    local unit={q=0,r=3,hp=10}; battle.units={unit,{q=1,r=3,hp=10}}
    battle.obstacles["2:3"]={q=2,r=3,kind="ruined-shack"}
    local reachable=Grid.reachable(battle,unit,4)
    local canDetour=reachable["3:2"]~=nil; local cannotJump=reachable["2:3"]==nil
    local blocked=not Grid.lineOfSight(battle,{q=0,r=3},{q=4,r=3})
    local clear=Grid.lineOfSight(battle,{q=0,r=1},{q=4,r=1})
    local obstacles=Grid.generateObstacles(40,"hard",function(low) return low end); local count=0; for _ in pairs(obstacles) do count=count+1 end
    local x,y=Grid.boardToScreen(1.25,5,4); local q,r=Grid.screenToBoardSpace(battle,1.25,x,y)
    local ready=Grid.COLS==9 and Grid.ROWS==6 and Grid.COLS*Grid.ROWS+Grid.ROWS==60 and canDetour and cannotJump and blocked and clear and count==7 and q==5 and r==4
    return {ready=ready,columns=Grid.COLS+1,rows=Grid.ROWS,spaces=(Grid.COLS+1)*Grid.ROWS,obstacles=count,
        pathing=canDetour and cannotJump,lineOfSight=blocked and clear,zoomHitTest=q==5 and r==4,curve="battle-grid-v1"}
end

return Grid
