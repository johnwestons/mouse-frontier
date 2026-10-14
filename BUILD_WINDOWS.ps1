param(
    [string]$LoveRoot = 'C:\Program Files\LOVE',
    [string]$PythonPath,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $PythonPath) {
    $PythonPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCommand) { $PythonPath = $pythonCommand.Source }
    }
}
if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'Python 3 with Pillow is required; pass -PythonPath.' }
$packageArguments = @((Join-Path $PSScriptRoot 'tools\build_windows_package.py'),'--love-root',$LoveRoot)
if ($OutputDirectory) { $packageArguments += @('--output-dir',$OutputDirectory) }
& $PythonPath @packageArguments
if ($LASTEXITCODE -ne 0) { throw "Windows portable packaging failed with exit code $LASTEXITCODE" }
