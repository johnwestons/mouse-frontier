local Manifest=require("game.first_person_weapon_manifest")

local Views={}

function Views.new(loadImage,fileExists)
    assert(type(loadImage)=="function","first-person weapon views require an image loader")
    local valid,issues=Manifest.validate()
    assert(valid,"invalid first-person weapon manifest: "..table.concat(issues,"; "))

    local cache={weapon=nil,images={},unavailable={}}

    function cache:release()
        for _,image in pairs(self.images) do
            if image and image.release then pcall(image.release,image) end
        end
        self.images={}
        self.unavailable={}
        self.weapon=nil
    end

    function cache:get(weapon,state)
        if self.weapon~=weapon then
            self:release()
            self.weapon=weapon
        end
        local entry=Manifest.weapons[weapon]
        if not entry then return nil end
        local file=entry.views[state or "hip"]
        if not file then return nil end
        if self.unavailable[file] then return nil end
        if self.images[file] then return self.images[file] end
        if fileExists and not fileExists(file) then self.unavailable[file]=true; return nil end
        local image=loadImage(file)
        if image then
            if image.setFilter then pcall(image.setFilter,image,"nearest","nearest") end
            self.images[file]=image
        else
            self.unavailable[file]=true
        end
        return image
    end

    function cache:anchor(weapon)
        return Manifest.anchorFor(weapon)
    end

    function cache:states(weapon)
        local entry=Manifest.weapons[weapon]
        return entry and entry.views or nil
    end

    return cache
end

return Views
