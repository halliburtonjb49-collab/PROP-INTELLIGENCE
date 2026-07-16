param(
    [string]$Source = "assets\branding\prop_intelligence_icon.png",
    [string]$Destination = "windows\runner\resources\app_icon.ico"
)

Add-Type -AssemblyName System.Drawing

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$destinationPath = [System.IO.Path]::GetFullPath(
    (Join-Path (Get-Location) $Destination)
)
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)

try {
    $bitmap = New-Object System.Drawing.Bitmap 256, 256
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode =
                [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode =
                [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode =
                [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($sourceImage, 0, 0, 256, 256)
        }
        finally {
            $graphics.Dispose()
        }

        $pngStream = New-Object System.IO.MemoryStream
        try {
            $bitmap.Save(
                $pngStream,
                [System.Drawing.Imaging.ImageFormat]::Png
            )
            $pngBytes = $pngStream.ToArray()
        }
        finally {
            $pngStream.Dispose()
        }

        $fileStream = [System.IO.File]::Create($destinationPath)
        try {
            $writer = New-Object System.IO.BinaryWriter $fileStream
            try {
                $writer.Write([UInt16]0)
                $writer.Write([UInt16]1)
                $writer.Write([UInt16]1)
                $writer.Write([Byte]0)
                $writer.Write([Byte]0)
                $writer.Write([Byte]0)
                $writer.Write([Byte]0)
                $writer.Write([UInt16]1)
                $writer.Write([UInt16]32)
                $writer.Write([UInt32]$pngBytes.Length)
                $writer.Write([UInt32]22)
                $writer.Write($pngBytes)
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            $fileStream.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}
finally {
    $sourceImage.Dispose()
}

Write-Output "Updated Windows icon: $destinationPath"
