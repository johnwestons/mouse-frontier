param(
    [ValidateSet('desktop','mobile','both')][string]$Mode='both',
    [string]$LoveExecutable='C:\Program Files\LOVE\lovec.exe'
)
$ErrorActionPreference='Stop'
$repositoryPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputPath=Join-Path $repositoryPath 'docs\concepts\expedition-validation'
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$previewStage=Join-Path $env:TEMP ('mouse-frontier-expedition-preview-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $previewStage | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'main.lua'),(Join-Path $PSScriptRoot 'conf.lua') -Destination $previewStage
foreach($directory in @('assets','sounds')) {
    New-Item -ItemType Junction -Path (Join-Path $previewStage $directory) -Target (Join-Path $repositoryPath $directory) | Out-Null
}
$oldMobile=$env:MOUSE_FRONTIER_MOBILE
$oldRoot=$env:EXPEDITION_PREVIEW_ROOT
$oldOutput=$env:EXPEDITION_PREVIEW_OUTPUT
try {
    $env:EXPEDITION_PREVIEW_ROOT=$repositoryPath
    $env:EXPEDITION_PREVIEW_OUTPUT=$outputPath
    $modes=if($Mode -eq 'both') {@('desktop','mobile')} else {@($Mode)}
    foreach($previewMode in $modes) {
        $env:MOUSE_FRONTIER_MOBILE=if($previewMode -eq 'mobile') {'1'} else {'0'}
        $process=Start-Process -FilePath $LoveExecutable -ArgumentList ('"'+$previewStage+'"') -WindowStyle Hidden -Wait -PassThru `
            -RedirectStandardOutput (Join-Path $outputPath ($previewMode+'-engine-log.txt')) `
            -RedirectStandardError (Join-Path $outputPath ($previewMode+'-engine-errors.txt'))
        Get-Content -LiteralPath (Join-Path $outputPath ($previewMode+'-report.txt'))
        if($process.ExitCode -ne 0) { throw ($previewMode+' preview failed with exit code '+$process.ExitCode) }
    }
    Write-Output ('Captures: '+$outputPath)
} finally {
    $env:MOUSE_FRONTIER_MOBILE=$oldMobile
    $env:EXPEDITION_PREVIEW_ROOT=$oldRoot
    $env:EXPEDITION_PREVIEW_OUTPUT=$oldOutput
}
