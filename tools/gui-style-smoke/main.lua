-- Render real screens with an isolated disposable journey; never invent speech.
io.stdout:setvbuf('no')
local app,c,stage,advance,finished
local names={'01-title','02-characters','03-hud','04-inventory','05-map','06-dialogue',
    '07-pause','08-audio','09-accessibility','10-controls','11-radio','12-upgrades',
    '13-journal','14-confirmation','15-small-phone'}
local function protect(fn)
    local ok,message=xpcall(fn,debug.traceback)
    if not ok then print('GUI_STYLE_FAIL '..message);finished=true;love.event.quit(1) end
end
local function prepare()
    local r,u=c.runtime,c.ui
    r.state=stage==1 and 'slots' or stage==2 and 'characters' or 'game'
    r.dialogue=nil;r.inventoryOpen=false;r.mapOpen=false;r.trainUpgradeOpen=false
    r.journeyLogOpen=false;r.pendingConfirmation=nil
    u.escMenuOpen=false;u.optionsOpen=false;u.radioOpen=false
    if stage==4 then r.inventoryOpen=true
    elseif stage==5 then r.mapOpen=true;r.mapScroll=0
    elseif stage==6 then r.dialogue={speaker='Traveler',text=c.catalog.dialogueLines[2]}
    elseif stage==7 then u.escMenuOpen=true
    elseif stage>=8 and stage<=10 then
        u.optionsOpen=true;r.optionsPage=({'audio','accessibility','controls'})[stage-7]
    elseif stage==11 then u.radioOpen=true
    elseif stage==12 then r.trainUpgradeOpen=true
    elseif stage==13 then r.journeyLogOpen=true
    elseif stage==14 then r.pendingConfirmation={kind='trainCar',message='Purchase this train car?',confirmLabel='PURCHASE'}
    elseif stage==15 then love.window.setMode(960,540,{vsync=0}) end
    app.update(.02)
end
function love.load()
    protect(function()
        require('game.smoke_playthrough').install=function(value)c=value end
        app=require('game.application_composition').new({engine=love});app.installSmoke();app.load()
        c.runtime.selectedSlot=99
        local data=c.newSave(c.characters[1]);data.homeStop=nil;data.location=2;data.scene='train';data.passengers={};data.stopped=true
        assert(c.enterGame(data),'fixture could not enter game')
        data.resources={food=10,water=10,coal=10,oil=10}
        stage=1;prepare()
    end)
end
function love.update()
    if finished or not advance then return end
    protect(function()
        stage=stage+1
        if not names[stage] then print('GUI_STYLE_OK screens='..#names);finished=true;love.event.quit(0);return end
        advance=false;prepare()
    end)
end
function love.draw()
    if finished or advance then return end
    protect(function() app.draw();love.graphics.captureScreenshot(names[stage]..'.png');advance=true end)
end
