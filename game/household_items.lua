local HouseholdItems = {}

-- Small home goods are kept in their own loot pool so they appear in house
-- storage without diluting food, medicine, or combat rewards elsewhere.
HouseholdItems.definitions = {
    ["wooden-spoon"] = {rarity="common", category="kitchen"},
    ["enamel-cup"] = {rarity="common", category="kitchen"},
    ["tin-plate"] = {rarity="common", category="kitchen"},
    ["cutlery-roll"] = {rarity="common", category="kitchen"},
    ["field-guide-book"] = {rarity="common", category="books"},
    ["worn-novel"] = {rarity="common", category="books"},
    ["thread-spool"] = {rarity="common", category="sewing"},
    ["button-tin"] = {rarity="common", category="sewing"},
    ["old-magazine"] = {rarity="common", category="reading"},
    ["folded-newspaper"] = {rarity="common", category="reading"},
    ["sewing-kit"] = {rarity="uncommon", category="sewing"},
    ["pocket-tool-roll"] = {rarity="uncommon", category="tools"},
    ["brass-flashlight"] = {rarity="uncommon", category="electronics"},
    ["ceramic-owl-figurine"] = {rarity="uncommon", category="keepsakes"},
    ["wooden-mouse-figurine"] = {rarity="uncommon", category="keepsakes"},
    ["handheld-radio"] = {rarity="rare", category="electronics"},
}

HouseholdItems.pools = {
    common={
        "wooden-spoon", "enamel-cup", "tin-plate", "cutlery-roll",
        "field-guide-book", "worn-novel", "thread-spool", "button-tin",
        "old-magazine", "folded-newspaper",
    },
    uncommon={
        "sewing-kit", "pocket-tool-roll", "brass-flashlight",
        "ceramic-owl-figurine", "wooden-mouse-figurine",
    },
    rare={"handheld-radio"},
}

function HouseholdItems.roll(rarity,pools)
    pools=pools or HouseholdItems.pools
    local pool=pools[rarity]
    if not pool or #pool==0 then pool=pools.common end
    if not pool or #pool==0 then return nil end
    return pool[love.math.random(1,#pool)]
end

return HouseholdItems
