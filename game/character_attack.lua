-- One action decision shared by battle, local field attacks and co-op cues.
local Attack={}
function Attack.action(weapon,combat)
    if combat and combat.kind=='ranged' then return 'ranged' end
    if not weapon or weapon=='scratch' or weapon=='mob-claw' then return 'melee' end
    return 'swing'
end
function Attack.heldItem(weapon)
    if weapon and weapon~='scratch' and weapon~='mob-claw' then return weapon end
end
return Attack
