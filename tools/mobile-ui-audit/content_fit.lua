-- Exercise real renderers and their current boxes against all authored text,
-- including long branches that a representative screenshot will not encounter.
local Typography=require("game.typography")
local Events=require("game.events")
local EventUI=require("game.event_ui")
local Conversations=require("game.npc_conversations")

local function run(context)
    local Graphics,game,ui,record=context.graphics,context.game,context.ui,context.record
    local data=game.saveData
    local saved={conversations=data.conversations,currentNPC=data.currentNPC,textSize=data.accessibility.textSize,
        dialogue=game.dialogue,helpDialogue=game.helpDialogue}
    local originalDraw=Typography.drawText
    local failures,eventCount,choiceCount,dialogueCount,responseCount=0,0,0,0,0
    local fixture="event"
    Typography.drawText=function(graphics,text,x,y,width,height,options)
        options=options or {}
        local scale,measuredHeight,lines,fits=Typography.fitText(graphics,text,width,height,options.scale,options.minScale,options)
        if not fits then
            failures=failures+1
            record(string.format("CONTENT OVERFLOW %s [%s] box=%.0fx%.0f scale=%.3f height=%.1f lines=%d",
                fixture,tostring(text):gsub("\n"," / "),width,height,scale,measuredHeight,lines))
        end
        return scale,measuredHeight,lines,fits
    end
    Graphics.push("all")
    local ok,message=xpcall(function()
        local function noop() end
        for _,events in pairs(Events.definitions) do
            for _,event in ipairs(events) do
                fixture="event "..event.id; eventCount=eventCount+1; choiceCount=choiceCount+#event.choices
                EventUI.draw(event,{},noop,noop,{brass={1,1,1},cream={1,1,1}},{story=10,mystery=5},function() return true end)
            end
        end
        data.currentNPC="ferret-medic.png"
        for _,entry in ipairs(Conversations.content) do
            local request={id=entry.id,npc=data.currentNPC,location=data.location}
            data.conversations={assignments={[tostring(data.location)]=request},completed={},seen={}}
            for _,textSize in ipairs({1,3}) do
                data.accessibility.textSize=textSize
                fixture="authored question "..entry.id.." text="..textSize
                game.helpDialogue=assert(Conversations.begin(data,data.currentNPC))
                game.dialogue={speaker="Ferret Medic",text=game.helpDialogue.text,timer=120}
                ui.drawDialogue()
                assert(#ui.helpDialogueChoices==3,"all three authored choices must remain visible")
                for index,choice in ipairs(ui.helpDialogueChoices) do
                    assert(choice.y+choice.h<=ui.helpDialoguePause.y,"dialogue choice must not touch the pause control")
                    if index>1 then
                        local previous=ui.helpDialogueChoices[index-1]
                        assert(choice.y>=previous.y+previous.h,"dialogue choices must not overlap")
                    end
                end
                dialogueCount=dialogueCount+1
                game.helpDialogue=nil
                for index,answer in ipairs(entry.choices) do
                    fixture="authored response "..entry.id.."/"..index.." text="..textSize
                    game.dialogue={speaker="Ferret Medic",text=answer.response,authored=true,timer=120}
                    ui.drawDialogue()
                    responseCount=responseCount+1
                end
            end
        end
    end,debug.traceback)
    Graphics.pop()
    Typography.drawText=originalDraw
    data.conversations=saved.conversations; data.currentNPC=saved.currentNPC
    data.accessibility.textSize=saved.textSize
    game.dialogue=saved.dialogue; game.helpDialogue=saved.helpDialogue
    if not ok then error(message,0) end
    assert(failures==0,"authored text exceeds readable boxes in "..failures.." cases")
    record(string.format("PASS content fit: %d events / %d choices, %d authored question layouts, %d authored response layouts",
        eventCount,choiceCount,dialogueCount,responseCount))
end

return {run=run}
