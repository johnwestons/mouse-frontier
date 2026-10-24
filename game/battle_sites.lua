-- Shared, seed-stable building footprints. Walls are tactical obstacles;
-- interiors and doorways remain traversable at every decoration quality.
local Sites={}
local cache=setmetatable({},{__mode='k'})
function Sites.list(field)
    if not field or field.version<3 then return {} end
    local cached=cache[field];if cached and cached.seed==field.seed then return cached.sites end
    local result={}
    for col,q in ipairs({6,23,43,62})do
        for row,r in ipairs({7,13,28})do
            local n=(col-1)*3+row
            local variant=(field.seed+n*97)%65521
            result[#result+1]={q=q+variant%3-1,r=r,w=5+math.floor(variant/3)%3,d=4+math.floor(variant/11)%3,style=(field.seed+n*17)%3+1}
        end
    end
    cache[field]={seed=field.seed,sites=result};return result
end
function Sites.at(field,q,r,sites)
    for _,s in ipairs(sites or Sites.list(field))do
        if q>=s.q and q<s.q+s.w and r>=s.r and r<s.r+s.d then return s,q-s.q,r-s.r end
    end
end
function Sites.wall(s,x,z)
    -- Two opposing entrances avoid making a room into a dead end.
    if s.style==2 and z==0 and x==s.w-2 or s.style==3 and x==s.w-1 and z==s.d-2 then return nil end
    if (z==0 or z==s.d-1)and x~=2 and x~=3 then return 'ruin-wall-x' end
    if x==0 or x==s.w-1 then return 'ruin-wall-z' end
end
function Sites.flatten(field,x,z,height)
    local maximum=0
    for _,s in ipairs(Sites.list(field))do
        local dx=math.max(s.q-x,0,x-(s.q+s.w))
        local dz=math.max((s.r-1)-z,0,z-(s.r+s.d-1))
        local d=math.max(dx,dz)
        if d<1.5 then
            if d==0 then return .125 end
            maximum=math.max(maximum,1-d/1.5)
        end
    end
    return height*(1-maximum)+.125*maximum
end
return Sites
