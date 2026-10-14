-- Tool motions need several inputs per second. Material allocation and every
-- other discrete action retain the ordinary budget; all buckets are bounded.
local Rate={}
local motions={point=true,adjust=true,pullStart=true,pullRelease=true,renew=true,suspend=true}
local guns={['gun.fire']=true,['gun.reload']=true,['gun.cover']=true,['gun.select']=true,['gun.mode']=true,
    ['range.fire']=true,['range.reload']=true}
function Rate.allow(link,message,now)
    local tool=message.command=='outfit.craft' and type(message.args)=='table' and motions[message.args.action]
    local aid=message.command=='firstAid.step' or message.command=='lastStand.aid' and type(message.args)=='table'
        and ({press=true,move=true,release=true,choose=true,tick=true,pause=true})[message.args.action]
    local field=message.command=='roaming.attack'
    local gun=guns[message.command]
    local key=aid and 'aidTokens' or tool and 'sewingTokens' or field and 'fieldTokens' or gun and 'gunTokens' or 'commandTokens'
    local timeKey=aid and 'aidTokenTime' or tool and 'sewingTokenTime' or field and 'fieldTokenTime' or gun and 'gunTokenTime' or 'commandTokenTime'
    -- Fastest authored automatic fire is ten shots/s. Gameplay validation
    -- still enforces the selected gun's cooldown, exact ownership and cost.
    local rate=gun and 12 or (tool or aid) and 6 or field and 3 or 2
    link[key]=math.min(4,(link[key] or 4)+math.max(0,now-(link[timeKey] or now))*rate)
    link[timeKey]=now
    if link[key]<1 then return false end
    link[key]=link[key]-1; return true
end
return Rate
