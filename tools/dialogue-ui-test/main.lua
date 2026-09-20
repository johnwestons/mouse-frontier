local runtime,ui,mobile,context
function love.load()
    local ok,err=xpcall(function()
        require('game.typography').install(love.graphics)
        runtime={saveData={resources={food=0,water=0},location=1,accessibility={textSize=1}}}
        ui={}; context={}
        local source=love.filesystem.read('game/screen_ui.lua')
        for name,kind in source:gmatch('required%(context,%s*"([^"]+)",%s*"([^"]+)"%)') do
            context[name]=kind=='table' and {} or kind=='number' and 0 or function() end
        end
        context.runtime=runtime; context.ui=ui; context.width=960; context.height=720
        context.colors=require('game.config').colors
        context.mobileEnabled=function() return mobile end
        require('game.screen_ui').new(context)
        local C=require('game.npc_conversations')
        local canvas=love.graphics.newCanvas(960,720)
        local checks=0
        for _,isMobile in ipairs({false,true}) do
            mobile=isMobile
            for size=1,3 do
                runtime.saveData.accessibility.textSize=size
                for _,entry in ipairs(C.content) do
                    local request={id=entry.id,location=1,npc='resident'}
                    C.ensure(runtime.saveData).assignments['1']=request
                    runtime.helpDialogue=C.view(runtime.saveData,request)
                    runtime.dialogue={text=entry.question,speaker='Resident',timer=120}
                    love.graphics.setCanvas(canvas); love.graphics.clear(.05,.035,.025,1)
                    ui.drawDialogue()
                    for _,choice in ipairs(ui.helpDialogueChoices) do
                        assert(choice.textFits,entry.id..' clipped mobile='..tostring(mobile)..' size='..size)
                        assert(choice.y+choice.h<ui.helpDialoguePause.y,'buttons overlap')
                    end
                    love.graphics.setCanvas()
                    if entry.id=='food' and size==3 then
                        local image=canvas:newImageData()
                        image:encode('png',mobile and 'mobile.png' or 'desktop.png')
                        image:release()
                    end
                    checks=checks+1
                end
            end
        end
        print('DIALOGUE_UI_OK layouts='..checks..' screenshots='..love.filesystem.getSaveDirectory())
    end,debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
