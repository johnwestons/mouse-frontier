-- Shared existing ending presentation, with controls only on the host.
local Finale=require('game.finale_progression')
local Players=require('game.coop_players')
local Style=require('game.ui_layout')
local UI={}
function UI.draw(data,finale,c,host)
    local g=love.graphics; local textBox=c.textBox; local colors=c.colors
    local choices,exit
    Style.scope('ending',{x=80,y=55,w=800,h=610},function()
        g.setColor(colors.panel); g.rectangle('fill',80,55,800,610,20,20)
        g.setColor(colors.brass); textBox(finale.choice and finale.tier or 'THE LAST SWITCH',110,83,740,58,1.5,'center')
        g.setColor(colors.cream); textBox(finale.reunion,145,151,670,86,.95,'center')
        g.setColor(colors.brass)
        textBox('GOODWILL '..finale.goodwill..'  •  FAMILY CLUES '..finale.storyClues..'/10  •  MYSTERY CLUES '..finale.mysteryClues..'/5',120,245,720,20,.66,'center')
        textBox('HELP '..finale.helpCount..'  •  RIDES '..finale.rides..'  •  TRAIN '..finale.condition..'%  •  CARS '..finale.cars..'  •  LEVEL '..finale.level,120,271,720,20,.66,'center')
        if not finale.choice then
            if host then
                g.setColor(colors.cream); textBox('Your family asks what comes next. Choose the legacy this journey leaves behind.',185,318,590,46,.78,'center')
                choices={}
                for index,choice in ipairs(Finale.choices) do
                    local x=115+(index-1)*245
                    g.setColor(colors.cream); textBox(choice.description,x,362,220,73,.8,'center')
                    choices[index]=c.button(index..'  '..choice.title,x,440,220,58,true)
                    choices[index].id=choice.id
                end
                g.setColor(colors.cream); textBox('All three paths are hopeful. Your choice changes the final legacy, never a good-or-evil alignment.',190,535,580,24,.62,'center')
            else
                g.setColor(colors.cream); textBox('The host is choosing the campaign ending.',145,365,670,82,.92,'center')
            end
        else
            g.setColor(colors.cream); textBox(finale.outcome,145,313,670,82,.92,'center')
            g.setColor(colors.brass); textBox(finale.tierText,155,404,650,63,.85,'center')
            data=Players.campaignOf(data)
            local character=data.players and data.players.host.character or data.character
            local family={character,(data.npcRoster or {})[1],(data.npcRoster or {})[2]}
            for i,file in ipairs(family) do
                local img=c.characterImages[file] or c.npcImages[file]
                if img then
                    local s=math.min(72/img:getWidth(),96/img:getHeight()); g.setColor(1,1,1)
                    g.draw(img,380+(i-1)*100,520+math.sin(c.animationClock*3+i)*3,0,s,s,img:getWidth()/2,img:getHeight()/2)
                end
            end
            if host then exit=c.button('CAMPAIGN COMPLETE  •  RETURN',330,590,300,45,true)
            else g.setColor(colors.cream); textBox('The host has completed this campaign.',145,590,670,45,.9,'center') end
        end
    end)
    return choices,exit
end
return UI
