-- Central composition manifest for the application-facing game systems.
-- Feature modules remain independently require-able; game.app constructs the
-- runtime-facing services after it has created authoritative application state.
return {
    audioRuntime = require("game.audio_runtime"),
    battleRuntime = require("game.battle_runtime"),
    battleUI = require("game.battle_ui"),
    eventRuntime = require("game.event_runtime"),
    gameplayHUD = require("game.gameplay_hud"),
    gameplayInput = require("game.gameplay_input"),
    gameplayUpdate = require("game.gameplay_update"),
    interactions = require("game.interaction_router"),
    intro = require("game.intro_cinematic"),
    inventory = require("game.inventory_ui"),
    inventoryActions = require("game.inventory_actions"),
    inventoryPresenter = require("game.inventory_presenter"),
    journeyRules = require("game.journey_rules"),
    screens = require("game.screen_manager"),
    screenUI = require("game.screen_ui"),
    session = require("game.game_session"),
    sessionBootstrap = require("game.session_bootstrap"),
    trainCarRuntime = require("game.train_car_runtime"),
    worldScene = require("game.world_scene"),
    worldRenderer = require("game.world_renderer"),
}
