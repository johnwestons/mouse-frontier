from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class LuaArchitectureTests(unittest.TestCase):
    def test_main_is_a_thin_lifecycle_shell(self) -> None:
        source = (ROOT / "main.lua").read_text(encoding="utf-8")
        active_lines = [line for line in source.splitlines() if line.strip() and not line.lstrip().startswith("--")]
        self.assertLessEqual(len(active_lines), 24)
        self.assertIn('require("game.app")', source)
        self.assertEqual(re.findall(r'require\("game\.[^"]+"\)', source), ['require("game.app")'])

        expected_callbacks = {
            "load", "update", "draw", "mousepressed", "mousemoved", "mousereleased",
            "wheelmoved", "keypressed", "keyreleased", "touchpressed", "touchmoved",
            "touchreleased", "focus", "quit",
        }
        forwarded = set(re.findall(r"function love\.([a-z]+)\(", source))
        self.assertEqual(forwarded, expected_callbacks)

    def test_application_boundaries_exist(self) -> None:
        app = (ROOT / "game" / "app.lua").read_text(encoding="utf-8")
        systems = (ROOT / "game" / "systems.lua").read_text(encoding="utf-8")
        schema = (ROOT / "game" / "save_schema.lua").read_text(encoding="utf-8")
        save = (ROOT / "game" / "save.lua").read_text(encoding="utf-8")
        config = (ROOT / "game" / "config.lua").read_text(encoding="utf-8")
        runtime = (ROOT / "game" / "runtime_state.lua").read_text(encoding="utf-8")
        bootstrap = (ROOT / "game" / "session_bootstrap.lua").read_text(encoding="utf-8")
        gameplay_input = (ROOT / "game" / "gameplay_input.lua").read_text(encoding="utf-8")
        gameplay_update = (ROOT / "game" / "gameplay_update.lua").read_text(encoding="utf-8")
        inventory_actions = (ROOT / "game" / "inventory_actions.lua").read_text(encoding="utf-8")
        journey_rules = (ROOT / "game" / "journey_rules.lua").read_text(encoding="utf-8")

        for callback in ("load", "update", "draw", "keypressed", "mousepressed", "quit"):
            self.assertIn(f"function App.{callback}", app)
        self.assertTrue(app.rstrip().endswith("return App"))
        self.assertIn('require("game.systems")', app)
        self.assertIn('require("game.save_schema")', app)
        self.assertIn('require("game.config")', app)
        self.assertIn('require("game.runtime_state")', app)
        self.assertNotRegex(app, r"local\s+state\s*=")
        self.assertNotRegex(app, r"local\s+selectedSlot\s*[,=]")
        self.assertNotRegex(app, r"local\s+scene\s*[,=]")
        self.assertIn("CURRENT_VERSION = 25", schema)
        self.assertIn("function SaveSchema.migrate", schema)
        self.assertIn("function SaveSchema.validate", schema)
        self.assertIn("SaveSchema.migrations=migrations", schema)
        self.assertIn("rewriteRequired=steps>0 or not wasCanonical", schema)
        self.assertIn('require("game.save_schema")', save)
        self.assertIn("SaveSchema.migrate(data)", save)
        self.assertIn("SaveSchema.migrate(data)", bootstrap)
        self.assertIn("baseWidth = 960", config)
        self.assertIn("game.gameplay_input", systems)
        self.assertIn("function RuntimeState:syncForSave", runtime)
        self.assertIn("function RuntimeState:isSynchronized", runtime)
        self.assertIn("return {new=new}", bootstrap)
        self.assertNotIn("setfenv", bootstrap)
        self.assertNotIn("dependency resolver", bootstrap)
        self.assertIn("Systems.sessionBootstrap=Systems.sessionBootstrap.new({", app)
        self.assertIn("return {new=new}", gameplay_input)
        self.assertNotIn("setfenv", gameplay_input)
        self.assertNotIn("dependency resolver", gameplay_input)
        self.assertIn("Systems.gameplayInput=Systems.gameplayInput.new({", app)
        self.assertIn("return {new=new}", gameplay_update)
        self.assertNotIn("setfenv", gameplay_update)
        self.assertNotIn("dependency resolver", gameplay_update)
        self.assertIn("Systems.gameplayUpdate=GameplayUpdate.new({", app)
        self.assertNotIn("resolveGameplayUpdate", app)
        self.assertIn("return {new=new}", inventory_actions)
        self.assertNotIn("setfenv", inventory_actions)
        self.assertNotIn("dependency resolver", inventory_actions)
        self.assertIn("Systems.inventoryActions=Systems.inventoryActions.new({", app)
        self.assertNotIn("resolveInventoryActions", app)
        self.assertIn("return {new=new}", journey_rules)
        self.assertNotIn("setfenv", journey_rules)
        self.assertNotIn("dependency resolver", journey_rules)
        self.assertIn("Systems.journeyRules=Systems.journeyRules.new({", app)
        self.assertNotIn("resolveJourneyRules", app)

    def test_mobile_package_stages_the_shared_lua_tree(self) -> None:
        builder = (ROOT / "tools" / "build_mobile_package.py").read_text(encoding="utf-8")
        self.assertIn('ROOT / "main.lua"', builder)
        self.assertIn('ROOT / "conf.lua"', builder)
        self.assertIn('(ROOT / "game").rglob("*.lua")', builder)
        self.assertFalse(list((ROOT / "mobile").rglob("*.lua")), "mobile must not contain a copied Lua gameplay tree")


if __name__ == "__main__":
    unittest.main()
