local Definitions=require("game.outfit_catalog")
local Sprites=require("game.outfit_sprite_art")
local OutfitItemArt={}
function OutfitItemArt.has(name)
    return Definitions.materials[name]~=nil or Definitions.upgrades[name]~=nil
        or name=="sewing-kit" or name=="pocket-tool-roll"
end
-- Inventory, merchant, recipe and world views share the authored item sprites.
-- Quality uses an authored thimble badge over the matching recipe icon.
function OutfitItemArt.draw(name,rect)
    if not OutfitItemArt.has(name) then return false end
    return Sprites.draw(name,rect)
end
return OutfitItemArt
