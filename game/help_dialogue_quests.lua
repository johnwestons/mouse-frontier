-- Retired generated dialogue. Original wording is preserved in the review inventory.
-- Keep this compatibility surface for the composition graph and old save layouts.
local Quests={version=2,order={},definitions={}}
function Quests.ensure() return nil end
function Quests.request() return nil end
function Quests.offer() return nil end
function Quests.begin() return nil end
function Quests.view() return nil end
function Quests.followup() return nil end
function Quests.pause() end
function Quests.choose() return {completed=false} end
function Quests.audit() return require("game.npc_conversations").audit() end
return Quests
