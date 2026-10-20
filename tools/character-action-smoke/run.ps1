param(
    [ValidateSet('desktop','mobile','both')][string]$Mode='both',
    [string]$LoveExecutable='C:\Program Files\LOVE\lovec.exe',
    [int]$TimeoutSeconds=240,
    [string]$GameRoot
)

$ErrorActionPreference='Stop'
$repositoryPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runtimePath=if ($GameRoot) { (Resolve-Path -LiteralPath $GameRoot).Path } else { $repositoryPath }
$outputPath=Join-Path $repositoryPath '.stabilization\character-action'
$previewStage=Join-Path $env:TEMP ('mouse-frontier-character-action-smoke-'+[guid]::NewGuid().ToString('N'))
if (-not (Test-Path -LiteralPath $LoveExecutable -PathType Leaf)) { throw "LÖVE runtime not found: $LoveExecutable" }
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
New-Item -ItemType Directory -Path $previewStage | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'main.lua'),(Join-Path $PSScriptRoot 'conf.lua') -Destination $previewStage
foreach($directory in @('assets','sounds')) {
    New-Item -ItemType Junction -Path (Join-Path $previewStage $directory) -Target (Join-Path $runtimePath $directory) | Out-Null
}
$oldMobile=$env:MOUSE_FRONTIER_MOBILE
$oldRoot=$env:CHARACTER_ACTION_SMOKE_ROOT
$oldOutput=$env:CHARACTER_ACTION_SMOKE_OUTPUT
$modes=if($Mode -eq 'both') {@('desktop','mobile')} else {@($Mode)}
try {
    $env:CHARACTER_ACTION_SMOKE_ROOT=$runtimePath
    $env:CHARACTER_ACTION_SMOKE_OUTPUT=$outputPath
    foreach($smokeMode in $modes) {
        $reportPath=Join-Path $outputPath ($smokeMode+'-report.txt')
        $stdoutPath=Join-Path $outputPath ($smokeMode+'-engine-log.txt')
        $stderrPath=Join-Path $outputPath ($smokeMode+'-engine-errors.txt')
        Remove-Item -LiteralPath $reportPath,$stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
        $env:MOUSE_FRONTIER_MOBILE=if($smokeMode -eq 'mobile') {'1'} else {'0'}
        $process=Start-Process -FilePath $LoveExecutable -ArgumentList ('"'+$previewStage+'"') -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $null=$process.Handle
        $process.Refresh()
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 200
            $process.Refresh()
        }
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "$smokeMode character action smoke exceeded $TimeoutSeconds seconds"
        }
        $process.WaitForExit(); $process.Refresh()
        if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath | Where-Object { $_ -match 'SUMMARY status=|CHARACTER_ACTION_SMOKE_ERROR' }
        }
        if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath | ForEach-Object { Write-Error $_ -ErrorAction Continue } }
        if ($process.ExitCode -ne 0) { throw "$smokeMode character action smoke failed with exit code $($process.ExitCode)" }
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "$smokeMode character action smoke report was not created" }
        $report=Get-Content -LiteralPath $reportPath -Raw
        if ($report -notmatch '(?m)^SUMMARY status=passed\b.*\berrors=0\s*$') { throw "$smokeMode character action smoke report is incomplete or failed" }
    }
    Write-Output "CHARACTER_ACTION_SMOKE_OUTPUT=$outputPath"
} finally {
    $env:MOUSE_FRONTIER_MOBILE=$oldMobile
    $env:CHARACTER_ACTION_SMOKE_ROOT=$oldRoot
    $env:CHARACTER_ACTION_SMOKE_OUTPUT=$oldOutput
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $resolvedStage=[IO.Path]::GetFullPath($previewStage)
    if ($resolvedStage.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStage).StartsWith('mouse-frontier-character-action-smoke-')) {
        foreach ($directory in @('assets','sounds')) {
            $link=Join-Path $resolvedStage $directory
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
        foreach ($file in @('main.lua','conf.lua')) {
            $path=Join-Path $resolvedStage $file
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        if (Test-Path -LiteralPath $resolvedStage) { [IO.Directory]::Delete($resolvedStage) }
    }
}
