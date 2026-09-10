"""Run the full regression suite, rejecting missing dependencies and skipped tests."""
from __future__ import annotations

import importlib
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
lua_path = os.environ.get("LUA_RUNTIME_PYTHONPATH")
if not lua_path and (ROOT / ".stabilization" / "python-deps").is_dir():
    lua_path = str(ROOT / ".stabilization" / "python-deps")
if lua_path:
    os.environ["LUA_RUNTIME_PYTHONPATH"] = lua_path
    sys.path.insert(0, lua_path)


def main() -> int:
    missing = []
    for module, package in (("numpy", "numpy"), ("PIL", "Pillow"), ("lupa.lua51", "lupa")):
        try:
            importlib.import_module(module)
        except ImportError:
            missing.append(package)
    if missing:
        print("Missing test dependencies: " + ", ".join(missing), file=sys.stderr)
        print("Install tools/requirements-test.txt into your Python test environment.", file=sys.stderr)
        return 2
    suite = unittest.defaultTestLoader.discover(str(ROOT / "tools" / "tests"))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.skipped:
        print("Full audit requires every test to run; skipped tests are not accepted.", file=sys.stderr)
    return 0 if result.wasSuccessful() and not result.skipped else 1


if __name__ == "__main__":
    raise SystemExit(main())
