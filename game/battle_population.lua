-- Populate ordinary crossings once. Boss, scripted event/expedition rosters and
-- explicit encounter stat overrides retain their assigned enemies.
local Population={COUNTS={easy=12,medium=18,hard=24}}
function Population.prepare(encounter,catalog,random,normalMaxHP)
    if encounter.source=='expedition'or encounter.boss or encounter.eventBattle or encounter.enemyStates
        or encounter.maxHP and encounter.maxHP~=normalMaxHP and not encounter.population then return false end
    local files=encounter.mobFiles or {};local target=Population.COUNTS[encounter.tier]or 12
    local pool=catalog.mobTiers[encounter.tier]or files
    if #pool==0 or #files==0 then return false end
    -- Reuse at most three sprite families per crossing. More combatants must
    -- not require a separate large animation atlas for every extra enemy.
    local types,known={},{}
    for _,file in ipairs(files)do if not known[file]then types[#types+1]=file;known[file]=true end end
    while #types<math.min(3,#pool)do
        local start=random(1,#pool);local added=false
        for offset=0,#pool-1 do
            local file=pool[(start-1+offset)%#pool+1]
            if not known[file]then types[#types+1]=file;known[file]=true;added=true;break end
        end
        if not added then break end
    end
    for i=#files+1,target do files[i]=types[(i-1)%#types+1]end
    encounter.mobFiles=files;encounter.population=1
    return true
end
return Population
