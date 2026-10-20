-- Renderers claim ADS for the current frame. The outer application restores
-- the pointer whenever no sight view is drawn or a menu takes control.
local Cursor={}
local aiming=false
local owned=false
local previous=true

function Cursor.restore()
    local mouse=love and love.mouse
    if owned and mouse and mouse.setVisible then mouse.setVisible(previous) end
    owned=false
end

function Cursor.beginFrame() aiming=false end
function Cursor.sights(active) if active then aiming=true end end
function Cursor.endFrame(menuOpen)
    local mouse=love and love.mouse
    if mouse and mouse.setVisible then
        if aiming and not menuOpen then
            if not owned then previous=not mouse.isVisible or mouse.isVisible();owned=true end
            if not mouse.isVisible or mouse.isVisible() then mouse.setVisible(false) end
        elseif owned then Cursor.restore() end
    end
end

return Cursor
