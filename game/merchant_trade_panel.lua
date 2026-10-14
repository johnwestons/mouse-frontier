-- Shared merchant presentation; interaction and saving belong to its caller.
local UIStyle=require("game.ui_layout")
local MerchantTrade=require("game.merchant_trade")
local Util=require("game.util")
local Panel={}
function Panel.draw(c,source)
    local MerchantTrade=c.trade or MerchantTrade
    local runtime,ui,Catalog,colors=c.runtime,c.ui,c.catalog,c.colors
    local button,drawMenuFrame,textBox=c.button,c.drawMenuFrame,c.textBox
    local isWeapon=c.isWeapon
    local W,H=c.width or 960,c.height or 720
      love.graphics.setColor(0,0,0,.86); love.graphics.rectangle("fill",0,0,W,H)
      return UIStyle.scope("trade",{x=60,y=42,w=840,h=640},function()
      local merchant=source.relationshipId or source.merchant or runtime.tradeNPC or runtime.saveData.currentNPC
      local terms=MerchantTrade.terms(runtime.saveData,source)
      local availableBudget=MerchantTrade.availableBudget(runtime.saveData,source)
      do
          drawMenuFrame(60,42,840,640,1,1)
          love.graphics.setColor(colors.cream); textBox(source.title or Util.titleFromFile(merchant).."'S TRADING POST",85,59,790,45,1.2,"center")
          textBox("YOUR SCRAP "..runtime.saveData.scrap.." / MERCHANT BUDGET "..math.max(0,availableBudget),85,108,790,27,.9,"center")
          love.graphics.setColor(colors.brass); textBox(runtime.tradeMessage or (terms.tier.." terms / "..math.floor(terms.discount*100+.5).."% buying discount"),85,139,790,32,.82,"center")
          local stockIndices,occupied={},{}
          for index in pairs(source.stock or {}) do if type(index)=="number" and MerchantTrade.stockItem(source,index) then stockIndices[#stockIndices+1]=index end end
          table.sort(stockIndices)
          for index=1,(runtime.saveData.inventoryCapacity or 6) do
              local item=runtime.saveData.inventory[index]
              if item and not (Catalog.repairParts and Catalog.repairParts[item]) then occupied[#occupied+1]=index end
          end
          local buyPages=math.max(0,math.ceil(#stockIndices/3)-1)
          local sellPages=math.max(0,math.ceil(#occupied/3)-1)
          runtime.tradeBuyPage=math.max(0,math.min(buyPages,runtime.tradeBuyPage or 0))
          runtime.tradeSellPage=math.max(0,math.min(sellPages,runtime.tradeSellPage or 0))
          ui.tradeBuy,ui.tradeSell,ui.tradeGive={},{},{}
          textBox("FOR SALE",90,177,350,26,.95)
          textBox("YOUR ITEMS",490,177,375,26,.95)
          for row=0,2 do
              local y=210+row*116
              local index=stockIndices[runtime.tradeBuyPage*3+row+1]
              if index then
                  local name,entry=MerchantTrade.stockItem(source,index)
                  local price=MerchantTrade.buyPrice(runtime.saveData,Catalog,source,index)
                  local enabled,target=MerchantTrade.canBuy(runtime.saveData,Catalog,source,index)
                  enabled=enabled and not c.busy
                  ui.drawItem(name,{x=90,y=y,w=54,h=54})
                  love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(name)..((tonumber(entry and entry.quantity) or 1)>1 and (" x"..entry.quantity) or ""),154,y,290,43,.85)
                  ui.tradeBuy[index]=button(target=="train" and "SEND" or "BUY",154,y+49,130,56,enabled,.95)
                  ui.tradeBuy[index].enabled=enabled
                  love.graphics.setColor(colors.cream); textBox(price.." SCRAP",297,y+49,150,56,.9,"center")
              end
              local ownedIndex=occupied[runtime.tradeSellPage*3+row+1]
              local name=ownedIndex and runtime.saveData.inventory[ownedIndex]
              if name then
                  ui.drawItem(name,{x=490,y=y,w=54,h=54})
                  love.graphics.setColor(colors.cream); textBox(Util.titleFromFile(name),556,y,306,43,.85)
                  local price=MerchantTrade.sellPrice(runtime.saveData,Catalog,source,ownedIndex)
                  local gift=isWeapon(name) and source.allowGifts
                  ui.tradeSell[ownedIndex]=button("SELL +"..price,556,y+49,gift and 143 or 306,56,availableBudget>=price and not c.busy,.95)
                  ui.tradeSell[ownedIndex].enabled=availableBudget>=price and not c.busy
                  if gift then ui.tradeGive[ownedIndex]=button("GIVE",716,y+49,146,56,true,.95) end
              end
          end
          ui.tradeBuyPrev=button("<",90,559,65,52,runtime.tradeBuyPage>0)
          ui.tradeBuyNext=button(">",382,559,65,52,runtime.tradeBuyPage<buyPages)
          ui.tradePrev=button("<",490,559,65,52,runtime.tradeSellPage>0)
          ui.tradeNext=button(">",797,559,65,52,runtime.tradeSellPage<sellPages)
          ui.tradeBuyPrev.enabled=runtime.tradeBuyPage>0; ui.tradeBuyNext.enabled=runtime.tradeBuyPage<buyPages
          ui.tradePrev.enabled=runtime.tradeSellPage>0; ui.tradeNext.enabled=runtime.tradeSellPage<sellPages
          love.graphics.setColor(colors.cream)
          textBox((runtime.tradeBuyPage+1).." / "..(buyPages+1),170,559,196,52,.95,"center")
          textBox((runtime.tradeSellPage+1).." / "..(sellPages+1),570,559,212,52,.95,"center")
          ui.tradeClose=button("DONE TRADING",340,622,280,48,true,.95)
          return
      end
      end)
end
return Panel
