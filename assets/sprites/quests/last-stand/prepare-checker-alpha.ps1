param(
    [string]$AssetDirectory = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

$drawingAssembly = [System.Drawing.Bitmap].Assembly.Location
$drawingReferences = @($drawingAssembly)
[System.Drawing.Bitmap].Assembly.GetReferencedAssemblies() | ForEach-Object {
    try {
        $dependency = [System.Reflection.Assembly]::Load($_)
        if ($dependency.Location) {
            $drawingReferences += $dependency.Location
        }
    }
    catch {
        # Add-Type will report any dependency that is genuinely required below.
    }
}
Add-Type -ReferencedAssemblies ($drawingReferences | Select-Object -Unique) -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public sealed class AlphaConversionResult
{
    public int Width;
    public int Height;
    public int TransparentPixels;
    public int OpaquePixels;
}

public static class CheckerAlphaConverter
{
    private static bool IsCheckerPixel(byte red, byte green, byte blue)
    {
        int high = Math.Max(red, Math.Max(green, blue));
        int low = Math.Min(red, Math.Min(green, blue));
        int average = (red + green + blue) / 3;

        return average >= 150 && high - low <= 12;
    }

    public static AlphaConversionResult Convert(
        string sourcePath,
        string destinationPath,
        int enclosedAreaThreshold)
    {
        if (!File.Exists(sourcePath))
            throw new FileNotFoundException("Source asset was not found.", sourcePath);
        if (File.Exists(destinationPath))
            throw new IOException("Refusing to overwrite an existing prepared asset: " + destinationPath);

        using (Bitmap source = new Bitmap(sourcePath))
        using (Bitmap bitmap = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            using (Graphics graphics = Graphics.FromImage(bitmap))
                graphics.DrawImageUnscaled(source, 0, 0);

            int width = bitmap.Width;
            int height = bitmap.Height;
            int pixelCount = checked(width * height);
            Rectangle bounds = new Rectangle(0, 0, width, height);
            BitmapData data = bitmap.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int byteCount = Math.Abs(data.Stride) * height;
            byte[] bytes = new byte[byteCount];
            Marshal.Copy(data.Scan0, bytes, 0, byteCount);

            bool[] checker = new bool[pixelCount];
            bool[] transparent = new bool[pixelCount];
            for (int y = 0; y < height; y++)
            {
                int row = y * data.Stride;
                for (int x = 0; x < width; x++)
                {
                    int offset = row + x * 4;
                    int index = y * width + x;
                    checker[index] = IsCheckerPixel(bytes[offset + 2], bytes[offset + 1], bytes[offset]);
                }
            }

            int[] queue = new int[pixelCount];
            int head = 0;
            int tail = 0;

            for (int x = 0; x < width; x++)
            {
                Enqueue(x, checker, transparent, queue, ref tail);
                Enqueue((height - 1) * width + x, checker, transparent, queue, ref tail);
            }
            for (int y = 0; y < height; y++)
            {
                Enqueue(y * width, checker, transparent, queue, ref tail);
                Enqueue(y * width + width - 1, checker, transparent, queue, ref tail);
            }

            Flood(queue, ref head, ref tail, checker, transparent, width, height);

            if (enclosedAreaThreshold > 0)
            {
                bool[] visited = new bool[pixelCount];

                for (int start = 0; start < pixelCount; start++)
                {
                    if (!checker[start] || transparent[start] || visited[start])
                        continue;

                    head = 0;
                    tail = 0;
                    visited[start] = true;
                    queue[tail++] = start;

                    while (head < tail)
                    {
                        int current = queue[head++];
                        int x = current % width;
                        int y = current / width;

                        Visit(current - 1, x > 0, checker, transparent, visited, queue, ref tail);
                        Visit(current + 1, x + 1 < width, checker, transparent, visited, queue, ref tail);
                        Visit(current - width, y > 0, checker, transparent, visited, queue, ref tail);
                        Visit(current + width, y + 1 < height, checker, transparent, visited, queue, ref tail);
                    }

                    if (tail >= enclosedAreaThreshold)
                    {
                        for (int i = 0; i < tail; i++)
                            transparent[queue[i]] = true;
                    }
                }
            }

            int transparentCount = 0;
            for (int y = 0; y < height; y++)
            {
                int row = y * data.Stride;
                for (int x = 0; x < width; x++)
                {
                    int offset = row + x * 4;
                    int index = y * width + x;
                    if (transparent[index])
                    {
                        bytes[offset] = 0;
                        bytes[offset + 1] = 0;
                        bytes[offset + 2] = 0;
                        bytes[offset + 3] = 0;
                        transparentCount++;
                    }
                    else
                    {
                        bytes[offset + 3] = 255;
                    }
                }
            }

            Marshal.Copy(bytes, 0, data.Scan0, byteCount);
            bitmap.UnlockBits(data);
            bitmap.Save(destinationPath, ImageFormat.Png);

            return new AlphaConversionResult
            {
                Width = width,
                Height = height,
                TransparentPixels = transparentCount,
                OpaquePixels = pixelCount - transparentCount
            };
        }
    }

    private static void Flood(
        int[] queue,
        ref int head,
        ref int tail,
        bool[] checker,
        bool[] transparent,
        int width,
        int height)
    {
        while (head < tail)
        {
            int current = queue[head++];
            int x = current % width;
            int y = current / width;

            if (x > 0)
                Enqueue(current - 1, checker, transparent, queue, ref tail);
            if (x + 1 < width)
                Enqueue(current + 1, checker, transparent, queue, ref tail);
            if (y > 0)
                Enqueue(current - width, checker, transparent, queue, ref tail);
            if (y + 1 < height)
                Enqueue(current + width, checker, transparent, queue, ref tail);
        }
    }

    private static void Enqueue(
        int index,
        bool[] checker,
        bool[] transparent,
        int[] queue,
        ref int tail)
    {
        if (checker[index] && !transparent[index])
        {
            transparent[index] = true;
            queue[tail++] = index;
        }
    }

    private static void Visit(
        int index,
        bool inBounds,
        bool[] checker,
        bool[] transparent,
        bool[] visited,
        int[] queue,
        ref int tail)
    {
        if (inBounds && checker[index] && !transparent[index] && !visited[index])
        {
            visited[index] = true;
            queue[tail++] = index;
        }
    }
}
'@

$assets = @(
    @{ Source = "friendly-house-backyard-shell-candidate-v1.png"; Output = "friendly-house-backyard-shell-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "friendly-house-interior-shell-candidate-v1.png"; Output = "friendly-house-interior-shell-alpha-candidate-v1.png"; Interior = 2000 },
    @{ Source = "rail-relay-facade-cutout-candidate-v1.png"; Output = "rail-relay-facade-cutout-alpha-candidate-v1.png"; Interior = 600 },
    @{ Source = "house-firing-window-frames-candidate-v1.png"; Output = "house-firing-window-frames-alpha-candidate-v1.png"; Interior = 2000 },
    @{ Source = "shootout-effects-atlas-candidate-v1.png"; Output = "shootout-effects-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "mouse-bandit-rifle-target-atlas-candidate-v1.png"; Output = "mouse-bandit-rifle-target-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "cowboy-mouse-rifle-target-atlas-candidate-v1.png"; Output = "cowboy-mouse-rifle-target-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Sourceolders = "" }
)

# Add the remaining entries separately to keep the table easy to audit.
$assets = @(
    @{ Source = "friendly-house-backyard-shell-candidate-v1.png"; Output = "friendly-house-backyard-shell-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "friendly-house-interior-shell-candidate-v1.png"; Output = "friendly-house-interior-shell-alpha-candidate-v1.png"; Interior = 2000 },
    @{ Source = "rail-relay-facade-cutout-candidate-v1.png"; Output = "rail-relay-facade-cutout-alpha-candidate-v1.png"; Interior = 600 },
    @{ Source = "house-firing-window-frames-candidate-v1.png"; Output = "house-firing-window-frames-alpha-candidate-v1.png"; Interior = 2000 },
    @{ Source = "shootout-effects-atlas-candidate-v1.png"; Output = "shootout-effects-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "mouse-bandit-rifle-target-atlas-candidate-v1.png"; Output = "mouse-bandit-rifle-target-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "cowboy-mouse-rifle-target-atlas-candidate-v1.png"; Output = "cowboy-mouse-rifle-target-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "tunnel-badger-rifle-target-atlas-candidate-v1.png"; Output = "tunnel-badger-rifle-target-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "guard-fox-rifle-action-atlas-candidate-v1.png"; Output = "guard-fox-rifle-action-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "gecko-ranger-pistol-action-atlas-candidate-v1.png"; Output = "gecko-ranger-pistol-action-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "otter-scout-support-action-atlas-candidate-v1.png"; Output = "otter-scout-support-action-atlas-alpha-candidate-v1.png"; Interior = 0 },
    @{ Source = "otter-scout-approach-walk-candidate-v1.png"; Output = "otter-scout-approach-walk-alpha-candidate-v1.png"; Interior = 0 }
)

foreach ($asset in $assets) {
    $sourcePath = Join-Path $AssetDirectory $asset.Source
    $outputPath = Join-Path $AssetDirectory $asset.Output
    $result = [CheckerAlphaConverter]::Convert($sourcePath, $outputPath, $asset.Interior)

    [pscustomobject]@{
        Asset = $asset.Output
        Size = "{0}x{1}" -f $result.Width, $result.Height
        TransparentPixels = $result.TransparentPixels
        OpaquePixels = $result.OpaquePixels
    }
}
