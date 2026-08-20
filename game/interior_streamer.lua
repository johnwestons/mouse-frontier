local InteriorStreamer={}
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
    local ok,image=pcall(self.loadImage,"assets/sprites/interiors/"..self.files[index])
    if ok then
        self.activeIndex=index
        self.activeImage=image
    end
    return self.activeImage
end

function InteriorStreamer:get(index)
    return self:activate(index)
end

return InteriorStreamer
