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
        config = (ROOT / "game" / "config.lua").read_text(encoding="utf-8")
        runtime = (ROOT / "game" / "runtime_state.lua").read_text(encoding="utf-8")
        bootstrap = (ROOT / "game" / "session_bootstrap.lua").read_text(encoding="utf-8")

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
        self.assertIn("baseWidth = 960", config)
        self.assertIn("game.gameplay_input", systems)
        self.assertIn("function RuntimeState:syncForSave", runtime)
        self.assertIn("function RuntimeState:isSynchronized", runtime)
        self.assertIn("return {new=new}", bootstrap)
        self.assertNotIn("setfenv", bootstrap)
        self.assertNotIn("dependency resolver", bootstrap)
        self.assertIn("Systems.sessionBootstrap=Systems.sessionBootstrap.new({", app)

    def test_mobile_package_stages_the_shared_lua_tree(self) -> None:
        builder = (ROOT / "tools" / "build_mobile_package.py").read_text(encoding="utf-8")
        self.assertIn('ROOT / "main.lua"', builder)
        self.assertIn('ROOT / "conf.lua"', builder)
        self.assertIn('(ROOT / "game").rglob("*.lua")', builder)
        self.assertFalse(list((ROOT / "mobile").rglob("*.lua")), "mobile must not contain a copied Lua gameplay tree")


if __name__ == "__main__":
    unittest.main()
