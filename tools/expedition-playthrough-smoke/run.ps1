param(
    [ValidateSet('desktop','mobile','both')][string]$Mode='both',
    [string]$LoveExecutable='C:\Program Files\LOVE\lovec.exe',
    [int]$TimeoutSeconds=240
)

$ErrorActionPreference='Stop'
$repositoryPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputPath=Join-Path $repositoryPath '.stabilization\expedition-playthrough-smoke'
$previewStage=Join-Path $env:TEMP ('mouse-frontier-expedition-smoke-'+[guid]::NewGuid().ToString('N'))
if (-not (Test-Path -LiteralPath $LoveExecutable -PathType Leaf)) { throw "LÖVE runtime not found: $LoveExecutable" }
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
New-Item -ItemType Directory -Path $previewStage | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'main.lua'),(Join-Path $PSScriptRoot 'conf.lua') -Destination $previewStage
foreach($directory in @('assets','sounds')) {
    New-Item -ItemType Junction -Path (Join-Path $previewStage $directory) -Target (Join-Path $repositoryPath $directory) | Out-Null
}
$oldMobile=$env:MOUSE_FRONTIER_MOBILE
$oldRoot=$env:EXPEDITION_SMOKE_ROOT
$oldOutput=$env:EXPEDITION_SMOKE_OUTPUT
$modes=if($Mode -eq 'both') {@('desktop','mobile')} else {@($Mode)}
try {
    $env:EXPEDITION_SMOKE_ROOT=$repositoryPath
    $env:EXPEDITION_SMOKE_OUTPUT=$outputPath
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
            throw "$smokeMode expedition smoke exceeded $TimeoutSeconds seconds"
        }
        $process.WaitForExit(); $process.Refresh()
        if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath | Where-Object { $_ -match 'SUMMARY status=|EXPEDITION_SMOKE_ERROR' }
        }
        if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath | ForEach-Object { Write-Error $_ -ErrorAction Continue } }
        if ($process.ExitCode -ne 0) { throw "$smokeMode expedition smoke failed with exit code $($process.ExitCode)" }
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "$smokeMode expedition smoke report was not created" }
        $report=Get-Content -LiteralPath $reportPath -Raw
        if ($report -notmatch '(?m)^SUMMARY status=passed\b.*\berrors=0\s*$') { throw "$smokeMode expedition smoke report is incomplete or failed" }
    }
    Write-Output "EXPEDITION_SMOKE_OUTPUT=$outputPath"
} finally {
    $env:MOUSE_FRONTIER_MOBILE=$oldMobile
    $env:EXPEDITION_SMOKE_ROOT=$oldRoot
    $env:EXPEDITION_SMOKE_OUTPUT=$oldOutput
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $resolvedStage=[IO.Path]::GetFullPath($previewStage)
    if ($resolvedStage.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStage).StartsWith('mouse-frontier-expedition-smoke-')) {
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
