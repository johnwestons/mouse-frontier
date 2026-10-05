param(
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 240,
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\.stabilization\smoke-report.rpt'),
    [string]$PackagePath,
    [string]$LovePath = 'C:\Program Files\LOVE\lovec.exe',
    [ValidateRange(0, 30)][int]$ReportFlushSeconds = 3,
    [ValidateRange(0, 2147483647)][int]$Seed = 810,
    [ValidateRange(0.01, 0.05)][double]$StepSeconds = 0.05,
    [string]$Character,
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
$coverageContract = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'smoke_required_checkpoints.json') -Raw | ConvertFrom-Json
$requiredCheckpoints = @($coverageContract.common)
if ($Mobile) { $requiredCheckpoints += @($coverageContract.mobile) }
if ($Full) { $requiredCheckpoints += @($coverageContract.full) }
if (-not (Test-Path -LiteralPath $LovePath -PathType Leaf)) { throw "LOVE runtime not found: $LovePath" }
$runId = [guid]::NewGuid().ToString('N')
$runDirectory = Join-Path (Split-Path -Parent $resolvedReportPath) ('smoke-run-' + $runId)
$isolatedAppData = Join-Path $runDirectory 'appdata'
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null

# Inherited capture/repair flags must never silently reduce gate coverage.
$controlledNames = @('APPDATA', 'MOUSE_FRONTIER_MOBILE', 'MOUSE_FRONTIER_SMOKE',
    'MOUSE_FRONTIER_SMOKE_REPORT', 'MOUSE_FRONTIER_SMOKE_RPT', 'MOUSE_FRONTIER_SMOKE_FULL',
    'MOUSE_FRONTIER_SMOKE_SEED', 'MOUSE_FRONTIER_SMOKE_STEP', 'MOUSE_FRONTIER_SMOKE_RUN_ID',
    'MOUSE_FRONTIER_SMOKE_CHARACTER')
$controlledNames += @(Get-ChildItem Env: | Where-Object { $_.Name -match '^MOUSE_FRONTIER_SMOKE_' } | ForEach-Object { $_.Name })
$controlledNames = @($controlledNames | Select-Object -Unique)
$previousEnvironment = @{}
foreach ($name in $controlledNames) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$testProcess = $null
$windowStyle = if ($Visible) { 'Normal' } else { 'Hidden' }
Remove-Item -LiteralPath $stdoutPath,$stderrPath,$statusPath,$resolvedReportPath -Force -ErrorAction SilentlyContinue

try {
    foreach ($name in $controlledNames) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    $env:APPDATA = $isolatedAppData
    $env:MOUSE_FRONTIER_SMOKE = '1'
    if ($Mobile) { $env:MOUSE_FRONTIER_MOBILE = '1' }
    if ($Full) { $env:MOUSE_FRONTIER_SMOKE_FULL = '1' }
    if ($Character) { $env:MOUSE_FRONTIER_SMOKE_CHARACTER = $Character }
    $env:MOUSE_FRONTIER_SMOKE_SEED = [string]$Seed
    $env:MOUSE_FRONTIER_SMOKE_STEP = $StepSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
    $env:MOUSE_FRONTIER_SMOKE_RUN_ID = $runId
    $env:MOUSE_FRONTIER_SMOKE_REPORT = $resolvedReportPath
    $env:MOUSE_FRONTIER_SMOKE_RPT = $resolvedReportPath
    $testProcess = Start-Process -FilePath $LovePath -ArgumentList ('"' + $gamePath + '"') `
        -WorkingDirectory $workspacePath -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath -WindowStyle $windowStyle -PassThru
    $null = $testProcess.Handle
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $testProcess.Refresh()
    }
    if (-not $testProcess.HasExited) {
        Stop-Process -Id $testProcess.Id -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $statusPath -Value "TIMEOUT exit=124 seconds=$TimeoutSeconds run_id=$runId"
        Write-Error "Smoke test exceeded $TimeoutSeconds seconds. The hung test was force-closed." -ErrorAction Continue
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
    $reportDeadline = [DateTime]::UtcNow.AddSeconds($ReportFlushSeconds)
    while ((-not (Test-Path -LiteralPath $resolvedReportPath)) -and [DateTime]::UtcNow -lt $reportDeadline) { Start-Sleep -Milliseconds 100 }
    $reportExists = Test-Path -LiteralPath $resolvedReportPath -PathType Leaf
    $reportBytes = if ($reportExists) { (Get-Item -LiteralPath $resolvedReportPath).Length } else { 0 }
    Write-Output "SMOKE_EXIT_CODE=$processExitCode"
    Write-Output "SMOKE_REPORT=$resolvedReportPath exists=$reportExists bytes=$reportBytes"
    Write-Output "SMOKE_SAVE_DIRECTORY=$isolatedAppData\LOVE\mouse-frontier-smoke"
    if ($processExitCode -ne 0) {
        Set-Content -LiteralPath $statusPath -Value "FAILED exit=$processExitCode run_id=$runId"
        exit $processExitCode
    }
    $gateError = $null
    if (-not $reportExists -or $reportBytes -eq 0) { $gateError = 'A non-empty smoke report is required.' }
    else {
        $reportText = [IO.File]::ReadAllText($resolvedReportPath)
        $summaries = [regex]::Matches($reportText, '(?m)^\[[^\]\r\n]+\] SUMMARY status=passed steps=(\d+) checkpoints=(\d+) values=\d+ warnings=\d+ errors=0 duration=[\d.]+\r?$')
        $plans = [regex]::Matches($reportText, '(?m)^\[[^\]\r\n]+\] META plannedCheckpoints=(\d+)\r?$')
        $plannedSteps = [regex]::Matches($reportText, '(?m)^\[[^\]\r\n]+\] META planned_step_(\d+)="([^"\r\n]+)"\r?$')
        $checkpoints = [regex]::Matches($reportText, '(?m)^\[[^\]\r\n]+\] CHECKPOINT (\S+) result=PASS(?: .*)?\r?$')
        $expectedMode = if ($Full) { 'full-journey' } else { 'autoplay' }
        $expectedMobile = if ($Mobile) { 'true' } else { 'false' }
        $reportedSeed = [regex]::Match($reportText, '(?m)^\[[^\]\r\n]+\] META seed=(\d+)\r?$')
        $reportedStep = [regex]::Match($reportText, '(?m)^\[[^\]\r\n]+\] META updateStep=([\d.]+)\r?$')
        $expectedCharacter = if ($Character -and $Character -notmatch '\.png$') { $Character + '.png' } else { $Character }
        if ($reportText -notmatch ('(?m)^\[[^\]\r\n]+\] run_id=' + [regex]::Escape($runId) + ' started=')) { $gateError = 'Report run ID does not match this invocation.' }
        elseif ($reportText -notmatch ('(?m)^\[[^\]\r\n]+\] META mode="' + $expectedMode + '"\r?$') -or
                $reportText -notmatch ('(?m)^\[[^\]\r\n]+\] META mobile=' + $expectedMobile + '\r?$') -or
                $reportText -notmatch '(?m)^\[[^\]\r\n]+\] META scope="complete"\r?$') { $gateError = 'Report mode/scope does not confirm the requested complete suite.' }
        elseif (-not $reportedSeed.Success -or [int]$reportedSeed.Groups[1].Value -ne $Seed -or
                -not $reportedStep.Success -or [double]::Parse($reportedStep.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -ne $StepSeconds) { $gateError = 'Report seed/update step does not match the requested run.' }
        elseif ($expectedCharacter -and $reportText -notmatch ('(?m)^\[[^\]\r\n]+\] META character="' + [regex]::Escape($expectedCharacter) + '"\r?$')) { $gateError = 'Report character does not match the requested traveler.' }
        elseif ($summaries.Count -ne 1 -or ([regex]::Matches($reportText, '(?m)^\[[^\]\r\n]+\] SUMMARY ')).Count -ne 1 -or
                $reportText -match '(?m)^\[[^\]\r\n]+\] (ERROR |CHECKPOINT \S+ result=FAIL\b)') { $gateError = 'Report must contain one passing summary and no errors or failed checkpoints.' }
        elseif ($plans.Count -ne 1 -or [int]$plans[0].Groups[1].Value -lt 1) { $gateError = 'Report must declare a non-empty checkpoint plan.' }
        else {
            $planned = [int]$plans[0].Groups[1].Value
            $names = @($plannedSteps | ForEach-Object { $_.Groups[2].Value })
            $passedNames = @($checkpoints | ForEach-Object { $_.Groups[1].Value })
            $indices = @($plannedSteps | ForEach-Object { [int]$_.Groups[1].Value })
            if ($planned -ne [int]$summaries[0].Groups[1].Value -or $planned -ne [int]$summaries[0].Groups[2].Value -or
                $planned -ne $checkpoints.Count -or $planned -ne $plannedSteps.Count -or
                @($names | Select-Object -Unique).Count -ne $planned -or @($passedNames | Select-Object -Unique).Count -ne $planned -or
                @($indices | Select-Object -Unique).Count -ne $planned -or ($indices | Measure-Object -Minimum).Minimum -ne 1 -or
                ($indices | Measure-Object -Maximum).Maximum -ne $planned -or @($names | Where-Object { $_ -notin $passedNames }).Count -gt 0) {
                $gateError = 'Planned, completed, and summarized checkpoints do not match exactly.'
            }
            elseif (@($requiredCheckpoints | Where-Object { $_ -notin $passedNames }).Count -gt 0) {
                $missingCoverage = @($requiredCheckpoints | Where-Object { $_ -notin $passedNames }) -join ', '
                $gateError = 'Required gameplay coverage is missing: ' + $missingCoverage
            }
        }
    }
    if ($gateError) {
        Set-Content -LiteralPath $statusPath -Value "INCOMPLETE exit=2 run_id=$runId reason=$gateError"
        Write-Error $gateError -ErrorAction Continue
        exit 2
    }
    Set-Content -LiteralPath $statusPath -Value "COMPLETE exit=0 checkpoints=$planned seed=$Seed run_id=$runId path=$resolvedReportPath"
    exit 0
}
finally {
    if ($testProcess -and -not $testProcess.HasExited) { Stop-Process -Id $testProcess.Id -Force -ErrorAction SilentlyContinue }
    foreach ($name in $controlledNames) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
}
