-- Presentation only. These preferences never enter a campaign or co-op command.
local Preferences=require('game.local_preferences')
local Graphics={distances={0,10,14,20,28}}
local unbound=setmetatable({},{__mode='k'})
function Graphics.values(data)
    local view=Preferences.view(data)
    if view and view.graphics then return view.graphics end
    if not data then return {renderDistance=0}end
    unbound[data]=unbound[data]or{renderDistance=0};return unbound[data]
end
function Graphics.distance(data,mobile)
    local n=Graphics.values(data).renderDistance
    return n and n>=10 and n<=28 and n or(mobile and 10 or 14)
end
function Graphics.label(data,mobile)
    return (Graphics.values(data).renderDistance==0 and 'AUTO: 'or'')..Graphics.distance(data,mobile)..' SPACES'
end
function Graphics.adjust(data,delta,mobile)
    local values=Graphics.values(data);local index=1
    local current=Graphics.distance(data,mobile)
    for i,n in ipairs(Graphics.distances)do if current==n then index=i;break end end
    index=math.max(2,math.min(#Graphics.distances,index+delta));values.renderDistance=Graphics.distances[index]
end
function Graphics.automatic(data)Graphics.values(data).renderDistance=0 end
return Graphics
