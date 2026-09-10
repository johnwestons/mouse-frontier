param(
    [string]$AssetRoot = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$runtimeRoot = Join-Path $AssetRoot "runtime"
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null

function New-TransparentBitmap {
    param(
        [int]$Width,
        [int]$Height
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $Width,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $bitmap.SetResolution(96, 96)
    return $bitmap
}

function Set-RenderQuality {
    param([System.Drawing.Graphics]$Graphics)

    $Graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
}

function Resize-Atlas {
    param(
        [string]$SourceName,
        [string]$OutputName,
        [int]$Width,
        [int]$Height
    )

    $sourcePath = Join-Path $AssetRoot $SourceName
    $outputPath = Join-Path $runtimeRoot $OutputName
    $source = [System.Drawing.Bitmap]::FromFile($sourcePath)
    $target = New-TransparentBitmap -Width $Width -Height $Height
    $graphics = [System.Drawing.Graphics]::FromImage($target)

    try {
        Set-RenderQuality -Graphics $graphics
        $destination = [System.Drawing.Rectangle]::new(0, 0, $Width, $Height)
        $graphics.DrawImage($source, $destination)
        $target.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $target.Dispose()
        $source.Dispose()
    }
}

function Repack-EightFrameStrip {
    param(
        [string]$SourceName,
        [string]$OutputName,
        [single]$CropTop
    )

    $sourcePath = Join-Path $AssetRoot $SourceName
    $outputPath = Join-Path $runtimeRoot $OutputName
    $source = [System.Drawing.Bitmap]::FromFile($sourcePath)
    $target = New-TransparentBitmap -Width 2560 -Height 512
    $graphics = [System.Drawing.Graphics]::FromImage($target)

    try {
        Set-RenderQuality -Graphics $graphics
        $sourceFrameWidth = [single]($source.Width / 8.0)
        $sourceFrameHeight = [single]($sourceFrameWidth * 1.6)

        for ($frame = 0; $frame -lt 8; $frame++) {
            $sourceRect = [System.Drawing.RectangleF]::new(
                [single]($frame * $sourceFrameWidth),
                $CropTop,
                $sourceFrameWidth,
                $sourceFrameHeight
            )
            $destinationRect = [System.Drawing.RectangleF]::new(
                [single]($frame * 320),
                0,
                320,
                512
            )
            $graphics.DrawImage(
                $source,
                $destinationRect,
                $sourceRect,
                [System.Drawing.GraphicsUnit]::Pixel
            )
        }

        $target.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $target.Dispose()
        $source.Dispose()
    }
}

function Split-WindowFrames {
    param([string]$SourceName)

    $sourcePath = Join-Path $AssetRoot $SourceName
    $source = [System.Drawing.Bitmap]::FromFile($sourcePath)

    try {
        $frameWidth = [int]($source.Width / 2)
        $outputs = @(
            @{ Name = "house-firing-window-wide.png"; X = 0 },
            @{ Name = "house-firing-window-tall.png"; X = $frameWidth }
        )

        foreach ($output in $outputs) {
            $target = New-TransparentBitmap -Width $frameWidth -Height $source.Height
            $graphics = [System.Drawing.Graphics]::FromImage($target)
            try {
                Set-RenderQuality -Graphics $graphics
                $destinationRect = [System.Drawing.Rectangle]::new(0, 0, $frameWidth, $source.Height)
                $sourceRect = [System.Drawing.Rectangle]::new(
                    [int]$output.X,
                    0,
                    $frameWidth,
                    $source.Height
                )
                $graphics.DrawImage(
                    $source,
                    $destinationRect,
                    $sourceRect,
                    [System.Drawing.GraphicsUnit]::Pixel
                )
                $target.Save(
                    (Join-Path $runtimeRoot $output.Name),
                    [System.Drawing.Imaging.ImageFormat]::Png
                )
            }
            finally {
                $graphics.Dispose()
                $target.Dispose()
            }
        }
    }
    finally {
        $source.Dispose()
    }
}

$sceneCopies = [ordered]@{
    "friendly-house-backyard-shell-alpha-candidate-v4.png" = "friendly-house-backyard-shell.png"
    "friendly-house-interior-shell-alpha-candidate-v4.png" = "friendly-house-interior-shell.png"
    "rail-relay-facade-cutout-alpha-candidate-v4.png" = "rail-relay-facade-cutout.png"
}

foreach ($copy in $sceneCopies.GetEnumerator()) {
    Copy-Item -LiteralPath (Join-Path $AssetRoot $copy.Key) -Destination (Join-Path $runtimeRoot $copy.Value) -Force
}

$gridAtlases = @(
    @{ Source = "shootout-effects-atlas-alpha-candidate-v4.png"; Output = "shootout-effects-atlas.png" },
    @{ Source = "mouse-bandit-rifle-target-atlas-alpha-candidate-v4.png"; Output = "mouse-bandit-rifle-target-atlas.png" },
    @{ Source = "cowboy-mouse-rifle-target-atlas-alpha-candidate-v4.png"; Output = "cowboy-mouse-rifle-target-atlas.png" },
    @{ Source = "tunnel-badger-rifle-target-atlas-alpha-candidate-v4.png"; Output = "tunnel-badger-rifle-target-atlas.png" },
    @{ Source = "guard-fox-rifle-action-atlas-alpha-candidate-v4.png"; Output = "guard-fox-rifle-action-atlas.png" },
    @{ Source = "gecko-ranger-pistol-action-atlas-alpha-candidate-v4.png"; Output = "gecko-ranger-pistol-action-atlas.png" },
    @{ Source = "otter-scout-support-action-atlas-alpha-candidate-v4.png"; Output = "otter-scout-support-action-atlas.png" },
    @{ Source = "house-surface-damage-decals-alpha-candidate-v3.png"; Output = "house-surface-damage-decals.png" },
    @{ Source = "domestic-siege-props-atlas-alpha-candidate-v3.png"; Output = "domestic-siege-props-atlas.png" }
)

foreach ($atlas in $gridAtlases) {
    Resize-Atlas -SourceName $atlas.Source -OutputName $atlas.Output -Width 2048 -Height 1024
}

Repack-EightFrameStrip `
    -SourceName "otter-scout-approach-walk-alpha-candidate-v4.png" `
    -OutputName "otter-scout-approach-walk.png" `
    -CropTop 165

Repack-EightFrameStrip `
    -SourceName "distant-dust-loop-alpha-candidate-v3.png" `
    -OutputName "distant-dust-loop.png" `
    -CropTop 50

Split-WindowFrames -SourceName "house-firing-window-frames-alpha-candidate-v4.png"

$manifest = [ordered]@{
    version = 1
    purpose = "Runtime-ready Last Stand quest art with transparent scene apertures and fixed atlas geometry."
    layerOrder = [ordered]@{
        viewBackground = 0
        distantBuilding = 10
        distantActors = 20
        distantEffects = 30
        atmosphere = 40
        windowFrame = 50
        playerWeapon = 60
        hud = 70
    }
    scenes = [ordered]@{
        backyard = [ordered]@{
            file = "friendly-house-backyard-shell.png"
            width = 1672
            height = 941
            charactersBakedIn = $false
        }
        interior = [ordered]@{
            file = "friendly-house-interior-shell.png"
            width = 1671
            height = 941
            transparentWindowCount = 2
            charactersBakedIn = $false
        }
        enemyRelay = [ordered]@{
            file = "rail-relay-facade-cutout.png"
            width = 2001
            height = 786
            transparentFiringApertures = $true
            charactersBakedIn = $false
        }
    }
    windows = @(
        [ordered]@{ id = "wide"; file = "house-firing-window-wide.png"; width = 887; height = 887 },
        [ordered]@{ id = "tall"; file = "house-firing-window-tall.png"; width = 887; height = 887 }
    )
    atlasDefaults = [ordered]@{
        grid4x2 = [ordered]@{
            width = 2048
            height = 1024
            columns = 4
            rows = 2
            frameWidth = 512
            frameHeight = 512
            frameCount = 8
        }
        strip8x1 = [ordered]@{
            width = 2560
            height = 512
            columns = 8
            rows = 1
            frameWidth = 320
            frameHeight = 512
            frameCount = 8
        }
    }
    atlases = [ordered]@{
        mouseBandit = [ordered]@{ file = "mouse-bandit-rifle-target-atlas.png"; layout = "grid4x2"; pivot = @(256, 500); role = "hostile" }
        cowboyMouse = [ordered]@{ file = "cowboy-mouse-rifle-target-atlas.png"; layout = "grid4x2"; pivot = @(256, 500); role = "hostile" }
        tunnelBadger = [ordered]@{ file = "tunnel-badger-rifle-target-atlas.png"; layout = "grid4x2"; pivot = @(256, 500); role = "hostile" }
        guardFox = [ordered]@{ file = "guard-fox-rifle-action-atlas.png"; layout = "grid4x2"; pivot = @(256, 500); role = "friendly" }
        geckoRanger = [ordered]@{ file = "gecko-ranger-pistol-action-atlas.png"; layout = "grid4x2"; pivot = @(256, 500); role = "friendly" }
        otterSupport = [ordered]@{ file = "otter-scout-support-action-atlas.png"; layout = "grid4x2"; pivot = @(256, 500); role = "friendly" }
        otterApproach = [ordered]@{ file = "otter-scout-approach-walk.png"; layout = "strip8x1"; pivot = @(160, 496); fps = 10; loop = $true; role = "friendly" }
        distantDust = [ordered]@{ file = "distant-dust-loop.png"; layout = "strip8x1"; pivot = @(160, 448); fps = 8; loop = $true }
        effects = [ordered]@{ file = "shootout-effects-atlas.png"; layout = "grid4x2"; pivot = @(256, 256) }
        surfaceDamage = [ordered]@{ file = "house-surface-damage-decals.png"; layout = "grid4x2"; solidSurfaceOnly = $true }
        domesticProps = [ordered]@{ file = "domestic-siege-props-atlas.png"; layout = "grid4x2" }
    }
}

$manifestJson = $manifest | ConvertTo-Json -Depth 10
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    (Join-Path $runtimeRoot "last-stand-assets.json"),
    $manifestJson,
    $utf8WithoutBom
)

Get-ChildItem -LiteralPath $runtimeRoot -File |
    Sort-Object Name |
    Select-Object Name, Length
