-- A received game view is never a save, even if a caller later fills in save
-- metadata. Keep ownership out of the transmitted payload and serialized data.
local Ownership={}
local replicas=setmetatable({},{__mode='k'})
function Ownership.mark(value) replicas[value]=true; return value end
function Ownership.isReplica(value) return replicas[value]==true end
return Ownership
