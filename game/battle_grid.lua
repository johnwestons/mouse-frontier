local Grid={}
local Field=require('game.battle_field')

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
    ['ruin-wall-x']={sprite=3,blocksMovement=true,blocksSight=true,cover=4},
    ['ruin-wall-z']={sprite=3,blocksMovement=true,blocksSight=true,cover=4},
}

local function key(q,r) return tostring(q)..":"..tostring(r) end

function Grid.dimensions(battle)
    local field=battle and battle.field
    return field and field.columns-1 or Grid.COLS,field and field.rows or Grid.ROWS
end
function Grid.elevation(battle,q,r)return Field.cellHeight(battle and battle.field,q,r)end

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

function Grid.moveBudget(battle,unit)
    local base=math.max(0,unit.move or 0)
    if not battle.field or unit.team~='ally'then return base end
    for _,enemy in ipairs(battle.units or {})do
        if enemy.team=='enemy' and enemy.hp>0 and Grid.distance(unit,enemy)<=9 then return base end
    end
    return math.max(base,8)
end

local function occupied(battle,q,r,ignoreUnit)
    for _,unit in ipairs(battle and battle.units or {}) do if unit~=ignoreUnit and unit.hp>0 and unit.q==q and unit.r==r then return true end end
    return false
end

function Grid.reachable(battle,unit,maximum)
    local result={[key(unit.q,unit.r)]={q=unit.q,r=unit.r,cost=0}}
    local cols,rows=Grid.dimensions(battle)
    maximum=math.max(0,math.min(math.floor(maximum or 0),(cols+1)*rows*2))
    -- Integer movement costs use bounded buckets, avoiding a whole-map sort.
    local buckets={[0]={result[key(unit.q,unit.r)]}}
    for cost=0,maximum do
        local queue=buckets[cost] or {};local head=1
        while queue[head]do
            local current=queue[head];head=head+1
            if current==result[key(current.q,current.r)] and cost<maximum then for _,direction in ipairs(directions)do
                local q,r=current.q+direction[1],current.r+direction[2];local k=key(q,r)
                if Grid.isBoardSpace(battle,q,r) and not Grid.blocksMovement(battle,q,r) and not occupied(battle,q,r,unit)then
                    local step=battle.field and Field.traversalCost(battle.field,current.q,current.r,q,r)or(not battle.field and 1)
                    local nextCost=step and cost+step
                    if nextCost and nextCost<=maximum and (not result[k]or nextCost<result[k].cost)then
                        local node={q=q,r=r,cost=nextCost,fromQ=current.q,fromR=current.r};result[k]=node
                        buckets[nextCost]=buckets[nextCost]or{};buckets[nextCost][#buckets[nextCost]+1]=node
                    end
                end
            end end
        end
    end
    return result
end

function Grid.path(battle,unit,q,r,maximum,reachable)
    reachable=reachable or Grid.reachable(battle,unit,maximum)
    local current=reachable[key(q,r)];if not current then return nil end
    local reverse={}
    while current do
        reverse[#reverse+1]={q=current.q,r=current.r}
        if current.fromQ==nil then break end
        current=reachable[key(current.fromQ,current.fromR)]
    end
    local path={};for i=#reverse,1,-1 do path[#path+1]=reverse[i]end
    return path
end

function Grid.canMove(battle,unit,q,r,maximum)
    local node=Grid.reachable(battle,unit,maximum)[key(q,r)]
    return node~=nil and not (q==unit.q and r==unit.r),node
end

function Grid.lineOfSight(battle,a,b)
    if battle.field then
        local field=battle.field;local x,z=a.q+.5,a.r-.5;local dx,dz=b.q-a.q,b.r-a.r
        local steps=math.max(1,math.ceil(math.sqrt(dx*dx+dz*dz)*4))
        local startHeight=Field.cellHeight(field,a.q,a.r)+.7
        local endHeight=Field.cellHeight(field,b.q,b.r)+.7
        local cover=0
        local heights={['dead-tree']=1.7,['rusty-car']=.84,['ruined-shack']=1.35,boulders=1.3,barricade=.78,['rail-cart']=.84}
        for i=1,steps-1 do
            local t=i/steps;local px,pz=x+dx*t,z+dz*t;local y=startHeight+(endHeight-startHeight)*t
            local q,r=math.floor(px),math.floor(pz)+1
            if Field.heightAt(field,px,pz)>y+.025 then return false,{kind='terrain-rise',q=q,r=r},cover end
            if not(q==a.q and r==a.r)and not(q==b.q and r==b.r)then
                local obstacle=Grid.obstacleAt(battle,q,r);local profile=Grid.profile(obstacle)
                if profile and y<Field.cellHeight(field,q,r)+(heights[obstacle.kind]or 1.3)then
                    cover=math.max(cover,profile.cover or 0)
                    if profile.blocksSight then return false,obstacle,cover end
                end
            end
        end
        return true,nil,cover
    end
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

-- Bounded A* for patrol groups: a six-space house must not trap a hunter
-- against its nearest wall. Only the active enemy plans a route.
function Grid.pursuitStep(battle,unit,target,maximum,preferred)
    local occupiedCells={}
    for _,u in ipairs(battle.units)do if u~=unit and u.hp>0 then occupiedCells[key(u.q,u.r)]=true end end
    local first={q=unit.q,r=unit.r,cost=0};first.score=math.max(0,Grid.distance(first,target)-preferred)
    local open={first};local known={[key(first.q,first.r)]=first};local goal=first;local bestDistance=Grid.distance(first,target)
    for _=1,384 do
        if #open==0 then break end
        local index=1
        for i=2,#open do local a,b=open[i],open[index]
            if a.score<b.score or a.score==b.score and(a.q<b.q or a.q==b.q and a.r<b.r)then index=i end
        end
        local current=table.remove(open,index)
        if not current.closed then
            current.closed=true;local d=Grid.distance(current,target)
            if d<bestDistance then goal,bestDistance=current,d end
            if d<=preferred and Grid.lineOfSight(battle,current,target)then goal=current;break end
            for _,v in ipairs(directions)do
                local q,r=current.q+v[1],current.r+v[2];local k=key(q,r)
                if Grid.isBoardSpace(battle,q,r)and not occupiedCells[k]and not Grid.blocksMovement(battle,q,r)then
                    local step=Field.traversalCost(battle.field,current.q,current.r,q,r)
                    local cost=step and current.cost+step;local prior=known[k]
                    if cost and(not prior or cost<prior.cost)then
                        local p={q=q,r=r,cost=cost,parent=current,score=cost+math.max(0,Grid.distance({q=q,r=r},target)-preferred)}
                        known[k]=p;open[#open+1]=p
                    end
                end
            end
        end
    end
    while goal.parent and goal.cost>maximum do goal=goal.parent end
    return goal
end
function Grid.bestAdvance(battle,unit,target,maximum,preferred)
    if battle.field and unit.patrolQ then return Grid.pursuitStep(battle,unit,target,maximum,preferred)end
    local reachable=Grid.reachable(battle,unit,maximum); local best={q=unit.q,r=unit.r,cost=0}; local bestScore=math.huge
    for _,node in pairs(reachable) do
        local distance=Grid.distance(node,target); local sight=Grid.lineOfSight(battle,node,target)
        local score=math.abs(distance-preferred)*10+(distance<preferred and 8 or 0)+(sight and 0 or 5)-node.cost*.05
        if score<bestScore or (battle.field and score==bestScore and (node.q<best.q or node.q==best.q and node.r<best.r)) then best,bestScore=node,score end
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
