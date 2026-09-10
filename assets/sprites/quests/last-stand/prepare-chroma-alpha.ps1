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
        # Add-Type reports any dependency that is actually required.
    }
}

Add-Type -ReferencedAssemblies ($drawingReferences | Select-Object -Unique) -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public sealed class ChromaAlphaResult
{
    public int Width;
    public int Height;
    public int TransparentPixels;
    public int OpaquePixels;
}

public static class ChromaAlphaConverter
{
    private static bool IsMagentaKey(byte red, byte green, byte blue)
    {
        int weakestKeyChannel = Math.Min(red, blue);
        int keySeparation = weakestKeyChannel - green;

        return weakestKeyChannel >= 120 && keySeparation >= 50;
    }

    private static bool IsMagentaSpill(byte red, byte green, byte blue)
    {
        int weakestKeyChannel = Math.Min(red, blue);
        int keySeparation = weakestKeyChannel - green;
        int keyBalance = Math.Abs(red - blue);

        return weakestKeyChannel >= 80
            && red + blue >= 240
            && keySeparation >= 12
            && keyBalance <= 100;
    }

    public static ChromaAlphaResult Convert(string sourcePath, string destinationPath)
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
            Rectangle bounds = new Rectangle(0, 0, width, height);
            BitmapData data = bitmap.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int byteCount = Math.Abs(data.Stride) * height;
            byte[] bytes = new byte[byteCount];
            Marshal.Copy(data.Scan0, bytes, 0, byteCount);

            int pixelCount = checked(width * height);
            bool[] transparent = new bool[pixelCount];
            byte[] distance = new byte[pixelCount];
            int[] queue = new int[pixelCount];
            int tail = 0;

            for (int y = 0; y < height; y++)
            {
                int row = y * data.Stride;
                for (int x = 0; x < width; x++)
                {
                    int offset = row + x * 4;
                    int index = y * width + x;
                    byte blue = bytes[offset];
                    byte green = bytes[offset + 1];
                    byte red = bytes[offset + 2];

                    if (IsMagentaKey(red, green, blue))
                    {
                        transparent[index] = true;
                        queue[tail++] = index;
                    }
                }
            }

            int head = 0;
            while (head < tail)
            {
                int current = queue[head++];
                int currentDistance = distance[current];
                if (currentDistance >= 3)
                    continue;

                int x = current % width;
                int y = current / width;
                byte nextDistance = (byte)(currentDistance + 1);

                if (x > 0)
                    ExpandSpill(current - 1, nextDistance, width, data.Stride, bytes, transparent, distance, queue, ref tail);
                if (x + 1 < width)
                    ExpandSpill(current + 1, nextDistance, width, data.Stride, bytes, transparent, distance, queue, ref tail);
                if (y > 0)
                    ExpandSpill(current - width, nextDistance, width, data.Stride, bytes, transparent, distance, queue, ref tail);
                if (y + 1 < height)
                    ExpandSpill(current + width, nextDistance, width, data.Stride, bytes, transparent, distance, queue, ref tail);
            }

            DespillOpaqueEdges(width, height, data.Stride, bytes, transparent);

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

            return new ChromaAlphaResult
            {
                Width = width,
                Height = height,
                TransparentPixels = transparentCount,
                OpaquePixels = pixelCount - transparentCount
            };
        }
    }

    private static void ExpandSpill(
        int index,
        byte nextDistance,
        int width,
        int stride,
        byte[] bytes,
        bool[] transparent,
        byte[] distance,
        int[] queue,
        ref int tail)
    {
        if (transparent[index])
            return;

        int x = index % width;
        int y = index / width;
        int offset = y * stride + x * 4;
        byte blue = bytes[offset];
        byte green = bytes[offset + 1];
        byte red = bytes[offset + 2];

        if (!IsMagentaSpill(red, green, blue))
            return;

        transparent[index] = true;
        distance[index] = nextDistance;
        queue[tail++] = index;
    }

    private static void DespillOpaqueEdges(
        int width,
        int height,
        int stride,
        byte[] bytes,
        bool[] transparent)
    {
        for (int y = 0; y < height; y++)
        {
            int row = y * stride;
            for (int x = 0; x < width; x++)
            {
                int index = y * width + x;
                if (transparent[index])
                    continue;

                bool touchesTransparency =
                    (x > 0 && transparent[index - 1])
                    || (x + 1 < width && transparent[index + 1])
                    || (y > 0 && transparent[index - width])
                    || (y + 1 < height && transparent[index + width]);

                if (!touchesTransparency)
                    continue;

                int offset = row + x * 4;
                int blue = bytes[offset];
                int green = bytes[offset + 1];
                int red = bytes[offset + 2];
                int magentaExcess = Math.Min(red, blue) - green;

                if (magentaExcess <= 3)
                    continue;

                bytes[offset] = (byte)Math.Max(green, blue - magentaExcess);
                bytes[offset + 2] = (byte)Math.Max(green, red - magentaExcess);
            }
        }
    }
}
'@

$assets = @(
    @{ Source = "friendly-house-backyard-shell-chroma-source-v2.png"; Output = "friendly-house-backyard-shell-alpha-candidate-v4.png" },
    @{ Source = "friendly-house-interior-shell-chroma-source-v2.png"; Output = "friendly-house-interior-shell-alpha-candidate-v4.png" },
    @{ Source = "rail-relay-facade-cutout-chroma-source-v2.png"; Output = "rail-relay-facade-cutout-alpha-candidate-v4.png" },
    @{ Source = "house-firing-window-frames-chroma-source-v2.png"; Output = "house-firing-window-frames-alpha-candidate-v4.png" },
    @{ Source = "shootout-effects-atlas-chroma-source-v2.png"; Output = "shootout-effects-atlas-alpha-candidate-v4.png" },
    @{ Source = "mouse-bandit-rifle-target-atlas-chroma-source-v2.png"; Output = "mouse-bandit-rifle-target-atlas-alpha-candidate-v4.png" },
    @{ Source = "cowboy-mouse-rifle-target-atlas-chroma-source-v2.png"; Output = "cowboy-mouse-rifle-target-atlas-alpha-candidate-v4.png" },
    @{ Source = "tunnel-badger-rifle-target-atlas-chroma-source-v2.png"; Output = "tunnel-badger-rifle-target-atlas-alpha-candidate-v4.png" },
    @{ Source = "guard-fox-rifle-action-atlas-chroma-source-v2.png"; Output = "guard-fox-rifle-action-atlas-alpha-candidate-v4.png" },
    @{ Source = "gecko-ranger-pistol-action-atlas-chroma-source-v2.png"; Output = "gecko-ranger-pistol-action-atlas-alpha-candidate-v4.png" },
    @{ Source = "otter-scout-support-action-atlas-chroma-source-v2.png"; Output = "otter-scout-support-action-atlas-alpha-candidate-v4.png" },
    @{ Source = "otter-scout-approach-walk-chroma-source-v2.png"; Output = "otter-scout-approach-walk-alpha-candidate-v4.png" },
    @{ Source = "house-surface-damage-decals-chroma-source-v1.png"; Output = "house-surface-damage-decals-alpha-candidate-v3.png" },
    @{ Source = "distant-dust-loop-chroma-source-v1.png"; Output = "distant-dust-loop-alpha-candidate-v3.png" },
    @{ Source = "domestic-siege-props-atlas-chroma-source-v1.png"; Output = "domestic-siege-props-atlas-alpha-candidate-v3.png" }
)

$results = foreach ($asset in $assets) {
    $sourcePath = Join-Path $AssetDirectory $asset.Source
    $destinationPath = Join-Path $AssetDirectory $asset.Output
    $result = [ChromaAlphaConverter]::Convert($sourcePath, $destinationPath)

    [pscustomobject]@{
        Asset = $asset.Output
        Size = "{0}x{1}" -f $result.Width, $result.Height
        TransparentPixels = $result.TransparentPixels
        OpaquePixels = $result.OpaquePixels
    }
}

$results | Format-Table -AutoSize
