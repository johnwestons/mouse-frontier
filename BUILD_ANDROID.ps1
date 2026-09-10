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
& (Join-Path $projectRoot 'tools\run_smoke.ps1') -PackagePath $report.package -Mobile `
    -ReportPath (Join-Path $projectRoot '.stabilization\mobile-package-smoke.rpt')
if ($LASTEXITCODE -ne 0) { throw "Packaged mobile smoke test failed with exit code $LASTEXITCODE" }
& (Join-Path $projectRoot 'tools\run_last_stand_smoke.ps1') `
    -GameRoot (Join-Path $projectRoot 'output\mobile\stage') `
    -ReportPath (Join-Path $projectRoot '.stabilization\mobile-last-stand-smoke.rpt')
if (-not $PackageOnly) {
    $apkArguments = @{ PackagePath = $report.package }
    if ($Install) { $apkArguments.Install = $true }
    & (Join-Path $projectRoot 'tools\build_android_apk.ps1') @apkArguments
}
