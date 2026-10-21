-- Shared Last Stand effects are resolved against the live host draft. The
-- handlers still validate the exact phase, occupancy, weapon and cooldown.
-- Personal inventory revisions are always strict, as are all other commands.
local Conflicts={}
local guns={['gun.fire']=true,['gun.reload']=true,['gun.cover']=true,['gun.mode']=true,
    ['gun.select']=true,['lastStand.supply']=true}
function Conflicts.accepts(command,args,scope,expected,current)
    if type(expected)~='number' or expected<0 or expected~=math.floor(expected) then return false end
    if expected==current then return true end
    if expected>current or type(args)~='table' then return false end
    if guns[command] and args.mode=='lastStand' then
        return scope=='world:scene' or scope=='resources' or scope=='world:maintenance' or scope=='story:events'
            or type(args.encounterId)=='string' and scope=='entity:'..args.encounterId
    end
    if command=='lastStand.position' and type(args.questId)=='string' then
        return scope=='world:scene' or scope=='entity:'..args.questId
            or scope=='activity:lastStand:'..args.questId..':positions'
    end
    return false
end
return Conflicts
