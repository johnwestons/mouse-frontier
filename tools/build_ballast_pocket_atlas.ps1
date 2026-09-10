param(
    [string]$TrackPath = "assets/sprites/tracks/railway-track-v2.png",
    [string]$MaskPath = "assets/sprites/tracks/railway-ballast-pocket-mask-v1.png",
    [string]$OutputPath = "assets/sprites/tracks/railway-ballast-pocket-run-4-v1.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$track = [System.Drawing.Bitmap]::new((Resolve-Path -LiteralPath $TrackPath).Path)
$mask = [System.Drawing.Bitmap]::new((Resolve-Path -LiteralPath $MaskPath).Path)
try {
    if ($track.Width -ne $mask.Width -or $track.Height -ne $mask.Height) {
        throw "Track and ballast mask dimensions must match."
    }

    $frameCount = 4
    $atlas = [System.Drawing.Bitmap]::new(
        $track.Width,
        $track.Height * $frameCount,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($atlas)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
        }
        finally {
            $graphics.Dispose()
        }

        # Each frame uses the exact same strong-alpha pocket mask. Variations
        # replace only small internal source-pixel clusters; no sprite position,
        # scale, outline, or baseline can change between frames.
        $offsets = @(
            @(0, 0),
            @(1, 0),
            @(0, -1),
            @(-1, 1)
        )

        for ($frame = 0; $frame -lt $frameCount; $frame++) {
            $dx = $offsets[$frame][0]
            $dy = $offsets[$frame][1]
            for ($y = 0; $y -lt $track.Height; $y++) {
                for ($x = 0; $x -lt $track.Width; $x++) {
                    if ($mask.GetPixel($x, $y).A -lt 192) { continue }

                    $sampleX = $x
                    $sampleY = $y
                    if ($frame -gt 0) {
                        $cellX = [math]::Floor($x / 6)
                        $cellY = [math]::Floor($y / 6)
                        $selected = (($cellX * 37 + $cellY * 19 + $frame * 23) % 13) -eq 0
                        $candidateX = $x + $dx
                        $candidateY = $y + $dy
                        if ($selected -and $candidateX -ge 0 -and $candidateX -lt $track.Width `
                            -and $candidateY -ge 0 -and $candidateY -lt $track.Height `
                            -and $mask.GetPixel($candidateX, $candidateY).A -ge 192) {
                            $sampleX = $candidateX
                            $sampleY = $candidateY
                        }
                    }

                    $source = $track.GetPixel($sampleX, $sampleY)
                    $pixel = [System.Drawing.Color]::FromArgb(255, $source.R, $source.G, $source.B)
                    $atlas.SetPixel($x, $frame * $track.Height + $y, $pixel)
                }
            }
        }

        $outputDirectory = Split-Path -Parent $OutputPath
        if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory | Out-Null
        }
        $atlas.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $atlas.Dispose()
    }
}
finally {
    $track.Dispose()
    $mask.Dispose()
}

Write-Output "Built four anchored ballast frames at $OutputPath"
