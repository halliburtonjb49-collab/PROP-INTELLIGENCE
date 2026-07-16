param(
    [string]$Source = "assets\branding\prop_intelligence_icon.png"
)

Add-Type -AssemblyName System.Drawing

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)

function Write-IconPng {
    param(
        [string]$Path,
        [int]$Size
    )

    $fullPath = [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location) $Path)
    )
    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode =
                [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode =
                [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode =
                [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($sourceImage, 0, 0, $Size, $Size)
        }
        finally {
            $graphics.Dispose()
        }
        $bitmap.Save(
            $fullPath,
            [System.Drawing.Imaging.ImageFormat]::Png
        )
    }
    finally {
        $bitmap.Dispose()
    }
}

try {
    $androidIcons = @{
        "android\app\src\main\res\mipmap-mdpi\ic_launcher.png" = 48
        "android\app\src\main\res\mipmap-hdpi\ic_launcher.png" = 72
        "android\app\src\main\res\mipmap-xhdpi\ic_launcher.png" = 96
        "android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png" = 144
        "android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png" = 192
    }
    foreach ($entry in $androidIcons.GetEnumerator()) {
        Write-IconPng -Path $entry.Key -Size $entry.Value
    }

    $iosIcons = @{
        "Icon-App-20x20@1x.png" = 20
        "Icon-App-20x20@2x.png" = 40
        "Icon-App-20x20@3x.png" = 60
        "Icon-App-29x29@1x.png" = 29
        "Icon-App-29x29@2x.png" = 58
        "Icon-App-29x29@3x.png" = 87
        "Icon-App-40x40@1x.png" = 40
        "Icon-App-40x40@2x.png" = 80
        "Icon-App-40x40@3x.png" = 120
        "Icon-App-60x60@2x.png" = 120
        "Icon-App-60x60@3x.png" = 180
        "Icon-App-76x76@1x.png" = 76
        "Icon-App-76x76@2x.png" = 152
        "Icon-App-83.5x83.5@2x.png" = 167
        "Icon-App-1024x1024@1x.png" = 1024
    }
    foreach ($entry in $iosIcons.GetEnumerator()) {
        Write-IconPng `
            -Path ("ios\Runner\Assets.xcassets\AppIcon.appiconset\" + $entry.Key) `
            -Size $entry.Value
    }

    foreach ($size in 16, 32, 64, 128, 256, 512, 1024) {
        Write-IconPng `
            -Path "macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_$size.png" `
            -Size $size
    }

    Write-IconPng -Path "web\icons\Icon-192.png" -Size 192
    Write-IconPng -Path "web\icons\Icon-512.png" -Size 512
    Write-IconPng -Path "web\icons\Icon-maskable-192.png" -Size 192
    Write-IconPng -Path "web\icons\Icon-maskable-512.png" -Size 512
}
finally {
    $sourceImage.Dispose()
}

Write-Output "Updated Android, iOS, macOS, and web icons."
