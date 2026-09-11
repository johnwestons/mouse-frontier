-- Exercise real renderers and their current boxes against all authored text,
-- including long branches that a representative screenshot will not encounter.
local Typography=require("game.typography")
local Events=require("game.events")
local EventUI=require("game.event_ui")
local Quests=require("game.help_dialogue_quests")
local HelpQuest=require("game.help_quest_session")

local function run(context)
    local Graphics,game,ui,record=context.graphics,context.game,context.ui,context.record
    local data=game.saveData
    local saved={sessions=data.helpQuestSessions,active=data.activeHelpQuestId,textSize=data.accessibility.textSize,
        mapScroll=game.mapScroll,dialogue=game.dialogue,helpDialogue=game.helpDialogue}
    local originalDraw=Typography.drawText
    local failures,eventCount,choiceCount,mapCount,dialogueCount=0,0,0,0,0
    local fixture,hintBox="event",nil
    Typography.drawText=function(graphics,text,x,y,width,height,options)
        options=options or {}
        local scale,measuredHeight,lines,fits=Typography.fitText(graphics,text,width,height,options.scale,options.minScale,options)
        if text=="Tap a response" then hintBox={x=x,y=y,w=width,h=height} end
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
        data.helpQuestSessions={}
        for index=1,2 do
            local other=HelpQuest.ensure(data,{id="fit-other-"..index,source="fit",kind="dialogue-help",mode="dialogue",
                location=6,npc="ferret-medic.png",title="Other journey",objective="Return to the critter."})
            HelpQuest.accept(data,other.id)
        end
        for id,definition in pairs(Quests.definitions) do
            for nodeName,node in pairs(definition.nodes) do
                local active=HelpQuest.ensure(data,{id="fit-active",source="fit",kind="dialogue-help",mode="dialogue",
                    location=6,npc="ferret-medic.png",title=definition.title,objective=node.objective})
                HelpQuest.activate(data,active.id,node.objective)
                for _,textSize in ipairs({1,3}) do
                    fixture="map "..id.."/"..nodeName.." text="..textSize
                    data.accessibility.textSize=textSize
                    ui.drawMap(); mapCount=mapCount+1
                    if #node.choices==3 then
                        fixture="three-choice dialogue "..id.."/"..nodeName.." text="..textSize
                        game.helpDialogue={title=definition.title,objective=node.objective,
                            text=node.text or definition.opening,choices=node.choices}
                        game.dialogue={speaker="Ferret Medic",text=game.helpDialogue.text,timer=120}
                        hintBox=nil; ui.drawDialogue()
                        assert(#ui.helpDialogueChoices==3,"three authored choices must remain visible")
                        for index,choice in ipairs(ui.helpDialogueChoices) do
                            assert(choice.y+choice.h<=ui.helpDialoguePause.y,"dialogue choice must not touch the pause control")
                            if index>1 then
                                local previous=ui.helpDialogueChoices[index-1]
                                assert(choice.y>=previous.y+previous.h,"dialogue choices must not overlap")
                            end
                            if hintBox then
                                assert(hintBox.y+hintBox.h<=choice.y or hintBox.y>=choice.y+choice.h,
                                    "mobile response hint must not overlap a dialogue choice")
                            end
                        end
                        dialogueCount=dialogueCount+1
                    end
                end
            end
        end
    end,debug.traceback)
    Graphics.pop()
    Typography.drawText=originalDraw
    data.helpQuestSessions=saved.sessions; data.activeHelpQuestId=saved.active; data.accessibility.textSize=saved.textSize
    game.mapScroll=saved.mapScroll; game.dialogue=saved.dialogue; game.helpDialogue=saved.helpDialogue
    if not ok then error(message,0) end
    assert(failures==0,"authored text exceeds readable boxes in "..failures.." cases")
    record(string.format("PASS content fit: %d events / %d choices, %d map summaries, %d three-choice dialogues",
        eventCount,choiceCount,mapCount,dialogueCount))
end

return {run=run}
