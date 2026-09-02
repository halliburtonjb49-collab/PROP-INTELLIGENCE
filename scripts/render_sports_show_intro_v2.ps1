$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$assetDir = Join-Path $root 'marketing_site/assets/ads/sports-show-intro-v2'
$outputDir = Join-Path $root 'marketing_site/assets/ads'
$logo = Join-Path $assetDir 'pi-monogram-only.png'
$sportsOrbit = Join-Path $assetDir 'sports-orbit.png'
$portalWide = Join-Path $assetDir 'portal-scene-wide.png'
$portalVertical = Join-Path $assetDir 'portal-scene-vertical.png'

New-Item -ItemType Directory -Force -Path $assetDir, $outputDir | Out-Null

$wideBg = Join-Path $assetDir 'arena-wide.png'
$verticalBg = Join-Path $assetDir 'arena-vertical.png'

function Render-Intro {
    param(
        [string]$Background,
        [string]$PortalBackground,
        [string]$Output,
        [int]$Width,
        [int]$Height,
        [int]$LogoSize
    )

    $filter = @"
[0:v]scale=${Width}:${Height}:force_original_aspect_ratio=increase,crop=${Width}:${Height},format=yuv420p,
fade=t=out:st=14.65:d=0.35[bg];
[1:v]scale=w='${LogoSize}':h=-1,format=rgba,
fade=t=in:st=7.55:d=0.65:alpha=1,fade=t=out:st=14.65:d=0.35:alpha=1,split=2[logoGlow][logoCore];
[logoGlow]gblur=sigma=22,colorchannelmixer=aa=0.55[glow];
[2:v]scale=${Width}:${Height}:force_original_aspect_ratio=increase,crop=${Width}:${Height},format=rgba,
fade=t=in:st=0.35:d=3.8:alpha=1[portal];
[3:v]scale=w='${LogoSize}*1.68':h=-1,format=rgba,rotate=angle='-0.14*t':ow=rotw(iw):oh=roth(ih):c=none,
fade=t=in:st=2.3:d=1.8:alpha=1,fade=t=out:st=14.65:d=0.35:alpha=1[orbit];
[4:v]scale=52:${Height},format=rgba,colorchannelmixer=aa=0.13,
fade=t=out:st=4.5:d=1.0:alpha=1[sweepCyan];
[5:v]scale=34:${Height},format=rgba,colorchannelmixer=aa=0.11,
fade=t=out:st=5.2:d=1.0:alpha=1[sweepGold];
[bg][sweepCyan]overlay=x='-80+mod(t*430\,W+160)':y=0:shortest=1[tmpSweep1];
[tmpSweep1][sweepGold]overlay=x='W+60-mod(t*350\,W+140)':y=0:shortest=1[tmpSweep2];
[tmpSweep2][portal]overlay=shortest=1[tmpPortal];
[tmpPortal][orbit]overlay=(W-w)/2:(H-h)/2:shortest=1[tmpOrbit];
[tmpOrbit][glow]overlay=(W-w)/2:(H-h)/2:shortest=1[tmpGlow];
[tmpGlow][logoCore]overlay=(W-w)/2:(H-h)/2:shortest=1,
eq=contrast=1.08:saturation=1.10,format=yuv420p[v];
[6:a]volume=0.055,afade=t=in:st=0:d=0.35,afade=t=out:st=14.2:d=0.8[bed];
[7:a]volume='if(between(t,2.45,2.9),0.22,0)':eval=frame[hit1];
[8:a]volume='if(between(t,7.05,8.1),0.38,0)':eval=frame[hit2];
[bed][hit1][hit2]amix=inputs=3:normalize=0,alimiter=limit=0.90[a]
"@

    & ffmpeg -y `
        -loop 1 -t 15 -i $Background `
        -loop 1 -t 15 -i $logo `
        -loop 1 -t 15 -i $PortalBackground `
        -loop 1 -t 15 -i $sportsOrbit `
        -f lavfi -t 15 -i "color=c=0x55d9ff@1.0:s=52x${Height}:r=30" `
        -f lavfi -t 15 -i "color=c=0xffd86b@0.68:s=${Width}x${Height}:r=30" `
        -f lavfi -t 15 -i "sine=frequency=76:sample_rate=48000" `
        -f lavfi -t 15 -i "sine=frequency=320:sample_rate=48000" `
        -f lavfi -t 15 -i "sine=frequency=54:sample_rate=48000" `
        -filter_complex $filter `
        -map '[v]' -map '[a]' `
        -r 30 -c:v libx264 -preset medium -crf 18 -profile:v high -pix_fmt yuv420p `
        -c:a aac -b:a 192k -movflags +faststart -shortest $Output

    if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed while rendering $Output" }
}

Render-Intro -Background $wideBg -PortalBackground $portalWide -Output (Join-Path $outputDir 'pi-sports-show-intro-wide-v9.mp4') -Width 1920 -Height 1080 -LogoSize 570
Render-Intro -Background $verticalBg -PortalBackground $portalVertical -Output (Join-Path $outputDir 'pi-sports-show-intro-vertical-v9.mp4') -Width 1080 -Height 1920 -LogoSize 720

Write-Host 'Created 15-second sports-show intro masters.'
