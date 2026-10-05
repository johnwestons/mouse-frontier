"""Failure-injection checks for the real callback-driven smoke controller."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class SmokeControllerBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute("package.path=root..'/?.lua;'..package.path; Controller=require('game.smoke_controller')")

    def test_missing_boolean_is_not_a_passing_check(self):
        self.lua.execute('''
            local c=Controller.new({timeout=.5,steps={{name='missing_ready',
                action=function() return {} end,
                check=function(_,_,_,result) return result.ready end}}})
            c:update(.1)
            assert(c.running and #c.results==0)
            c:update(.5)
            assert(c.failed and #c.results==0 and c.errors[1]:find('check returned nil',1,true))
        ''')

    def test_false_with_reason_waits_then_passes_without_repeating_action(self):
        self.lua.execute('''
            local attempts,actions=0,0
            local c=Controller.new({steps={{name='async',action=function() actions=actions+1; return true end,
                check=function() attempts=attempts+1; return attempts>=2,'not yet ready' end}}})
            c:update(.1); assert(c.running and not c.failed)
            c:update(.1); assert(c.finished and not c.failed and #c.results==1 and actions==1)
        ''')

    def test_timeout_preserves_check_failure_reason(self):
        self.lua.execute('''
            local c=Controller.new({timeout=.2,steps={{name='blocked',
                check=function() return false,'door never opened' end}}})
            c:update(.3)
            assert(c.failed and c.errors[1]:find('door never opened',1,true))
        ''')

    def test_assertion_exception_is_fatal_on_first_attempt(self):
        self.lua.execute('''
            local attempts=0
            local c=Controller.new({steps={{name='assertion',check=function()
                attempts=attempts+1; assert(false,'broken invariant') end}}})
            c:update(.01); c:update(.01)
            assert(c.failed and attempts==1 and #c.results==0)
            assert(c.errors[1]:find('broken invariant',1,true) and c.errors[1]:find('stack traceback',1,true))
        ''')

    def test_expectations_require_an_actual_snapshot(self):
        self.lua.execute('''
            for _,source in ipairs({false,17,'missing'}) do
                local c=Controller.new({timeout=.1,hooks={snapshot=function() return source end},
                    steps={{name='needs_snapshot',expect={state='game'}}}})
                c:update(.2)
                assert(c.failed and #c.results==0 and c.errors[1]:find('snapshot table',1,true))
            end
            local c=Controller.new({timeout=.1,steps={{expect={state='game'}}}})
            c:update(.2); assert(c.failed and #c.results==0)
        ''')

    def test_missing_expected_field_cannot_pass_predicate(self):
        self.lua.execute('''
            local c=Controller.new({timeout=.1,hooks={snapshot=function() return {} end},
                steps={{expect={ready=function(value) return value end}}}})
            c:update(.2); assert(c.failed and #c.results==0)
        ''')

    def test_expectation_predicate_exceptions_are_fatal(self):
        self.lua.execute('''
            local c=Controller.new({hooks={snapshot={ready=false}},steps={{name='predicate',
                expect={ready=function() error('invalid expected state') end}}}})
            local ok=pcall(function() c:update(.01) end)
            assert(ok and c.failed and c.errors[1]:find('invalid expected state',1,true))
        ''')

    def test_nested_expectations_and_epsilon_still_pass(self):
        self.lua.execute('''
            local c=Controller.new({hooks={snapshot={state={scene='train'},x=12.01}},
                steps={{epsilon=.02,expect={['state.scene']='train',x=12}}}})
            c:update(.01); assert(c.finished and not c.failed and #c.results==1)
        ''')

    def test_empty_sparse_and_unverified_steps_are_rejected(self):
        self.lua.execute('''
            local valid={check=function() return true end}
            local invalid={{},{[2]=valid},{[1]=valid,[3]=valid},{true},
                {{action=function() return true end}},{{expect={}}},{{check=true}},
                {{check=function() return true end,timeout=0}},{{check=function() return true end,timeout=math.huge}}}
            for _,steps in ipairs(invalid) do
                assert(not pcall(function() Controller.new({steps=steps}) end),'malformed steps were accepted')
            end
        ''')

    def test_action_hook_retries_until_done(self):
        self.lua.execute('''
            local calls=0
            local c=Controller.new({hooks={action=function() calls=calls+1; return calls>=3 end},
                steps={{name='hook_retry',check=function() return true end}}})
            c:update(.1); assert(c.running and calls==2)
            c:update(.1); assert(c.finished and not c.failed and calls==3)
        ''')

    def test_after_failure_does_not_count_a_completed_checkpoint(self):
        self.lua.execute('''
            local c=Controller.new({steps={{name='after_failure',check=function() return true end,
                after=function() error('report failed') end}}})
            c:update(.01)
            assert(c.failed and #c.results==0 and c.errors[1]:find('report failed',1,true))
        ''')

    def test_controller_report_absolute_path_uses_io_and_rejects_write_failure(self):
        self.lua.execute('''
            love={filesystem={write=function() error('absolute path was passed to sandbox') end}}
            local closed=false
            io.open=function() return {
                write=function() return nil,'disk full' end,
                close=function() closed=true; return true end,
            } end
            local c=Controller.new({steps={{check=function() return true end}}})
            local ok,err=c:writeReport('C:/isolated/report.rpt')
            assert(not ok and err=='disk full' and closed)
        ''')

    def test_controller_report_relative_path_propagates_filesystem_exception(self):
        self.lua.execute('''
            love={filesystem={write=function() error('relative write failed') end}}
            local c=Controller.new({steps={{check=function() return true end}}})
            local ok,err=c:writeReport('report.rpt')
            assert(not ok and err:find('relative write failed',1,true))
        ''')


if __name__ == '__main__':
    unittest.main()
