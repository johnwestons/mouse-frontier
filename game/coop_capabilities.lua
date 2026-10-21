-- Release-scope inventory and deny-by-default command permission policy.
-- Status tracks integration evidence, not whether a command is permitted.
local Capabilities={commands={},interactions={}}
local policies={personal=true,shared_assistance=true,host_progression=true,host_admin=true,local_presentation=true}

local function declare(policy,domain,names)
    for name in names:gmatch("%S+") do
        assert(not Capabilities.commands[name],"duplicate capability: "..name)
        Capabilities.commands[name]={policy=policy,domain=domain,status="planned"}
    end
end

declare("personal","player","player.move player.pose player.car inventory.swap inventory.equip inventory.consume weapon.select")
declare('personal','session','traveler.return traveler.ack')
declare("shared_assistance","inventory","storage.transfer loot.pickup loot.drop mailbox.collect inventory.give ammo.give")
declare("shared_assistance","trade","merchant.buy merchant.sell npc.gift npc.chatter passenger.chatter passenger.equip")
declare("shared_assistance","train","train.fuel train.upgrade train.engineUpgrade radio.station decoration.acquire decoration.place decoration.collect")
declare("shared_assistance","activities","firstAid.acquire firstAid.step firstAid.complete maintenance.acquire maintenance.step maintenance.complete weaponRepair.acquire weaponRepair.step weaponRepair.complete outfit.craft activity.release")
declare("shared_assistance","quests","quest.deliver quest.help expedition.survey expedition.cache")
declare("personal","combat","battle.move battle.attack battle.guard battle.heal battle.ability battle.item battle.swap battle.endTurn roaming.attack gun.aim gun.fire gun.reload gun.cover gun.ads gun.mode gun.select")
declare("shared_assistance","combat","lastStand.aid lastStand.position lastStand.supply range.acquire range.configure range.ammo range.fire range.reload range.release")
declare("shared_assistance","requests","progression.request")
declare("personal","scenes","scene.leaveTrain scene.returnTrain scene.enterHouse scene.exitHouse scene.office scene.expedition scene.caravan")
declare("host_progression","scenes","scene.rangeEnter scene.rangeExit")
declare("host_progression","story","travel.depart travel.arrive travel.finish event.begin event.choose event.continue quest.offer quest.accept quest.decline quest.storyHandIn passenger.recruit passenger.dismiss conversation.begin conversation.choose conversation.end family.choose finale.choose")
declare("host_progression","story","home.advance")
declare("host_progression","combat","encounter.roll battle.begin battle.enemyTurn battle.continue battle.retreat battle.retry lastStand.offer lastStand.decline lastStand.accept lastStand.advance lastStand.start lastStand.retry lastStand.withdraw ambush.start ambush.continue ambush.retry ambush.withdraw")
declare('host_progression','combat','roaming.pressure')
declare("host_admin","session","session.host session.end session.enroll session.rebind session.replace session.kick session.returnTraveler save.select save.write save.reset debug.grant")
declare("local_presentation","presentation","camera.move camera.zoom settings.change inventory.inspect map.inspect scene.inspect quest.inspect session.inspect session.leave")

-- Domain implementation does not imply network/UI guest readiness. Only
-- explicitly connected capabilities are marked network_implemented below.
-- Movement uses the dedicated realtime intent channel, not command dispatch;
-- this status does not claim physical-device or packaged-release acceptance.
Capabilities.commands["player.move"].status="realtime_implemented"
Capabilities.commands["player.car"].status="network_implemented"
for _,name in ipairs({"inventory.swap","inventory.consume","storage.transfer","loot.pickup","loot.drop","train.fuel","train.upgrade","train.engineUpgrade","merchant.buy","merchant.sell","npc.gift","passenger.equip"}) do
    Capabilities.commands[name].status="domain_implemented"
end
-- Ordinary scenes only; combat requires its own adapter.
for _,name in ipairs({"inventory.swap","inventory.consume","loot.pickup","loot.drop","storage.transfer","merchant.buy","merchant.sell","train.fuel","train.upgrade","train.engineUpgrade","radio.station","decoration.acquire","decoration.place","decoration.collect","activity.release","npc.gift","passenger.equip","npc.chatter","passenger.chatter"}) do
    Capabilities.commands[name].status="network_implemented"
end
Capabilities.commands["mailbox.collect"].status="network_ammunition_only"
for _,name in ipairs({"weaponRepair.acquire","weaponRepair.complete"}) do
    Capabilities.commands[name].status="domain_implemented"
end
Capabilities.commands["outfit.craft"].status="network_implemented"
Capabilities.commands["quest.help"].status="domain_implemented"
Capabilities.commands["quest.deliver"].status="domain_implemented"
Capabilities.commands['quest.help'].status='network_implemented'
Capabilities.commands['quest.deliver'].status='network_implemented'
for _,name in ipairs({"scene.returnTrain","scene.enterHouse","scene.exitHouse","scene.caravan","scene.expedition","travel.depart","travel.arrive","travel.finish"}) do
    Capabilities.commands[name].status="domain_implemented"
end
Capabilities.commands["scene.leaveTrain"].status="resolved_destination_commit"
Capabilities.commands["home.advance"].status="domain_implemented"
for _,name in ipairs({'conversation.begin','conversation.choose','conversation.end'}) do
    Capabilities.commands[name].status='domain_implemented'
end
for _,name in ipairs({'quest.offer','quest.accept','quest.decline','passenger.recruit'}) do
    Capabilities.commands[name].status='domain_implemented'
end
for _,name in ipairs({'event.begin','event.choose','event.continue'}) do
    Capabilities.commands[name].status='domain_implemented'
end
Capabilities.commands['finale.choose'].status='domain_implemented'
Capabilities.commands['encounter.roll'].status='domain_implemented'
for _,name in ipairs({'battle.begin','battle.move','battle.attack','battle.guard','battle.heal','battle.item','battle.swap','battle.ability','battle.endTurn','battle.enemyTurn','battle.continue','battle.retreat'}) do
    Capabilities.commands[name].status='domain_implemented'
end
-- These owned actions use the same guest panel for ordinary and expedition
-- tactical boards. First-person and special combat remain separate work.
for _,name in ipairs({'battle.move','battle.attack','battle.guard','battle.heal','battle.item','battle.swap','battle.ability','battle.endTurn'}) do
    Capabilities.commands[name].status='network_tactical'
end
-- Owned expedition melee swings have desktop/touch source-app evidence.
-- This command status excludes two-player roaming AI and packaged acceptance;
-- live enemy visuals and flood correction have their own presentation paths.
Capabilities.commands['roaming.attack'].status='network_field_melee'
-- Host-simulated companion contact is a saved wait, resolved by the host UI.
-- Source ENet checks cover engagement/withdrawal, save retry and reconnect.
Capabilities.commands['roaming.pressure'].status='network_roaming_encounter'
-- Shared survey/opening uses authored reach and saved receipts; item movement
-- continues through storage.transfer. Source desktop/touch evidence is separate
-- from complete adventure, package and physical-device acceptance.
Capabilities.commands['expedition.survey'].status='network_expedition_assistance'
Capabilities.commands['expedition.cache'].status='network_expedition_assistance'
-- Owned ambush/Last Stand guns and private guest controls; acceptance scope is recorded in the plan.
for _,name in ipairs({'gun.fire','gun.reload','gun.cover','gun.mode','gun.select'}) do
    Capabilities.commands[name].status='network_ambush_and_last_stand'
end
-- Both farmhouse actors can borrow at Guard Fox through saved modal proximity.
-- The same actor-owned supply command also works at a readied firing position.
Capabilities.commands['lastStand.supply'].status='network_last_stand_supply'
Capabilities.commands['lastStand.aid'].status='network_farmhouse_aid'
Capabilities.commands['lastStand.position'].status='network_last_stand_position'
-- Host-only original encounter lifecycle uses critical saved transactions.
-- The original ambush has no retry rule; declaring that permission must not
-- imply an invented retry control or grant it to a guest.
for _,name in ipairs({'ambush.start','ambush.continue','ambush.withdraw'}) do
    Capabilities.commands[name].status='domain_implemented'
end
Capabilities.commands['ambush.retry'].status='unavailable_original_rules'
for _,name in ipairs({'range.acquire','range.configure','range.ammo','range.fire','range.reload','range.release'}) do
    Capabilities.commands[name].status='network_range'
end
Capabilities.commands['player.pose'].status='network_ephemeral'
Capabilities.commands['progression.request'].status='network_transient_travel_request'
-- These guest panels are private UI, never remotely executable commands.
-- Their integration status does not imply physical-device verification.
Capabilities.commands['settings.change'].status='device_local_guest'
Capabilities.commands['map.inspect'].status='read_only_guest'
Capabilities.commands['scene.inspect'].status='read_only_guest'
Capabilities.commands['quest.inspect'].status='read_only_guest'
for _,name in ipairs({"session.host","session.enroll","session.rebind","session.replace","session.kick"}) do
    Capabilities.commands[name].status="domain_implemented"
end
for _,name in ipairs({"maintenance.acquire","maintenance.step","maintenance.complete","firstAid.acquire","firstAid.step","firstAid.complete"}) do
    Capabilities.commands[name].status="domain_implemented"
end
for _,name in ipairs({'maintenance.acquire','maintenance.step','maintenance.complete','weaponRepair.acquire','weaponRepair.step','weaponRepair.complete','firstAid.acquire','firstAid.step','firstAid.complete'}) do
    Capabilities.commands[name].status='network_implemented'
end

-- World affordances can expose multiple commands with different permissions:
-- talking to a resident never implicitly authorizes their story branch.
Capabilities.interactions={
    stopInspect={"scene.inspect"},
    item={"loot.pickup"},chest={"storage.transfer","loot.pickup"},mailbox={"mailbox.collect","storage.transfer"},
    radio={"radio.station"},carPrev={"player.car"},carNext={"player.car"},fire={"train.fuel"},
    returnTrain={"scene.returnTrain"},house={"scene.enterHouse"},houseExit={"scene.exitHouse"},
    shootingRange={"scene.rangeEnter","range.acquire"},
    npc={"npc.chatter","npc.gift","conversation.begin","quest.accept","merchant.buy","firstAid.acquire"},
    passenger={"passenger.chatter","passenger.equip","passenger.dismiss"},
    expedition={"scene.expedition","battle.begin","expedition.survey","expedition.cache"},
    crowCaravan={"scene.caravan","merchant.buy","merchant.sell"},
    homeStop={"home.advance","scene.returnTrain"},
    homeFox={"npc.chatter"},
}

function Capabilities.requireInteraction(kind)
    assert(Capabilities.interactions[kind],"undeclared co-op interaction: "..tostring(kind))
    return Capabilities.interactions[kind]
end

function Capabilities.authorize(name,role,effects)
    local spec=Capabilities.commands[name]
    if not spec then return false,"unknown_command" end
    if role~="host" and role~="guest" then return false,"unknown_actor" end
    if spec.policy=="local_presentation" then return false,"local_only" end
    if role~="host" and (spec.policy=="host_progression" or spec.policy=="host_admin") then return false,"host_only" end
    -- Effects are derived by the server-side domain handler, never received
    -- from the guest. Routine hand-ins/attacks must not hide story transitions.
    if role~="host" and effects and (effects.story or effects.scene or effects.questOffer or effects.ending) then
        return false,"host_only"
    end
    return true
end

function Capabilities.validate()
    for name,spec in pairs(Capabilities.commands) do
        if type(name)~="string" or not policies[spec.policy] or not spec.domain or not spec.status then
            return false,"invalid capability"
        end
    end
    for kind,commands in pairs(Capabilities.interactions) do
        if #commands==0 then return false,"empty interaction: "..kind end
        for _,name in ipairs(commands) do
            if not Capabilities.commands[name] then return false,"unknown interaction command: "..name end
        end
    end
    return true
end

return Capabilities
