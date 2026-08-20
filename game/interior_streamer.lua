local InteriorStreamer={}
local AssetDiagnostics=require("game.asset_diagnostics")
InteriorStreamer.__index=InteriorStreamer

function InteriorStreamer.new(files,loadImage)
    return setmetatable({
        files=files or {},
        loadImage=loadImage or function(path) return love.graphics.newImage(path) end,
        activeIndex=nil,
        activeImage=nil,
    },InteriorStreamer)
end

function InteriorStreamer:release()
    if self.activeImage and self.activeImage.release then
        pcall(self.activeImage.release,self.activeImage)
    end
    self.activeImage=nil
    self.activeIndex=nil
end

function InteriorStreamer:activate(index)
    index=tonumber(index)
    if not index or not self.files[index] then
        self:release()
        return nil
    end
    if self.activeIndex==index and self.activeImage then return self.activeImage end
    self:release()
    local path="assets/sprites/interiors/"..self.files[index]
    local ok,image=pcall(self.loadImage,path)
    if ok and image then
        self.activeIndex=index
        self.activeImage=image
    end
    if not ok or not image then AssetDiagnostics.record(path,"interior scenery",ok and "no image returned" or image) end
    return self.activeImage
end

function InteriorStreamer:get(index)
    return self:activate(index)
end

return InteriorStreamer
