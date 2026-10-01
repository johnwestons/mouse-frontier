local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"inventory presenter requires "..name)
  if expected then assert(type(value)==expected,"inventory presenter "..name.." must be a "..expected) end
  return value
end
local UIStyle=require("game.ui_layout")

local function new(context)
  assert(type(context)=="table","inventory presenter requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local InventoryUI=required(context,"inventoryUI","table")
  local Inventory=required(context,"inventory","table")
  local Catalog=required(context,"catalog","table")
  local colors=required(context,"colors","table")
  local mobileEnabled=required(context,"mobileEnabled","function")
  local pointIn=required(context,"pointIn","function")
  local title=required(context,"title","function")
  local isWeapon=required(context,"isWeapon","function")
  local drawMenuFrame=required(context,"drawMenuFrame","function")
  local button=required(context,"button","function")
  local pointer=required(context,"pointer","function")
  local value=required(context,"value","function")
  local move=required(context,"move","function")
  local quickTransfer=required(context,"quickTransfer","function")
  local collectAmmo=required(context,"collectAmmo","function")
  local drop=required(context,"drop","function")
  local consume=required(context,"consume","function")
  local consumeBattle=required(context,"consumeBattle","function")
  local lastClick,lastClickTime=nil,0

  local setters={
      draggedSlot=function(nextValue) runtime.draggedSlot=nextValue end,
      inventoryDragActive=function(nextValue) runtime.inventoryDragActive=nextValue end,
      giftOpen=function(nextValue) runtime.giftOpen=nextValue end,
      giftSlot=function(nextValue) runtime.giftSlot=nextValue end,
      inventoryOpen=function(nextValue) runtime.inventoryOpen=nextValue end,
      lastClick=function(nextValue) lastClick=nextValue end,
      lastClickTime=function(nextValue) lastClickTime=nextValue end,
  }

  local function setState(name,nextValue)
      local setter=setters[name]
      assert(setter,"inventory presenter cannot set "..tostring(name))
      setter(nextValue)
  end

  local function currentContext()
      local battleMode=runtime.state=="battle"
      return {
          data=runtime.saveData,
          activeChest=runtime.activeChest,
          chestOpen=runtime.chestOpen,
          inventoryOpen=runtime.inventoryOpen,
          draggedSlot=runtime.draggedSlot,
          inventoryDragActive=runtime.inventoryDragActive,
          giftOpen=runtime.giftOpen,
          giftNPC=runtime.giftNPC,
          giftSlot=runtime.giftSlot,
          lastClick=lastClick,
          lastClickTime=lastClickTime,
          nearNPC=runtime.nearNPC,
          nearPassenger=runtime.nearPassenger,
          ui=ui,
          Inventory=Inventory,
          Catalog=Catalog,
          colors=colors,
          mobileEnabled=mobileEnabled(),
          pointIn=pointIn,
          title=title,
          isWeapon=isWeapon,
          drawMenuFrame=drawMenuFrame,
          button=button,
          pointer=function()
              local x,y=pointer()
              return UIStyle.inversePoint(x,y,"inventory",{x=25,y=35,w=910,h=660})
          end,
          value=value,
          set=setState,
          battleMode=battleMode,
          move=move,
          quickTransfer=quickTransfer,
          collectAmmo=collectAmmo,
          drop=battleMode and function() return false end or drop,
          consume=battleMode and consumeBattle or consume,
      }
  end

  ui.keyboardInventoryValue=function(slot) return value(slot) end
  ui.keyboardInventoryMove=function(from,to) return currentContext().move(from,to) end
  ui.keyboardInventoryConsume=function() return currentContext().consume() end
  ui.keyboardInventoryDrop=function(slot) return currentContext().drop(slot) end

  local function drawInventory()
      return UIStyle.scope("inventory",{x=25,y=35,w=910,h=660},function()
          return InventoryUI.draw(currentContext())
      end)
  end

  local function drawChestInventory()
      return UIStyle.scope("inventory",{x=25,y=35,w=910,h=660},function()
          return InventoryUI.drawChest(currentContext())
      end)
  end

  local function drawItem(name,rect)
      return InventoryUI.drawItem(currentContext(),name,rect)
  end

  local function handleClick(x,y,offerGift)
      x,y=UIStyle.inversePoint(x,y,"inventory",{x=25,y=35,w=910,h=660})
      local inventoryContext=currentContext()
      inventoryContext.offerGift=offerGift
      return InventoryUI.handleClick(inventoryContext,x,y)
  end

  local function handleRelease(x,y,buttonCode)
      x,y=UIStyle.inversePoint(x,y,"inventory",{x=25,y=35,w=910,h=660})
      return InventoryUI.handleRelease(currentContext(),x,y,buttonCode)
  end

  -- Existing renderers consume these focused drawing callbacks through the UI
  -- table; the full mutable inventory context stays private to this service.
  ui.drawInventory=drawInventory
  ui.drawChestInventory=drawChestInventory
  ui.drawItem=drawItem

  return {
      drawInventory=drawInventory,
      drawChestInventory=drawChestInventory,
      drawItem=drawItem,
      handleClick=handleClick,
      handleRelease=handleRelease,
  }
end

return {new=new}
