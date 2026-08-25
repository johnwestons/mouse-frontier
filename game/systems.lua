-- Central composition manifest for the application-facing game systems.
-- Feature modules remain independently require-able; game.app constructs the
-- runtime-facing services after it has created authoritative application state.
return {
    battleRuntime = require("game.battle_runtime"),
    battleUI = require("game.battle_ui"),
    gameplayHUD = require("game.gameplay_hud"),
    gameplayInput = require("game.gameplay_input"),
    gameplayUpdate = require("game.gameplay_update"),
    interactions = require("game.interaction_router"),
    intro = require("game.intro_cinematic"),
    inventory = require("game.inventory_ui"),
    inventoryActions = require("game.inventory_actions"),
    journeyRules = require("game.journey_rules"),
    screens = require("game.screen_manager"),
    screenUI = require("game.screen_ui"),
    session = require("game.game_session"),
    sessionBootstrap = require("game.session_bootstrap"),
    worldRenderer = require("game.world_renderer"),
}
