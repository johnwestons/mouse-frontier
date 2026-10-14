-- Routine hand-ins share the recipient panel. Story choices stay with the host.
local Access=require('game.coop_quest_access')
local Util=require('game.util')
local Focus=require('game.ui_focus')
local Style=require('game.ui_layout')
local Panel={}; Panel.__index=Panel
local failures={recipient_unavailable='Return to the recipient to continue.',quest_unavailable='This accepted task is no longer available here.',
    item_selection_required='Select the requested item from your backpack.',item_changed='The selected item changed. Review the task again.',
    cargo_unavailable='Required supplies are missing. Nothing was delivered.',story_hand_in='The host controls this story decision.',
    stale_revision='The task, supplies or reward storage changed. Review it again.',stale_scene='The host moved the party.',
    invalid_revisions='The party changed. Review the task again.',rate_limited='Please wait a moment and try again.'}
function Panel.new(parent) return setmetatable({parent=parent,view=parent.view,c=parent.c,runtime=parent.runtime,ui=parent.ui,page=0},Panel) end
function Panel:recipient() return Access.recipient(self.runtime.saveData,self.parent:state(),self.parent.targetId,self.parent.npc) end
function Panel:available()
    local r=self:recipient(); return r and #Access.offers(self.runtime.saveData,r,self.c.catalog)>0
end
function Panel:open()
    if self.parent.pending or self.parent.quote or self.parent.speech or not self.runtime.peopleOpen or not self:available() then return false end
    self.opened=true; self.quote=nil; self.receipt=nil; self.notice=nil; self.drawn=nil; self.page=0
    self.ui.keyboardFocusId=nil; return true
end
function Panel:close() self.opened=false; self.quote=nil; self.drawn=nil; self.controls=nil; self.ui.keyboardFocusId=nil end
function Panel:choose(index)
    if self.parent.pending or self.quote or not self.opened or not self.view:actionsAllowed() then return false end
    local offer=self.drawn and self.drawn[index]
    if not offer or not offer.available then return false end
    self.quote=offer; self.notice=nil; self.receipt=nil; self.ui.keyboardFocusId='confirm'; return true
end
function Panel:confirm()
    local q=self.quote
    if not q or self.parent.pending or not self.opened or not self.view:actionsAllowed() or not self:recipient() then return false end
    local id,reason=self.view.controller.network:submitCommand(q.command,q.args,self.view.epoch,q.expected)
    if not id then self.notice=failures[reason] or 'Task unavailable. Review it and try again.'; return false end
    self.parent.pending={id=id,command=q.command,quest=true,epoch=self.view.epoch}
    self.view:neutralize(); self.notice='Waiting for the host to confirm delivery and save...'; return true
end
function Panel:update()
    local p=self.parent.pending; if not p or not p.quest then return end
    local r=self.view.controller.network.lastCommandResult; if not r or r.requestId~=p.id then return end
    if r.savePending or r.reason=='save_pending' or r.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
    if r.ok and self.runtime.saveData.coop.revision<r.revision then self.notice='Updating the task...'; return end
    self.parent.pending=nil; self.quote=nil; self.drawn=nil; self.lastOutcome=r
    if p.epoch~=self.view.epoch or not self.opened then return end
    if not r.ok then self.notice=failures[r.reason] or 'Task unavailable. Review it and try again.'; return end
    local d=r.details; self.receipt=d
    if not d.completed then self.notice='Bring '..Util.titleFromFile(d.missing)..' in your backpack to complete this request.'
    elseif p.command=='quest.help' then self.notice='Delivered '..Util.titleFromFile(d.item)..'. +'..d.gained..' goodwill. Total '..d.total..'.'
    else
        self.notice='Delivery complete. +'..d.coal..' train coal, +'..d.scrap..' scrap, +'..d.gained..' goodwill.\n'
            ..'Reward: '..Util.titleFromFile(d.item)..(d.amount and ' x'..d.amount or '')..' / '..d.delivery..'.\n'
        local xp={}; for _,id in ipairs({'host','companion'}) do if d.recipients[id] then xp[#xp+1]=id..' +'..d.recipients[id]..' XP' end end
        self.notice=self.notice..table.concat(xp,' / ')..(d.levels>0 and ' / +'..d.levels..' levels for you.' or '.')
    end
end
function Panel:targets() return self.controls or {} end
function Panel:keypressed(key)
    if key=='escape' or key=='acback' or key=='j' then
        if self.quote and not self.parent.pending then self.quote=nil; self.ui.keyboardFocusId=nil else self:close() end
    elseif key=='pageup' then self.page=math.max(0,self.page-1)
    elseif key=='pagedown' then self.page=self.page+1
    elseif key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then Focus.move(self.ui,self:targets(),'guest-quests',key,love.keyboard.isDown('lshift','rshift'))
    elseif key=='return' or key=='kpenter' or key=='space' then local t=Focus.current(self.ui,self:targets(),'guest-quests'); if t and t.enabled then t.action() end end
    return true
end
function Panel:press(x,y)
    for _,t in ipairs(self:targets()) do if t.enabled and Util.pointIn(x,y,t.rect) then self.ui.keyboardFocusId=t.id; t.action(); break end end
    return true
end
function Panel:draw()
    local g=love.graphics; local text=function(...) self.view.trade:textBox(...) end; self.controls={}
    local function button(id,label,x,y,w,h,action,enabled)
        local rect=Style.transformRect(self.view.inventory:button(label,x,y,w,h,enabled~=false,.82))
        self.ui['quests_'..id]=rect; self.controls[#self.controls+1]={id=id,rect=rect,action=action,enabled=enabled~=false}; return rect
    end
    g.setColor(0,0,0,.78); g.rectangle('fill',0,0,960,720)
    Style.scope('guest-quests',{x=80,y=50,w=800,h=620},function()
        self.view.inventory:frame(80,50,800,620,1,1); g.setColor(self.c.colors.cream)
        text('QUEST HELP / '..Util.titleFromFile(self.parent.npc),110,70,740,40,1.1,'center')
        text(self.notice or 'Help with tasks already accepted by the host.',110,120,740,98,.82,'center')
        local recipient=self:recipient(); self.drawn=recipient and Access.offers(self.runtime.saveData,recipient,self.c.catalog) or {}
        local pages=math.max(1,math.ceil(#self.drawn/4)); self.page=math.min(self.page,pages-1)
        if self.quote then
            local q=self.quote; local label=q.command=='quest.help' and 'Deliver '..Util.titleFromFile(q.item)..' from backpack '..q.slot..'?'
                or 'Complete the '..q.kind..' delivery here?'
            text(label,140,250,680,55,1,'center')
            if q.cargo then
                local parts={}; for _,item in ipairs(q.cargo.items) do parts[#parts+1]=Util.titleFromFile(item.name)..' / backpack '..item.slot end
                for _,use in ipairs(q.cargo.ammoUsed) do parts[#parts+1]=use.amount..' '..use.name end
                if q.cargo.resource and q.cargo.resourceUsed>0 then parts[#parts+1]=q.cargo.resourceUsed..' shared '..q.cargo.resource end
                text(#parts>0 and ('Supplies: '..table.concat(parts,', ')) or 'The encounter requirement has been met.',140,318,680,140,.84,'center')
            end
            button('confirm','CONFIRM',150,490,300,60,function() self:confirm() end,not self.parent.pending)
            button('cancel','BACK',510,490,300,60,function() if self.parent.pending then self:close() else self.quote=nil end end,true)
        else
            for row=1,4 do
                local index=self.page*4+row; local offer=self.drawn[index]
                if offer then
                    local label=offer.command=='quest.help' and ('ITEM REQUEST / '..Util.titleFromFile(offer.item)..(offer.slot and ' / BACKPACK '..offer.slot or ' / MISSING'))
                        or ('DELIVER '..offer.kind:upper()..(not offer.available and ' / SUPPLIES MISSING' or ''))
                    button('task'..row,label,115,236+(row-1)*67,730,57,function() self:choose(index) end,not self.parent.pending and offer.available)
                end
            end
            if #self.drawn==0 then text('No accepted routine tasks are available here.',115,285,730,80,1,'center') end
            button('prev','<',115,539,110,54,function() self.page=math.max(0,self.page-1) end,not self.parent.pending and self.page>0)
            text('Page '..(self.page+1)..' / '..pages,250,548,230,38,.84,'center')
            button('next','>',505,539,110,54,function() self.page=math.min(pages-1,self.page+1) end,not self.parent.pending and self.page<pages-1)
            button('close','BACK',639,539,206,54,function() self:close() end,true)
        end
    end)
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-quests')) end
end
return Panel
