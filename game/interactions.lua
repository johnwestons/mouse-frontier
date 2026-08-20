local Interactions = {}

-- Choose one action from the objects already confirmed to be in player range.
-- Hovered objects receive a strong priority; otherwise the action nearest the
-- cursor wins, with player distance used only to break close ties.
function Interactions.select(candidates,cursorX,cursorY,player)
    local best,bestScore
    for _,candidate in ipairs(candidates or {}) do
        local dx,dy=cursorX-candidate.x,cursorY-candidate.y
        local cursorDistance=math.sqrt(dx*dx+dy*dy)
        local pdx,pdy=player.x-candidate.x,player.y-candidate.y
        local playerDistance=math.sqrt(pdx*pdx+pdy*pdy)
        local hovered=cursorDistance<=(candidate.hoverRadius or 42)
        local score=cursorDistance+playerDistance*.001-(hovered and 10000 or 0)
        if not bestScore or score<bestScore then best,bestScore=candidate,score end
    end
    return best
end

return Interactions
