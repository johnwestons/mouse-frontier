local Crafting=require("game.outfit_crafting")
local Definitions=require("game.outfit_catalog")
local Items=require("game.item_instances")
local Save=require("game.save")
local Viewport=require("game.viewport")
local Smoke={}

function Smoke.steps(context)
    return {{name="sewing_authority_save_resume",action=function()
        local game,ui=context.runtime,context.ui
        local previous,previousSlot=game.saveData,game.selectedSlot
        local randomState=love.math.getRandomState()
        local mobile=context.mobileEnabled()
        local touch=0
        local function point(x,y)
            local ox,oy,sx,sy=Viewport.transform(960,720)
            return ox+x*sx,oy+y*sy
        end
        local function tap(x,y)
            touch=touch+1; local id="smoke-sewing-"..touch
            x,y=point(x,y)
            love.touchpressed(id,x,y); love.touchreleased(id,x,y)
        end
        local function space()
            love.keypressed("space",nil,false); love.keyreleased("space")
        end
        local ok,result=xpcall(function()
            game.selectedSlot=99
            Save.remove(99)
            assert(context.enterGame(context.newSave(context.character)))
            local data=game.saveData
            local recipe=Definitions.recipes[1]
            local slots={}; for index in pairs(data.inventory) do slots[#slots+1]=index end
            for _,index in ipairs(slots) do Items.write(data,nil,{kind="inventory",index=index},nil) end
            local index=1
            for _,cost in ipairs(recipe.materials) do for n=1,cost.count do
                Items.write(data,nil,{kind="inventory",index=index},cost.id); index=index+1
            end end
            assert(ui.openOutfitWorkbench(),"sewing bench did not open")
            context.draw()
            if mobile then tap(480,610) else space() end
            local project=assert(Crafting.project(data),"real sewing input did not start a project")
            assert(project.ownerPlayerId=="host" and not next(data.inventory),"materials/owner not committed by authority")
            local stage=assert(Crafting.stage(data))
            context.draw()
            if mobile then tap(285+stage.currentPoint.x*390,221+stage.currentPoint.y*260) else space() end
            assert(project.correctActions==1,"real sewing point did not advance")
            love.focus(false)
            assert(not game.outfitCraftingOpen,"focus loss retained the sewing lock")
            love.focus(true)
            local restored=assert(Save.read(99))
            assert(restored.outfitCrafting.project.correctActions==1 and restored.outfitCrafting.project.ownerPlayerId=="host")
            assert(context.enterGame(restored)); data=game.saveData
            assert(ui.openOutfitWorkbench(),"saved sewing project did not reopen")
            local count=0
            while not Crafting.project(data).complete do
                count=count+1; assert(count<1000,"sewing project did not complete")
                stage=Crafting.stage(data); context.draw()
                if stage.kind=="point" then
                    if mobile then tap(285+stage.currentPoint.x*390,221+stage.currentPoint.y*260) else space() end
                else
                    local x,y=point(400,610)
                    if mobile then love.touchpressed("smoke-sewing-hold",x,y) else love.keypressed("space",nil,false) end
                    local duration=(stage.targetRange.min+stage.targetRange.max)/2/.24
                    love.timer.sleep(duration)
                    context.update(duration)
                    if mobile then love.touchreleased("smoke-sewing-hold",x,y) else love.keyreleased("space") end
                end
            end
            assert(Crafting.project(data).quality=="masterwork","host-scored sewing diverged from visible input")
            context.draw()
            if mobile then tap(480,610) else space() end
            assert(not Crafting.project(data),"collect input did not finish the project")
            local item=assert(Items.get(data,nil,{kind="inventory",index=1}))
            assert(item.name==recipe.outputIds.masterwork)
            local saved=assert(Save.read(99))
            assert(saved.itemSlots.inventory[1].id==item.id and not saved.outfitCrafting.project)
            ui.suspendOutfitWorkbench()
            return {ok=true,owner="host",quality="masterwork",itemId=item.id,
                checkpointRestored=true,input=mobile and "touch" or "keyboard",steps=count}
        end,debug.traceback)
        if game.outfitCraftingOpen then ui.suspendOutfitWorkbench() end
        game.selectedSlot=nil
        assert(context.enterGame(previous))
        game.selectedSlot=previousSlot
        love.math.setRandomState(randomState)
        if not ok then error(result) end
        return result
    end,check=function(_,_,_,result) return result.ok and result.checkpointRestored end}}
end

return Smoke
