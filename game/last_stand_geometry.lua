-- Shared farmhouse collision; no assets, input, RNG or campaign writes.
local G={}
function G.walking(mode) return mode=='interior' or mode=='backyard' end
function G.spawn(mode,id) return id=='companion' and 505 or 480,mode=='interior' and 590 or 610 end
function G.walkable(mode,x,y)
    if not G.walking(mode) or type(x)~='number' or type(y)~='number' or x~=x or y~=y
        or x<70 or x>890 or y>620 then return false end
    if mode=='interior' then
        if y<285 or y>535 and (x<435 or x>525) then return false end
        if x>150 and x<340 and y>350 and y<523 then return false end
        if x>807 and x<872 and y>342 and y<405 then return false end
    else
        if y<360 or y>555 and (x<395 or x>590) then return false end
        if x>125 and x<340 and y>429 and y<530 then return false end
        if x>551 and x<739 and y>409 and y<513 then return false end
    end
    return true
end
function G.move(mode,oldX,oldY,x,y)
    local dx,dy=x-oldX,y-oldY
    local count=math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy)/5))
    local nx,ny=oldX,oldY
    for _=1,count do
        if G.walkable(mode,nx+dx/count,ny) then nx=nx+dx/count end
        if G.walkable(mode,nx,ny+dy/count) then ny=ny+dy/count end
    end
    return nx,ny
end
return G
