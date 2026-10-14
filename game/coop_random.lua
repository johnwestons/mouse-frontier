-- Campaign RNG advances on the detached transaction. Rejection/rollback does
-- not consume a reward roll from the live campaign or LÖVE's global stream.
local Random={MAX=2147483647}
function Random.valid(value)
    return type(value)=="number" and value==math.floor(value) and value>=1 and value<Random.MAX
end
function Random.generator(data,seed)
    assert(Random.valid(seed),"invalid host random seed")
    data.coop.randomState=data.coop.randomState or seed
    assert(Random.valid(data.coop.randomState),"invalid campaign random state")
    return function()
        data.coop.randomState=(data.coop.randomState*16807)%Random.MAX
        return (data.coop.randomState-1)/(Random.MAX-1)
    end
end
-- Domain generators accept a [0,1) stream; legacy callers retain LÖVE's
-- usual float/integer overload without changing the global random source.
function Random.range(rng)
    return function(low,high)
        if not rng then
            if low==nil then return love.math.random() end
            if high==nil then return love.math.random(low) end
            return love.math.random(low,high)
        end
        local value=rng()
        assert(type(value)=="number" and value>=0 and value<1,"invalid random sample")
        if low==nil then return value end
        if high==nil then high=low; low=1 end
        return low+math.floor(value*(high-low+1))
    end
end
return Random
