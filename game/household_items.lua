local HouseholdItems = {}

-- Small home goods are kept in their own loot pool so they appear in house
-- storage without diluting food, medicine, or combat rewards elsewhere.
HouseholdItems.definitions = {
    ["wooden-spoon"] = {rarity="common", category="kitchen", worldScale=.82, description="A worn wooden spoon from an old kitchen drawer."},
    ["enamel-cup"] = {rarity="common", category="kitchen", worldScale=.62, description="A chipped enamel cup with a sturdy metal rim."},
    ["tin-plate"] = {rarity="common", category="kitchen", worldScale=.70, description="A lightweight tin plate marked by years of use."},
    ["cutlery-roll"] = {rarity="common", category="kitchen", worldScale=.62, description="A cloth wrap holding a few mismatched utensils."},
    ["field-guide-book"] = {rarity="common", category="books", worldScale=.78, description="A weathered field guide with notes tucked between its pages."},
    ["worn-novel"] = {rarity="common", category="books", worldScale=.72, description="A dog-eared paperback with a creased spine and softened pages."},
    ["thread-spool"] = {rarity="common", category="sewing", worldScale=.34, description="A small spool of sturdy thread, wound unevenly."},
    ["button-tin"] = {rarity="common", category="sewing", worldScale=.40, description="A dented tin holding a mixed handful of old buttons."},
    ["old-magazine"] = {rarity="common", category="reading", worldScale=.75, description="An old illustrated magazine with curled, yellowed pages."},
    ["folded-newspaper"] = {rarity="common", category="reading", worldScale=.74, description="A folded newspaper, faded and brittle at the creases."},
    ["sewing-kit"] = {rarity="uncommon", category="sewing", worldScale=.58, description="A compact sewing kit with thread, needles, and spare fasteners."},
    ["pocket-tool-roll"] = {rarity="uncommon", category="tools", worldScale=.74, description="A rolled canvas sleeve packed with small hand tools."},
    ["brass-flashlight"] = {rarity="uncommon", category="electronics", worldScale=.62, description="A scuffed brass flashlight with a cloudy lens."},
    ["ceramic-owl-figurine"] = {rarity="uncommon", category="keepsakes", worldScale=.42, description="A small glazed owl figurine with a few chipped edges."},
    ["wooden-mouse-figurine"] = {rarity="uncommon", category="keepsakes", worldScale=.38, description="A hand-carved wooden mouse with a smooth, worn finish."},
    ["handheld-radio"] = {rarity="rare", category="electronics", worldScale=.58, description="A compact handheld radio with a scratched case and short antenna."},
    ["brass-compass"] = {rarity="uncommon", category="navigation", worldScale=.60, description="A worn brass compass with a cloudy face and a needle that still moves."},
    ["pocket-watch"] = {rarity="uncommon", category="keepsakes", worldScale=.54, description="A tarnished pocket watch with a cracked crystal and short chain."},
    ["map-case"] = {rarity="common", category="travel", worldScale=.68, description="A folded route map tucked into a weathered leather sleeve."},
    ["matchbox"] = {rarity="common", category="supplies", worldScale=.44, description="A worn matchbox holding a few dry matches."},
    ["rail-token"] = {rarity="common", category="keepsakes", worldScale=.32, description="A tarnished brass rail token, worn smooth along its edges."},
    -- These props already appear in the starter supply crate; keep them in the
    -- same metadata table so their dropped size and inventory descriptions work.
    ["pickaxe"] = {rarity="common", category="tools", worldScale=.86, description="A sturdy pickaxe with a worn wooden handle and a chipped steel head."},
    ["potted-sprout"] = {rarity="common", category="plants", worldScale=.74, description="A young green sprout growing from a small reused pot."},
    ["flower-pot"] = {rarity="common", category="plants", worldScale=.78, description="A small flower growing in a scuffed clay pot."},
    ["potted-flowers"] = {rarity="common", category="plants", worldScale=.92, description="A bundle of purple flowers in a patched container."},
    ["coal-bucket"] = {rarity="common", category="fuel", worldScale=.72, description="A small bucket of coal for feeding the train's firebox."},
}

HouseholdItems.pools = {
    common={
        "wooden-spoon", "enamel-cup", "tin-plate", "cutlery-roll",
        "field-guide-book", "worn-novel", "thread-spool", "button-tin",
        "old-magazine", "folded-newspaper", "map-case", "matchbox", "rail-token",
    },
    uncommon={
        "sewing-kit", "pocket-tool-roll", "brass-flashlight",
        "ceramic-owl-figurine", "wooden-mouse-figurine", "brass-compass", "pocket-watch",
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
