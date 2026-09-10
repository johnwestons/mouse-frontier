$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$HarnessRoot = Join-Path $ProjectRoot 'output\character-motion-runtime-test'
$HarnessGame = Join-Path $HarnessRoot 'game'
$Love = Join-Path $env:ProgramFiles 'LOVE\love.exe'

if (-not (Test-Path -LiteralPath $Love)) {
    throw "LÖVE runtime not found at $Love"
}

New-Item -ItemType Directory -Force -Path $HarnessGame | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'character-motion-runtime-test\main.lua') -Destination (Join-Path $HarnessRoot 'main.lua') -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'game\character_motion.lua') -Destination (Join-Path $HarnessGame 'character_motion.lua') -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'game\character_motion_self_test.lua') -Destination (Join-Path $HarnessGame 'character_motion_self_test.lua') -Force

$QuotedHarness = '"' + $HarnessRoot + '"'
$Process = Start-Process -FilePath $Love -ArgumentList @('--console', $QuotedHarness) -WorkingDirectory $ProjectRoot -WindowStyle Hidden -Wait -PassThru
if ($Process.ExitCode -ne 0) {
    throw "Character motion runtime test failed with exit code $($Process.ExitCode)"
}
Write-Output 'CHARACTER_MOTION_TEST_OK'
