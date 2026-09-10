param(
    [int]$TimeoutSeconds = 240,
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\.stabilization\smoke-report.rpt'),
    [string]$PackagePath,
    [string]$LovePath = 'C:\Program Files\LOVE\lovec.exe',
    [int]$ReportFlushSeconds = 3,
    [switch]$Visible,
    [switch]$Full,
    [switch]$Mobile
)

$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resolvedReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath)
$stdoutPath = $resolvedReportPath + '.stdout.log'
$stderrPath = $resolvedReportPath + '.stderr.log'
$statusPath = $resolvedReportPath + '.status.txt'
$gamePath = if ($PackagePath) { (Resolve-Path -LiteralPath $PackagePath).Path } else { $workspacePath }
if (-not (Test-Path -LiteralPath $LovePath -PathType Leaf)) { throw "LÖVE runtime not found: $LovePath" }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedReportPath) | Out-Null
$previousSmokeValue = $env:MOUSE_FRONTIER_SMOKE
$previousSmokeReportValue = $env:MOUSE_FRONTIER_SMOKE_REPORT
$previousSmokeRptValue = $env:MOUSE_FRONTIER_SMOKE_RPT
$previousSmokeFullValue = $env:MOUSE_FRONTIER_SMOKE_FULL
$previousMobileValue = $env:MOUSE_FRONTIER_MOBILE
$testProcess = $null
$windowStyle = if ($Visible) { 'Normal' } else { 'Hidden' }

Remove-Item -LiteralPath $stdoutPath,$stderrPath,$statusPath,$resolvedReportPath -Force -ErrorAction SilentlyContinue

try {
    $env:MOUSE_FRONTIER_SMOKE = '1'
    if ($Mobile) { $env:MOUSE_FRONTIER_MOBILE = '1' } else { Remove-Item Env:MOUSE_FRONTIER_MOBILE -ErrorAction SilentlyContinue }
    if ($Full) { $env:MOUSE_FRONTIER_SMOKE_FULL = '1' } else { Remove-Item Env:MOUSE_FRONTIER_SMOKE_FULL -ErrorAction SilentlyContinue }
    # The controller/report module uses this contract to keep each run's report
    # beside the watchdog artifacts. Keep the shorter alias for older fixtures.
    $env:MOUSE_FRONTIER_SMOKE_REPORT = $resolvedReportPath
    $env:MOUSE_FRONTIER_SMOKE_RPT = $resolvedReportPath
    $testProcess = Start-Process -FilePath $lovePath `
        -ArgumentList ('"' + $gamePath + '"') `
        -WorkingDirectory $workspacePath `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle $windowStyle `
        -PassThru
    # Force creation of the underlying Process handle. Without this, some
    # PowerShell versions lose ExitCode after an asynchronously started process exits.
    $null = $testProcess.Handle

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $testProcess.Refresh()
    }

    if (-not $testProcess.HasExited) {
        Stop-Process -Id $testProcess.Id -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $statusPath -Value "TIMEOUT exit=124 seconds=$TimeoutSeconds"
        Write-Error "Smoke test exceeded $TimeoutSeconds seconds. The hung LÖVE test/error window was force-closed." -ErrorAction Continue
        exit 124
    }

    $testProcess.WaitForExit()
    $testProcess.Refresh()
    $processExitCode = $testProcess.ExitCode
    if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath }
    if (Test-Path -LiteralPath $stderrPath) {
        $stderrLines = @(Get-Content -LiteralPath $stderrPath)
        if ($stderrLines.Count -gt 0) {
            if ($processExitCode -eq 0) { $stderrLines | ForEach-Object { Write-Warning "SMOKE_STDERR: $_" } }
            else { $stderrLines | Write-Error -ErrorAction Continue }
        }
    }

    # Give the report writer a brief opportunity to flush after the game exits.
    $reportDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(0, $ReportFlushSeconds))
    while ((-not (Test-Path -LiteralPath $resolvedReportPath)) -and [DateTime]::UtcNow -lt $reportDeadline) {
        Start-Sleep -Milliseconds 100
    }

    $reportExists = Test-Path -LiteralPath $resolvedReportPath
    $reportBytes = if ($reportExists) { (Get-Item -LiteralPath $resolvedReportPath).Length } else { 0 }
    $reportState = if ($reportExists -and $reportBytes -gt 0) { "report=OK bytes=$reportBytes path=$resolvedReportPath" } else { "report=MISSING path=$resolvedReportPath" }
    Set-Content -LiteralPath $statusPath -Value "COMPLETE exit=$processExitCode $reportState"
    Write-Output "SMOKE_EXIT_CODE=$processExitCode"
    Write-Output "SMOKE_REPORT=$resolvedReportPath exists=$reportExists bytes=$reportBytes"
    if ($processExitCode -eq 0 -and (-not $reportExists -or $reportBytes -eq 0)) {
        Write-Error "Smoke test passed without producing a non-empty .rpt report: $resolvedReportPath" -ErrorAction Continue
        exit 2
    }
    if ($processExitCode -eq 0) {
        $reportText = [System.IO.File]::ReadAllText($resolvedReportPath)
        $summaries = [regex]::Matches($reportText, '(?m)^.*\bSUMMARY\s+status=([^\r\n]+)\r?$')
        if ($summaries.Count -ne 1 -or $summaries[0].Groups[1].Value -notmatch '^passed\b.*\berrors=0\b' -or $reportText -match '\bCHECKPOINT\s+\S+\s+result=FAIL\b') {
            Set-Content -LiteralPath $statusPath -Value "INCOMPLETE exit=2 path=$resolvedReportPath"
            Write-Error 'Smoke report does not confirm a complete passing playthrough. Capture-only and partial runs cannot pass this gate.' -ErrorAction Continue
            exit 2
        }
    }
    exit $processExitCode
}
finally {
    $env:MOUSE_FRONTIER_MOBILE = $previousMobileValue
    if ($testProcess -and -not $testProcess.HasExited) {
        Stop-Process -Id $testProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($null -eq $previousSmokeValue) {
        Remove-Item Env:MOUSE_FRONTIER_SMOKE -ErrorAction SilentlyContinue
    } else {
        $env:MOUSE_FRONTIER_SMOKE = $previousSmokeValue
    }
    if ($null -eq $previousSmokeReportValue) {
        Remove-Item Env:MOUSE_FRONTIER_SMOKE_REPORT -ErrorAction SilentlyContinue
    } else {
        $env:MOUSE_FRONTIER_SMOKE_REPORT = $previousSmokeReportValue
    }
    if ($null -eq $previousSmokeRptValue) {
        Remove-Item Env:MOUSE_FRONTIER_SMOKE_RPT -ErrorAction SilentlyContinue
    } else {
        $env:MOUSE_FRONTIER_SMOKE_RPT = $previousSmokeRptValue
    }
    if ($null -eq $previousSmokeFullValue) {
        Remove-Item Env:MOUSE_FRONTIER_SMOKE_FULL -ErrorAction SilentlyContinue
    } else {
        $env:MOUSE_FRONTIER_SMOKE_FULL = $previousSmokeFullValue
    }
}
