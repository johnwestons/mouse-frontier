-- Detached deterministic campaigns; no player save directory is accessed.
local Schema=require("game.save_schema")
local Fixtures={}

function Fixtures.campaign(stop,overrides)
    local legacy={version=37,character="scout-frog.png",location=stop or 1,
        health=17,maxHealth=23,stats={level=2,xp=4,nextXP=18},
        inventory={[1]="orange-rose-vase",[4]="cowboy-hat"},
        equipment={"frontier-short-sword","trail-slingshot"},ammo={rocks=8},
        weaponDurability={["frontier-short-sword"]=67},weaponProficiency={firearms=3},
        playerX=200,playerY=250,resources={food=10,water=10,coal=10,oil=10},scrap=40,
        conversations={assignments={},completed={example={answer=2,xp=5}},seen={example=true}},
    }
    for key,value in pairs(overrides or {}) do legacy[key]=value end
    return assert(Schema.migrate(legacy))
end

function Fixtures.enroll(data)
    return require("game.coop_players").enroll(data,"host","cook-mouse.png",
        {characterTrait=function() return {name="cook",maxHealth=2} end},
        {["cook-mouse.png"]=true})
end

function Fixtures.filesystem()
    local files={}
    return {
        getInfo=function(path) return files[path] and {type="file"} end,
        createDirectory=function() return true end,
        write=function(path,value) files[path]=value; return true end,
        read=function(path) return files[path] end,
        load=function(path) return loadstring(files[path] or "",path) end,
        remove=function(path) files[path]=nil; return true end,
    },files
end

return Fixtures
