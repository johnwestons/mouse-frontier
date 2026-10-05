param(
    [string]$PythonPath,
    [string]$LovePath = 'C:\Program Files\LOVE\lovec.exe',
    [string]$ReportDirectory = (Join-Path $PSScriptRoot '..\.stabilization\validation'),
    [int]$Seed = 1337,
    [ValidateRange(1,2147483647)][int]$RegressionTimeoutSeconds = 600,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 240,
    [ValidateRange(1,3600)][int]$SpecialistTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$resolvedReportDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
New-Item -ItemType Directory -Force -Path $resolvedReportDirectory | Out-Null
$summaryPath = Join-Path $resolvedReportDirectory 'validation-summary.rpt'
$summaryJsonPath = Join-Path $resolvedReportDirectory 'validation-summary.json'
$startedAt = [DateTime]::UtcNow
$results = [System.Collections.Generic.List[object]]::new()
$firstFailureExit = 0

function Write-ValidationSummary {
    param([string]$Status)
    $passed = @($results | Where-Object { $_.exitCode -eq 0 }).Count
    $failed = @($results | Where-Object { $_.exitCode -ne 0 }).Count
    $lines = @('VALIDATION scope=source seed=' + $Seed + ' started=' + $startedAt.ToString('o') + ' root="' + $workspacePath + '"')
    foreach ($result in $results) {
        $lines += ('GATE name={0} result={1} exit={2} seconds={3} log="{4}" report="{5}"' -f
            $result.name,$result.status,$result.exitCode,$result.seconds,$result.log,$result.report)
    }
    $lines += ('SUMMARY status={0} passed={1} failed={2} completed={3} planned=7' -f
        $Status,$passed,$failed,$results.Count)
    Set-Content -LiteralPath $summaryPath -Value $lines -Encoding UTF8
    [pscustomobject]@{
        status=$Status; scope='source'; sourceRoot=$workspacePath; seed=$Seed; startedAt=$startedAt.ToString('o')
        passed=$passed; failed=$failed; planned=7; results=@($results.ToArray())
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryJsonPath -Encoding UTF8
}

function Invoke-BoundedRegressionProcess {
    param([string]$Executable,[string]$ScriptPath,[string]$LogPath,[int]$ProcessTimeoutSeconds)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    # -u keeps redirected Python progress visible while the child is running.
    $startInfo.Arguments = '-u "' + $ScriptPath + '"'
    $startInfo.WorkingDirectory = $workspacePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $false
    $timedOut = $false
    $timer = [Diagnostics.Stopwatch]::StartNew()
    [IO.File]::WriteAllText($LogPath,'')
    try {
        $null = $process.Start()
        $started = $true
        $streams = @(
            @{ reader=$process.StandardOutput; pending=$process.StandardOutput.ReadLineAsync() },
            @{ reader=$process.StandardError; pending=$process.StandardError.ReadLineAsync() }
        )
        $drainDeadline = $null
        while ($true) {
            foreach ($stream in $streams) {
                $linesDrained = 0
                while ($linesDrained -lt 100 -and $null -ne $stream.pending -and $stream.pending.IsCompleted) {
                    $line = $stream.pending.GetAwaiter().GetResult()
                    if ($null -eq $line) { $stream.pending = $null; break }
                    [IO.File]::AppendAllText($LogPath,$line + [Environment]::NewLine)
                    $line | Out-Host
                    $stream.pending = $stream.reader.ReadLineAsync()
                    $linesDrained += 1
                }
            }
            if ($process.HasExited -and @($streams | Where-Object { $null -ne $_.pending }).Count -eq 0) { break }
            if (-not $timedOut -and $timer.Elapsed.TotalSeconds -ge $ProcessTimeoutSeconds) {
                $timedOut = $true
                # Child smoke watchdogs retain their own engine timeouts;
                # this watchdog stops the regression process itself.
                if (-not $process.HasExited) {
                    try { $process.Kill() } catch { if (-not $process.HasExited) { throw } }
                }
                $line = 'REGRESSION_TIMEOUT exit=124 seconds=' + $ProcessTimeoutSeconds
                [IO.File]::AppendAllText($LogPath,$line + [Environment]::NewLine)
                $line | Out-Host
                # Give killed-child pipes a bounded interval to deliver their
                # final partial progress line, even if a descendant holds a pipe.
                $drainDeadline = $timer.Elapsed.TotalSeconds + 2
            }
            if ($timedOut -and $timer.Elapsed.TotalSeconds -ge $drainDeadline) { break }
            Start-Sleep -Milliseconds 50
        }
        if ($timedOut) { return 124 }
        return $process.ExitCode
    } finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill() } catch { if (-not $process.HasExited) { throw } }
        }
        $process.Dispose()
        $timer.Stop()
    }
}

function Invoke-ValidationGate {
    param([string]$Name,[string]$Executable,[string[]]$Arguments,[string]$ReportPath,[int]$ProcessTimeoutSeconds=0)
    $gateLogPath = Join-Path $resolvedReportDirectory ($Name + '.process.log')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $gateExit = 1
    Write-Output ('VALIDATION_START=' + $Name)
    try {
        # Each runner has its own process: its exit statement cannot terminate
        # this orchestrator or suppress the remaining independent gates.
        # unittest normally writes progress to stderr, so native stderr must
        # be captured without PowerShell turning it into a terminating error.
        if ($ProcessTimeoutSeconds -gt 0) {
            $gateExit = Invoke-BoundedRegressionProcess -Executable $Executable -ScriptPath $Arguments[0] `
                -LogPath $gateLogPath -ProcessTimeoutSeconds $ProcessTimeoutSeconds
        } else {
            $ErrorActionPreference = 'Continue'
            & $Executable @Arguments 2>&1 | Tee-Object -FilePath $gateLogPath | Out-Host
            $gateExit = $LASTEXITCODE
        }
        if ($null -eq $gateExit) { $gateExit = 1 }
    } catch {
        $_ | Out-String | Add-Content -LiteralPath $gateLogPath
        Write-Warning ($Name + ': ' + $_.Exception.Message)
        $gateExit = 1
    } finally {
        $timer.Stop()
    }
    $status = if ($gateExit -eq 0) { 'passed' } else { 'failed' }
    $results.Add([pscustomobject]@{
        name=$Name; status=$status; exitCode=[int]$gateExit
        seconds=[Math]::Round($timer.Elapsed.TotalSeconds,2)
        log=$gateLogPath; report=$ReportPath
    })
    if ($gateExit -ne 0 -and $script:firstFailureExit -eq 0) {
        $script:firstFailureExit = [int]$gateExit
    }
    Write-ValidationSummary -Status 'running'
    Write-Output ('VALIDATION_GATE={0} result={1} exit={2}' -f $Name,$status,$gateExit)
}

Write-ValidationSummary -Status 'starting'
$oldLoveExe = $env:LOVE_EXE
$pushedLocation = $false
try {
    if (-not $PythonPath) {
        $profilePath = [Environment]::GetFolderPath('UserProfile')
        $bundledPythonPath = Join-Path $profilePath '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
        if (Test-Path -LiteralPath $bundledPythonPath -PathType Leaf) {
            $PythonPath = $bundledPythonPath
        } else {
            $pythonCommand = Get-Command python.exe,python3.exe -CommandType Application -ErrorAction SilentlyContinue |
                Where-Object { $_.Source -notmatch '\\Microsoft\\WindowsApps\\python(?:3)?\.exe$' } |
                Select-Object -First 1
            if ($pythonCommand) { $PythonPath = $pythonCommand.Source }
        }
    }
    if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        throw 'Python 3 executable not found. Pass -PythonPath with your test environment executable.'
    }
    if (-not (Test-Path -LiteralPath $LovePath -PathType Leaf)) {
        throw "LÖVE runtime not found: $LovePath"
    }
    $PythonPath = (Resolve-Path -LiteralPath $PythonPath).Path
    $LovePath = (Resolve-Path -LiteralPath $LovePath).Path
    $powerShellPath = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
    $env:LOVE_EXE = $LovePath
    Push-Location -LiteralPath $workspacePath
    $pushedLocation = $true

    Invoke-ValidationGate -Name 'regression' -Executable $PythonPath `
        -Arguments @((Join-Path $PSScriptRoot 'run_tests.py')) `
        -ProcessTimeoutSeconds $RegressionTimeoutSeconds `
        -ReportPath (Join-Path $resolvedReportDirectory 'regression.process.log')

    $smokeRunner = Join-Path $PSScriptRoot 'run_smoke.ps1'
    foreach ($mode in @('desktop','mobile','full-route')) {
        $reportPath = Join-Path $resolvedReportDirectory ($mode + '.rpt')
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$smokeRunner,
            '-LovePath',$LovePath,'-ReportPath',$reportPath,
            '-TimeoutSeconds',$TimeoutSeconds.ToString(),'-Seed',$Seed.ToString())
        if ($mode -eq 'mobile') { $arguments += '-Mobile' }
        if ($mode -eq 'full-route') { $arguments += '-Full' }
        Invoke-ValidationGate -Name $mode -Executable $powerShellPath -Arguments $arguments -ReportPath $reportPath
    }

    foreach ($specialist in @(
        @{ name='last-stand'; script='run_last_stand_smoke.ps1' },
        @{ name='zoom'; script='run_zoom_smoke.ps1' },
        @{ name='mobile-pickup'; script='run_mobile_pickup_smoke.ps1' }
    )) {
        $reportPath = Join-Path $resolvedReportDirectory ($specialist.name + '.rpt')
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',
            (Join-Path $PSScriptRoot $specialist.script),'-ReportPath',$reportPath,
            '-TimeoutSeconds',$SpecialistTimeoutSeconds.ToString())
        Invoke-ValidationGate -Name $specialist.name -Executable $powerShellPath `
            -Arguments $arguments -ReportPath $reportPath
    }
} catch {
    $_ | Out-String | Add-Content -LiteralPath (Join-Path $resolvedReportDirectory 'validation-error.log')
    Write-Error $_ -ErrorAction Continue
    if ($firstFailureExit -eq 0) { $firstFailureExit = 1 }
} finally {
    if ($pushedLocation) { Pop-Location }
    if ($null -eq $oldLoveExe) { Remove-Item Env:LOVE_EXE -ErrorAction SilentlyContinue } else { $env:LOVE_EXE = $oldLoveExe }
    $status = if ($firstFailureExit -eq 0 -and $results.Count -eq 7) { 'passed' } else { 'failed' }
    Write-ValidationSummary -Status $status
    Write-Output ('VALIDATION_SUMMARY=' + $summaryPath)
}

if ($firstFailureExit -ne 0) { exit $firstFailureExit }
if ($results.Count -ne 7) { exit 1 }
exit 0
