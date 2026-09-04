$ErrorActionPreference = 'Stop'

$outputDirectory = Join-Path $PSScriptRoot '..\marketing_site\assets\ads'
$logoPath = Join-Path $PSScriptRoot '..\marketing_site\assets\pi-logo.png'
$ads = @(
    @{ Input = 'stop-guessing-vertical.png'; Output = 'stop-guessing-reel.mp4' },
    @{ Input = 'one-prop-20-seconds-vertical.png'; Output = 'one-prop-20-seconds-reel.mp4' },
    @{ Input = 'one-workspace-every-screen-vertical.png'; Output = 'one-workspace-every-screen-reel.mp4' }
)

foreach ($ad in $ads) {
    $inputPath = Join-Path $outputDirectory $ad.Input
    $outputPath = Join-Path $outputDirectory $ad.Output

    ffmpeg -loglevel error -y `
        -f lavfi -i "color=c=0x03131d:s=1080x1920:r=30:d=2" `
        -loop 1 -t 2 -i $logoPath `
        -loop 1 -t 13 -i $inputPath `
        -filter_complex `
        "[1:v]scale=430:430:force_original_aspect_ratio=decrease,format=rgba,fade=t=in:st=0.15:d=0.55:alpha=1,fade=t=out:st=1.65:d=0.3:alpha=1[logo];[0:v]drawbox=x=120:y=1370:w=840:h=5:color=0xd7b54a:t=fill,drawbox=x=270:y=1450:w=540:h=2:color=0xd7b54a@0.45:t=fill[introbase];[introbase][logo]overlay=(W-w)/2:545,fade=t=out:st=1.75:d=0.25[intro];[2:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=28:18,eq=brightness=-0.32:saturation=0.75[background];[2:v]scale=1010:1850:force_original_aspect_ratio=decrease[art];[background][art]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=0.35,fade=t=out:st=12.25:d=0.75[advert];[intro][advert]concat=n=2:v=1:a=0,format=yuv420p" `
        -r 30 -c:v libx264 -preset medium -crf 18 -movflags +faststart -an $outputPath
}
