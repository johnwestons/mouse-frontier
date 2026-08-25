param(
    [switch]$PackageOnly,
    [switch]$Install,
    [string]$Ffmpeg
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$userProfilePath = [Environment]::GetFolderPath('UserProfile')
$bundledPython = Join-Path $userProfilePath '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$python = if (Test-Path -LiteralPath $bundledPython) {
    $bundledPython
} elseif ($pythonCommand) {
    $pythonCommand.Source
} else {
    throw 'Python 3 is required to build the shared mobile package.'
}
$packageArguments = @((Join-Path $projectRoot 'tools\build_mobile_package.py'))
if ($Ffmpeg) { $packageArguments += @('--ffmpeg',$Ffmpeg) }
& $python @packageArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$report = Get-Content -Raw (Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json
$loveExecutable = 'C:\Program Files\LOVE\lovec.exe'
if (Test-Path -LiteralPath $loveExecutable) {
    $previousSmoke = $env:MOUSE_FRONTIER_SMOKE
    $previousMobile = $env:MOUSE_FRONTIER_MOBILE
    $previousReport = $env:MOUSE_FRONTIER_SMOKE_REPORT
    try {
        $env:MOUSE_FRONTIER_SMOKE = '1'
        $env:MOUSE_FRONTIER_MOBILE = '1'
        $env:MOUSE_FRONTIER_SMOKE_REPORT = (Join-Path $projectRoot '.stabilization\mobile-package-smoke.rpt')
        & $loveExecutable $report.package
        if ($LASTEXITCODE -ne 0) { throw "Packaged mobile smoke test failed with exit code $LASTEXITCODE" }
    }
    finally {
        $env:MOUSE_FRONTIER_SMOKE = $previousSmoke
        $env:MOUSE_FRONTIER_MOBILE = $previousMobile
        $env:MOUSE_FRONTIER_SMOKE_REPORT = $previousReport
    }
}
if (-not $PackageOnly) {
    $apkArguments = @{ PackagePath = $report.package }
    if ($Install) { $apkArguments.Install = $true }
    & (Join-Path $projectRoot 'tools\build_android_apk.ps1') @apkArguments
}
