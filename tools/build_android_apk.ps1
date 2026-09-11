param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [switch]$Install
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $projectRoot 'output\mobile'
$toolingRoot = Join-Path $outputRoot 'tooling'
$androidRoot = Join-Path $toolingRoot 'android-sdk'
$loveAndroidRoot = Join-Path $outputRoot 'love-android'
$config = Get-Content -Raw (Join-Path $projectRoot 'mobile\config.json') | ConvertFrom-Json
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path

function Get-StreamSha256 {
    param([System.IO.Stream]$Stream)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

# Reject a stale or unrelated game archive before downloading tools or building.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$packageArchive = [System.IO.Compression.ZipFile]::OpenRead($resolvedPackage)
try {
    $buildManifest = $packageArchive.GetEntry('mobile-build.json')
    if (-not $buildManifest) { throw 'Game package is missing mobile-build.json; run BUILD_ANDROID.ps1 first' }
    $reader = [System.IO.StreamReader]::new($buildManifest.Open())
    try { $packageManifest = $reader.ReadToEnd() | ConvertFrom-Json }
    finally { $reader.Dispose() }
    foreach ($field in @('applicationId','applicationName','versionName','versionCode','loveVersion')) {
        if ($packageManifest.$field -ne $config.$field) { throw "Game package $field differs from mobile/config.json; rebuild the mobile package" }
    }
    $sourceFiles = @((Get-Item -LiteralPath (Join-Path $projectRoot 'main.lua')),(Get-Item -LiteralPath (Join-Path $projectRoot 'conf.lua')))
    $sourceFiles += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'game') -Recurse -Filter '*.lua' -File)
    $packagedLua = @($packageArchive.Entries | Where-Object { $_.FullName -match '^(main\.lua|conf\.lua|game/.*\.lua)$' })
    if ($packagedLua.Count -ne $sourceFiles.Count) { throw 'Game package has a stale Lua file inventory; rebuild the mobile package' }
    foreach ($source in $sourceFiles) {
        $relative = $source.FullName.Substring($projectRoot.Length + 1).Replace('\','/')
        $entry = $packageArchive.GetEntry($relative)
        if (-not $entry) { throw "Game package is missing $relative; rebuild the mobile package" }
        $stream = $entry.Open()
        try { $entrySha = Get-StreamSha256 $stream }
        finally { $stream.Dispose() }
        if ($entrySha -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $source.FullName).Hash.ToLowerInvariant()) {
            throw "Game package contains stale source: $relative; rebuild the mobile package"
        }
    }
}
finally { $packageArchive.Dispose() }
$packageSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPackage).Hash.ToLowerInvariant()

New-Item -ItemType Directory -Force -Path $toolingRoot,$androidRoot | Out-Null

function Get-VerifiedDownload {
    param([string]$Uri,[string]$Destination,[string]$Sha256)
    if (-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
    }
    $algorithm = if ($Sha256.Length -eq 40) { 'SHA1' } else { 'SHA256' }
    $actual = (Get-FileHash -Algorithm $algorithm -LiteralPath $Destination).Hash
    if ($actual -ne $Sha256) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Checksum verification failed for $Uri"
    }
}

$javaExecutable = Get-ChildItem (Join-Path $toolingRoot 'jdk-17') -Recurse -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $javaExecutable) {
    Write-Output 'Downloading a verified JDK 17 Android build dependency...'
    $jdkMetadata = Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
    $jdkPackage = $jdkMetadata[0].binary.package
    $jdkArchive = Join-Path $toolingRoot 'jdk-17.zip'
    Get-VerifiedDownload -Uri $jdkPackage.link -Destination $jdkArchive -Sha256 $jdkPackage.checksum
    $jdkRoot = Join-Path $toolingRoot 'jdk-17'
    New-Item -ItemType Directory -Force -Path $jdkRoot | Out-Null
    Expand-Archive -LiteralPath $jdkArchive -DestinationPath $jdkRoot -Force
    $javaExecutable = Get-ChildItem $jdkRoot -Recurse -Filter java.exe | Select-Object -First 1 -ExpandProperty FullName
}
$javaHome = Split-Path (Split-Path $javaExecutable -Parent) -Parent

$sdkManager = Join-Path $androidRoot 'cmdline-tools\12.0\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkManager)) {
    Write-Output 'Downloading the verified Android command-line tools...'
    $commandToolsArchive = Join-Path $toolingRoot 'android-command-line-tools-12.zip'
    Get-VerifiedDownload -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -Destination $commandToolsArchive -Sha256 '3d2917302740f476999a091bc5558837c7a863c5'
    # Use a short temporary drive while extracting deep SDK dependency paths.
    # Windows can otherwise silently omit files under a OneDrive project path.
    $sdkExtractDrive = $null
    foreach ($candidate in @('Q:','R:','S:','T:')) {
        if (-not (Test-Path ($candidate + '\'))) {
            & subst.exe $candidate $androidRoot
            if ($LASTEXITCODE -eq 0) { $sdkExtractDrive = $candidate; break }
        }
    }
    if (-not $sdkExtractDrive) { throw 'Could not allocate a temporary SDK extraction drive' }
    try {
        $versionedRoot = Join-Path ($sdkExtractDrive + '\') 'cmdline-tools\12.0'
        New-Item -ItemType Directory -Force -Path $versionedRoot | Out-Null
        & tar.exe -xf $commandToolsArchive -C $versionedRoot --strip-components=1
        if ($LASTEXITCODE -ne 0) { throw "Android command-tools extraction failed with exit code $LASTEXITCODE" }
    }
    finally { & subst.exe $sdkExtractDrive /D | Out-Null }
    $sdkManager = Join-Path $androidRoot 'cmdline-tools\12.0\bin\sdkmanager.bat'
}

$previousJavaHome = $env:JAVA_HOME
$previousAndroidHome = $env:ANDROID_HOME
$previousAndroidSdkRoot = $env:ANDROID_SDK_ROOT
$previousPath = $env:Path
$buildAndroidRoot = $androidRoot
$buildLoveAndroidRoot = $loveAndroidRoot
$substDrive = $null
if ($outputRoot -match '\s') {
    foreach ($candidate in @('M:','N:','O:','P:')) {
        if (-not (Test-Path ($candidate + '\'))) {
            & subst.exe $candidate $outputRoot
            if ($LASTEXITCODE -eq 0) { $substDrive = $candidate; break }
        }
    }
    if (-not $substDrive) { throw 'Could not allocate a temporary no-space drive for the Android NDK build' }
    $buildAndroidRoot = $substDrive + '\tooling\android-sdk'
    $buildLoveAndroidRoot = $substDrive + '\love-android'
}
try {
    $env:JAVA_HOME = $javaHome
    $env:ANDROID_HOME = $buildAndroidRoot
    $env:ANDROID_SDK_ROOT = $buildAndroidRoot
    $env:Path = (Join-Path $javaHome 'bin') + ';' + $env:Path

    Write-Output 'Installing the pinned Android SDK components...'
    1..100 | ForEach-Object { 'y' } | & $sdkManager --sdk_root=$buildAndroidRoot --licenses | Out-Null
    & $sdkManager --sdk_root=$buildAndroidRoot 'platform-tools' 'platforms;android-34' 'build-tools;34.0.0' 'ndk;25.2.9519653'
    if ($LASTEXITCODE -ne 0) { throw "Android SDK setup failed with exit code $LASTEXITCODE" }

    if (-not (Test-Path -LiteralPath (Join-Path $loveAndroidRoot 'gradlew.bat'))) {
        $git = (Get-Command git -ErrorAction Stop).Source
        & $git clone --recurse-submodules --depth 1 --branch $config.loveVersion https://github.com/love2d/love-android.git $loveAndroidRoot
        if ($LASTEXITCODE -ne 0) { throw "LÖVE Android checkout failed with exit code $LASTEXITCODE" }
    }

    # SDL 2 can replace the manifest's landscape lock with FULL_SENSOR during
    # startup on recent Android releases. Keep this patch local to the Android
    # wrapper so the shared desktop game stays resizable.
    $gameActivityPath = Join-Path $loveAndroidRoot 'love\src\main\java\org\love2d\android\GameActivity.java'
    # Windows PowerShell 5 decodes Get-Content with the active ANSI code page.
    # GameActivity contains the word "LÖVE", so repeated build-and-rewrite
    # cycles otherwise expand that text into mojibake until javac rejects the
    # oversized string constant. Keep this boundary explicitly UTF-8.
    $gameActivity = [System.IO.File]::ReadAllText($gameActivityPath,[System.Text.Encoding]::UTF8)
    if ($gameActivity -notmatch 'MOUSE_FRONTIER_LANDSCAPE_LOCK') {
        $landscapeOverride = @'
public class GameActivity extends SDLActivity {
    // MOUSE_FRONTIER_LANDSCAPE_LOCK
    @Override
    public void setOrientationBis(int width, int height, boolean resizable, String hint) {
        setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }
'@
        $gameActivity = $gameActivity.Replace('public class GameActivity extends SDLActivity {',$landscapeOverride.TrimEnd())
    }
    if ($gameActivity -notmatch 'MOUSE_FRONTIER_EMBEDDED_GAME') {
        $embedInitialization = @'
        embed = getResources().getBoolean(R.bool.embed);
        // MOUSE_FRONTIER_EMBEDDED_GAME
        // LÖVE Android 11.5 does not initialize this flag for embed builds,
        // leaving assets/game.love present but never mounted.
        if (embed) {
            needToCopyGameInArchive = true;
        }
'@
        $gameActivity = $gameActivity.Replace('        embed = getResources().getBoolean(R.bool.embed);',$embedInitialization.TrimEnd())
    }
    if ($gameActivity -notmatch 'MOUSE_FRONTIER_GAME_CACHE') {
        $cacheGuard = @'
    private void copyGameInsideArchive() {
        // MOUSE_FRONTIER_GAME_CACHE
        // Reuse the extracted archive until a newer APK is installed.
        File cachedGame = new File(this.getCacheDir(), "game.love");
        File installedApk = new File(this.getApplicationInfo().sourceDir);
        if (cachedGame.isFile() && cachedGame.length() > 0 && cachedGame.lastModified() >= installedApk.lastModified()) {
            gamePath = cachedGame.getPath();
            storagePermissionUnnecessary = true;
            Log.d("GameActivity", "Reusing cached embedded game: " + gamePath);
            return;
        }
'@
        $gameActivity = $gameActivity.Replace('    private void copyGameInsideArchive() {',$cacheGuard.TrimEnd())
    }
    foreach ($requiredMarker in @('MOUSE_FRONTIER_LANDSCAPE_LOCK','MOUSE_FRONTIER_EMBEDDED_GAME','MOUSE_FRONTIER_GAME_CACHE')) {
        if ($gameActivity -notmatch $requiredMarker) { throw "Unable to apply Android wrapper patch: $requiredMarker" }
    }
    [System.IO.File]::WriteAllText($gameActivityPath,$gameActivity,[System.Text.UTF8Encoding]::new($false))

    $embedAssets = Join-Path $loveAndroidRoot 'app\src\embed\assets'
    New-Item -ItemType Directory -Force -Path $embedAssets | Out-Null
    Copy-Item -LiteralPath $resolvedPackage -Destination (Join-Path $embedAssets 'game.love') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'mobile\android\AndroidManifest.xml') -Destination (Join-Path $loveAndroidRoot 'app\src\embed\AndroidManifest.xml') -Force
    $androidResources = Join-Path $outputRoot 'android-res'
    if (Test-Path -LiteralPath $androidResources) {
        Copy-Item -Path (Join-Path $androidResources '*') -Destination (Join-Path $loveAndroidRoot 'app\src\main\res') -Recurse -Force
    }

    $propertiesPath = Join-Path $loveAndroidRoot 'gradle.properties'
    $properties = Get-Content -Raw $propertiesPath
    $properties = $properties -replace '(?m)^app\.name_byte_array=.*$',('#app.name_byte_array=disabled-for-mouse-frontier')
    if ($properties -match '(?m)^#?app\.name=.*$') { $properties = $properties -replace '(?m)^#?app\.name=.*$',("app.name=" + $config.applicationName) }
    else { $properties = "app.name=$($config.applicationName)`r`n" + $properties }
    $properties = $properties -replace '(?m)^app\.application_id=.*$',("app.application_id=" + $config.applicationId)
    $properties = $properties -replace '(?m)^app\.orientation=.*$','app.orientation=landscape'
    $properties = $properties -replace '(?m)^app\.version_code=.*$',("app.version_code=" + $config.versionCode)
    $properties = $properties -replace '(?m)^app\.version_name=.*$',("app.version_name=" + $config.versionName)
    if ($properties -notmatch '(?m)^org\.gradle\.jvmargs=') { $properties += "`r`norg.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8`r`n" }
    [System.IO.File]::WriteAllText($propertiesPath,$properties,[System.Text.UTF8Encoding]::new($false))

    $appBuildPath = Join-Path $loveAndroidRoot 'app\build.gradle'
    $appBuild = Get-Content -Raw $appBuildPath
    if ($appBuild -notmatch "noCompress 'love'") {
        $appBuild = $appBuild -replace "android \{","android {`r`n    aaptOptions { noCompress 'love' }"
        [System.IO.File]::WriteAllText($appBuildPath,$appBuild,[System.Text.UTF8Encoding]::new($false))
    }

    # Gradle's native cache stores absolute paths to the temporary SUBST drive.
    # Another Android project can occupy that letter between builds, so discard
    # only this checkout's generated CXX metadata when the drive has changed.
    $nativeCacheRoot = Join-Path $loveAndroidRoot 'love\build\.cxx'
    if (Test-Path -LiteralPath $nativeCacheRoot) {
        $expectedAndroidMk = Join-Path $buildLoveAndroidRoot 'love\src\jni\Android.mk'
        $cachedBuildFiles = @(Get-ChildItem -LiteralPath $nativeCacheRoot -Recurse -Filter 'build_file_index.txt' -File -ErrorAction SilentlyContinue)
        $staleNativeCache = $cachedBuildFiles | Where-Object {
            $recordedBuildFiles = @(Get-Content -LiteralPath $_.FullName -ErrorAction SilentlyContinue)
            $recordedBuildFiles.Count -gt 0 -and $recordedBuildFiles -notcontains $expectedAndroidMk
        } | Select-Object -First 1
        if ($staleNativeCache) {
            $resolvedNativeCache = [System.IO.Path]::GetFullPath($nativeCacheRoot)
            $resolvedLoveRoot = [System.IO.Path]::GetFullPath($loveAndroidRoot).TrimEnd('\') + '\'
            if (-not $resolvedNativeCache.StartsWith($resolvedLoveRoot,[System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to clear native cache outside the Android checkout: $resolvedNativeCache"
            }
            Write-Output 'Invalidating native cache tied to a previous temporary build drive...'
            Remove-Item -LiteralPath $resolvedNativeCache -Recurse -Force
        }
    }

    Write-Output 'Building the installable Android APK...'
    # Clean only the app packaging outputs. This avoids stale ZIP alignment gaps
    # when game.love changes while preserving the expensive native engine cache.
    & (Join-Path $buildLoveAndroidRoot 'gradlew.bat') --project-dir $buildLoveAndroidRoot --no-daemon :app:clean assembleEmbedNoRecordDebug
    if ($LASTEXITCODE -ne 0) { throw "Android APK build failed with exit code $LASTEXITCODE" }

    $builtApk = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\outputs\apk') -Recurse -Filter '*embed-noRecord-debug*.apk' | Select-Object -First 1
    if (-not $builtApk) { $builtApk = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\outputs\apk') -Recurse -Filter '*.apk' | Select-Object -First 1 }
    if (-not $builtApk) { throw 'Gradle completed without producing an APK' }
    $apkPath = Join-Path $outputRoot ("MouseFrontier-" + $config.versionName + "-debug.apk")
    Copy-Item -LiteralPath $builtApk.FullName -Destination $apkPath -Force

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $apkArchive = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
    try {
        $embeddedGame = $apkArchive.GetEntry('assets/game.love')
        if (-not $embeddedGame) { throw 'APK is missing assets/game.love' }
        $packageBytes = (Get-Item -LiteralPath $resolvedPackage).Length
        if ($embeddedGame.Length -ne $packageBytes) {
            throw "Embedded game size mismatch: expected $packageBytes, found $($embeddedGame.Length)"
        }
        $embeddedStream = $embeddedGame.Open()
        try { $embeddedGameSha = Get-StreamSha256 $embeddedStream }
        finally { $embeddedStream.Dispose() }
        if ($embeddedGameSha -ne $packageSha) { throw 'APK contains a different game archive; SHA-256 verification failed' }
        $verifiedAbis = @('arm64-v8a','armeabi-v7a','x86_64')
        foreach ($abi in $verifiedAbis) {
            if (-not $apkArchive.GetEntry("lib/$abi/liblove.so")) { throw "APK is missing its $abi engine" }
        }
    }
    finally { $apkArchive.Dispose() }

    $aapt = Join-Path $androidRoot 'build-tools\34.0.0\aapt.exe'
    $badging = (& $aapt dump badging $apkPath | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect Android APK identity' }
    $expectedIdentity = "package: name='$($config.applicationId)' versionCode='$($config.versionCode)' versionName='$($config.versionName)'"
    if (-not $badging.Contains($expectedIdentity)) { throw 'Android APK identity/version differs from mobile/config.json' }

    $apksigner = Join-Path $androidRoot 'build-tools\34.0.0\apksigner.bat'
    & $apksigner verify --verbose $apkPath
    if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed with exit code $LASTEXITCODE" }

    $adb = Join-Path $androidRoot 'platform-tools\adb.exe'
    $devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" })
    $deviceLaunchVerified = $false
    if ($Install) {
        if ($devices.Count -ne 1) { throw "Expected one connected Android device, found $($devices.Count)" }
        $deviceSerial = ($devices[0] -split '\s+')[0]
        & $adb -s $deviceSerial install -r $apkPath
        if ($LASTEXITCODE -ne 0) { throw "APK installation failed with exit code $LASTEXITCODE" }
        & $adb -s $deviceSerial shell am force-stop $config.applicationId
        # A fresh process gives us scoped startup logs without clearing the
        # device-wide logs belonging to other applications.
        & $adb -s $deviceSerial shell am start -W -n "$($config.applicationId)/org.love2d.android.GameActivity"
        if ($LASTEXITCODE -ne 0) { throw 'Installed APK did not launch' }
        for ($attempt=1; $attempt -le 30; $attempt++) {
            $devicePid = (& $adb -s $deviceSerial shell pidof $config.applicationId | Out-String).Trim()
            if ($devicePid) {
                $deviceLog = (& $adb -s $deviceSerial logcat -d --pid=$devicePid -v brief | Out-String)
                if ($deviceLog -match '\[LOVE\].*\[AUDIO\] Registered') { $deviceLaunchVerified = $true; break }
                if ($deviceLog -match 'FATAL EXCEPTION|stack traceback|Lua error') { throw 'Installed APK reported a startup error' }
            }
            Start-Sleep -Seconds 1
        }
        if (-not $deviceLaunchVerified) { throw 'Installed APK did not reach the Mouse Frontier startup marker within 30 seconds' }
    }
    $apkReport = [ordered]@{
        applicationId = $config.applicationId
        versionName = $config.versionName
        versionCode = $config.versionCode
        apk = $apkPath
        apkBytes = (Get-Item -LiteralPath $apkPath).Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash.ToLowerInvariant()
        signed = $true
        identityVerified = $true
        verifiedAbis = $verifiedAbis
        sourceCommit = $packageManifest.sourceCommit
        sourceDirty = $packageManifest.sourceDirty
        embeddedGameBytes = $packageBytes
        embeddedGameSha256 = $embeddedGameSha
        connectedAndroidDevices = $devices.Count
        deviceLaunchVerified = $deviceLaunchVerified
    }
    [System.IO.File]::WriteAllText((Join-Path $outputRoot 'apk-report.json'),($apkReport | ConvertTo-Json) + "`n",[System.Text.UTF8Encoding]::new($false))
    Write-Output "ANDROID_APK=$apkPath"
    Write-Output "CONNECTED_ANDROID_DEVICES=$($devices.Count)"
}
finally {
    $env:JAVA_HOME = $previousJavaHome
    $env:ANDROID_HOME = $previousAndroidHome
    $env:ANDROID_SDK_ROOT = $previousAndroidSdkRoot
    $env:Path = $previousPath
    if ($substDrive) { & subst.exe $substDrive /D | Out-Null }
}
