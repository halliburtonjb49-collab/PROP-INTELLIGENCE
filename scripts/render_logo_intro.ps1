param(
  [string]$OutputDirectory = "marketing_site/assets/ads"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$logo = Join-Path $root "assets/branding/Prop_Intelligence_Exact_Logo_Icon_Package/SOURCE_EXACT_LOGO.png"
$output = Join-Path $root $OutputDirectory
New-Item -ItemType Directory -Force -Path $output | Out-Null

function Render-Intro {
  param(
    [string]$Name,
    [int]$Width,
    [int]$Height,
    [int]$LogoSize,
    [int]$LogoY,
    [int]$HeadlineY,
    [int]$TaglineY,
    [int]$HeadlineSize,
    [int]$TaglineSize
  )

  $target = Join-Path $output $Name
  $filter = @"
[0:v]format=rgba,
drawgrid=width=120:height=120:thickness=2:color=0x244553@0.32,
drawbox=x='-520+430*t':y=0:w=220:h=ih:color=0xD7B95A@0.08:t=fill,
drawbox=x='iw+160-520*t':y=0:w=90:h=ih:color=0x64D8F0@0.06:t=fill,
drawbox=x=0:y='ih-16':w='min(iw,iw*t/4.4)':h=6:color=0xD7B95A@0.85:t=fill,
fade=t=in:st=0:d=0.18,fade=t=out:st=5.78:d=0.22[background];
[1:v]format=rgba,scale=$LogoSize`:$LogoSize,
fade=t=in:st=0.20:d=0.55:alpha=1,
fade=t=out:st=5.65:d=0.30:alpha=1[logo];
[background][logo]overlay=x='(W-w)/2':y='$LogoY+18*exp(-1.7*t)*cos(9*t)':shortest=1,
format=yuv420p[v];
[2:a]volume=0.20,afade=t=in:st=0:d=0.15,afade=t=out:st=5.3:d=0.7[a]
"@
  $previousErrorPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $ffmpegOutput = & ffmpeg -hide_banner -loglevel info -y `
    -f lavfi -i "color=c=0x020B12:s=$($Width)x$($Height):r=30:d=6" `
    -loop 1 -framerate 30 -i $logo `
    -f lavfi -i "sine=frequency=58:sample_rate=48000:duration=6" `
    -filter_complex $filter `
    -map "[v]" -map "[a]" -t 6 -r 30 `
    -c:v libx264 -preset slow -crf 17 -profile:v high -level 4.2 `
    -c:a aac -b:a 192k -movflags +faststart $target 2>&1
  $ffmpegExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorPreference
  if ($ffmpegExitCode -ne 0) {
    $ffmpegOutput | Write-Output
    throw "FFmpeg failed while rendering $Name (exit $ffmpegExitCode)"
  }
}

Render-Intro -Name "pi-broadcast-intro-wide.mp4" -Width 1920 -Height 1080 `
  -LogoSize 700 -LogoY 72 -HeadlineY 820 -TaglineY 910 `
  -HeadlineSize 58 -TaglineSize 30

Render-Intro -Name "pi-broadcast-intro-vertical.mp4" -Width 1080 -Height 1920 `
  -LogoSize 900 -LogoY 250 -HeadlineY 1260 -TaglineY 1395 `
  -HeadlineSize 62 -TaglineSize 27

Write-Output "Created:"
Write-Output (Join-Path $output "pi-broadcast-intro-wide.mp4")
Write-Output (Join-Path $output "pi-broadcast-intro-vertical.mp4")
