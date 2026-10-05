"""Failure-injection checks for report status and durable I/O contracts."""
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
class SmokeReportBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            files={}; fail=false; attempts=0
            love={filesystem={
                write=function(path,payload)
                    attempts=attempts+1
                    if fail then return false,'disk unavailable' end
                    files[path]=payload; return true
                end,
                append=function(path,payload)
                    attempts=attempts+1
                    if fail then return false,'disk unavailable' end
                    files[path]=(files[path] or '')..payload; return true
                end
            }}
            Report=require('game.smoke_report')
            function summaryCount(value)
                local _,count=value:gsub('SUMMARY status=',''); return count
            end
            function mockFileIo(failure)
                love=nil; contents=''; closes=0
                io.open=function()
                    if failure=='open' then return nil,'open denied' end
                    return {
                        write=function(self,payload)
                            if failure=='write' then return nil,'write denied' end
                            if failure=='throw' then error('write exception') end
                            contents=contents..payload; return self
                        end,
                        flush=function()
                            if failure=='flush' then return nil,'flush denied' end
                            return true
                        end,
                        close=function()
                            closes=closes+1
                            if failure=='close' then return nil,'close denied' end
                            return true
                        end,
                    }
                end
            end
        ''')

    def test_failed_checkpoint_forces_failed_summary(self):
        self.lua.execute('''
            local report=Report.new({path='result.rpt'})
            report:checkpoint('missing item',false)
            assert(report:finish('passed'))
            assert(report.counts.errors==1 and files['result.rpt']:find('SUMMARY status=failed',1,true))
            assert(files['result.rpt']:find('CHECKPOINT missing item result=FAIL',1,true))
        ''')

    def test_missing_checkpoint_boolean_cannot_pass(self):
        self.lua.execute('''
            local report=Report.new({path='result.rpt'})
            report:checkpoint('nil result',nil)
            report:finish(); assert(files['result.rpt']:find('SUMMARY status=failed',1,true))
        ''')

    def test_failed_step_cannot_be_reported_as_passed(self):
        self.lua.execute('''
            local report=Report.new({path='result.rpt'})
            report:step('runtime crash','failed')
            report:finish('passed')
            assert(files['result.rpt']:find('SUMMARY status=failed',1,true))
        ''')

    def test_existing_error_overrides_explicit_passed_status(self):
        self.lua.execute('''
            local report=Report.new({path='result.rpt'})
            report:error('broken state'); report:finish('passed')
            assert(files['result.rpt']:find('SUMMARY status=failed',1,true))
        ''')

    def test_success_and_capture_statuses_remain_supported(self):
        self.lua.execute('''
            for _,status in ipairs({'passed','captured'}) do
                local report=Report.new({path=status..'.rpt'})
                report:checkpoint('ready',true); assert(report:finish(status))
                assert(files[status..'.rpt']:find('SUMMARY status='..status,1,true))
            end
        ''')

    def test_filesystem_failure_keeps_pending_report_and_error_detail(self):
        self.lua.execute('''
            local report=Report.new({path='result.rpt'}); fail=true
            local ok,err=report:finish('passed')
            assert(not ok and err=='disk unavailable' and not report.closed and #report.lines>0)
            fail=false; assert(report:finish('passed'))
            assert(report.closed and summaryCount(files['result.rpt'])==1)
            local previous=attempts; assert(report:finish('passed') and attempts==previous)
        ''')

    def test_filesystem_exception_is_reported(self):
        self.lua.execute('''
            love.filesystem.write=function() error('write exploded') end
            local report=Report.new({path='result.rpt'})
            local ok,err=report:flush()
            assert(not ok and err:find('write exploded',1,true) and #report.lines>0)
        ''')

    def test_append_failure_retains_unwritten_lines(self):
        self.lua.execute('''
            local report=Report.new({path='result.rpt'})
            assert(report:flush()); local first=files['result.rpt']
            report:checkpoint('second',true); fail=true
            assert(not report:flush() and files['result.rpt']==first and #report.lines>0)
            fail=false; assert(report:finish('passed'))
            assert(summaryCount(files['result.rpt'])==1 and files['result.rpt']:find('CHECKPOINT second result=PASS',1,true))
        ''')

    def test_absolute_path_open_failure_is_detected(self):
        self.lua.execute('''
            mockFileIo('open')
            local report=Report.new({path='C:/isolated/result.rpt'})
            local ok,err=report:finish('passed')
            assert(not ok and err=='open denied' and not report.closed and closes==0)
        ''')

    def test_absolute_path_write_flush_close_failures_are_detected(self):
        self.lua.execute('''
            for _,failure in ipairs({'write','flush','close','throw'}) do
                mockFileIo(failure)
                local report=Report.new({path='C:/isolated/result.rpt'})
                local ok,err=report:finish('passed')
                assert(not ok and not report.closed and #report.lines>0 and closes==1)
                assert(err:find(failure=='throw' and 'write exception' or failure..' denied',1,true))
            end
        ''')

    def test_absolute_path_success_is_durable_and_closes_file(self):
        self.lua.execute('''
            mockFileIo(nil)
            local report=Report.new({path='C:/isolated/result.rpt'})
            report:checkpoint('ready',true)
            assert(report:finish('passed') and report.closed and closes==1)
            assert(contents:find('SUMMARY status=passed',1,true))
        ''')


if __name__ == '__main__':
    unittest.main()
