local Entities=require("game.coop_entities")
local Runtime={}
function Runtime.install(context)
    local runtime,ui,commands=context.runtime,context.ui,context.commands
    local lease,entityId,campaign,renewAt
    local function release()
        if lease and campaign==runtime.saveData then commands.submit("activity.release",{leaseId=lease}) end
        lease=nil; entityId=nil; campaign=nil; renewAt=nil
        runtime.editedItem=nil; runtime.editDragging=false; ui.editSliderDrag=nil
    end
    local function current()
        if not lease then return nil end
        if campaign~=runtime.saveData or runtime.scene~="train" or runtime.state~="game" or not runtime.editMode then release(); return nil end
        local item,entry=Entities.find(campaign,entityId)
        if not item or entry.kind~="drop" or item.scene~="train" or (item.carIndex or 1)~=campaign.activeCar then release(); return nil end
        runtime.editedItem=entry.key
        return item
    end
    local function failure(reason)
        ui.decorationMessage=reason=="activity_busy" and "This object is being edited. Try again when it is free."
            or reason=="inventory_full" and "Make space in your backpack before collecting this object."
            or reason=="container_not_empty" and "Empty this container before collecting it."
            or reason=="permanent" and "This stays aboard the train."
            or "Edit unavailable. Select the object again to continue."
        return false
    end
    ui.closeDecoration=release
    ui.editedDecoration=current
    ui.selectDecoration=function(index)
        local selected=index and runtime.saveData and runtime.saveData.droppedItems[index]
        if selected and selected.entityId==entityId and current() then return true end
        release(); ui.decorationMessage=nil
        if not selected then return false end
        local reply=commands.submit("decoration.acquire",{entityId=commands.identify(selected)})
        if not reply.ok then return failure(reply.reason) end
        lease=reply.result.leaseId; entityId=reply.result.entityId; campaign=runtime.saveData
        renewAt=(runtime.animationClock or 0)+10
        return current()~=nil
    end
    ui.placeDecoration=function(item,values)
        if not current() or item.entityId~=entityId then return failure("stale_selection") end
        local reply=commands.submit("decoration.place",{leaseId=lease,values=values})
        if not reply.ok then release(); return failure(reply.reason) end
        renewAt=(runtime.animationClock or 0)+10; ui.decorationMessage=nil
        return true
    end
    ui.collectDecoration=function()
        if not current() then return false end
        local reply=commands.submit("decoration.collect",{leaseId=lease})
        if not reply.ok then return failure(reply.reason) end
        release(); ui.decorationMessage=nil
        return true
    end
    ui.updateDecoration=function()
        local item=current()
        if item and (runtime.animationClock or 0)>=renewAt then ui.placeDecoration(item,{}) end
    end
end
return Runtime
