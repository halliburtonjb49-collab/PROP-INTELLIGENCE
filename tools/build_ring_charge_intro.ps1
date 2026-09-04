$ErrorActionPreference = 'Stop'

$inputVideo = 'C:\Users\PI\OneDrive\Desktop\pi-sports-show-intro-vertical-v5.mp4'
$outputVideo = 'C:\Users\PI\OneDrive\Desktop\pi-sports-show-intro-vertical-v7-visible-charges.mp4'

$filter = @'
[0:v]trim=start=1.15:end=7.35,setpts=(PTS-STARTPTS)*2.419354839,scale=1080:1920:flags=lanczos,
drawbox=x='-260+470*mod(t-0.7,2.6)/2.6':y=690:w=300:h=7:color=0xffc94d@0.92:t=fill:enable='between(t,0.7,3.3)+between(t,6.0,8.6)',
drawbox=x='1040-470*mod(t-1.4,2.8)/2.8':y=985:w=300:h=7:color=0x68d7ff@0.90:t=fill:enable='between(t,1.4,4.2)+between(t,7.0,9.8)',
drawbox=x='-300+510*mod(t-3.0,2.5)/2.5':y=1060:w=340:h=10:color=0xffdc72@0.96:t=fill:enable='between(t,3.0,5.5)+between(t,9.0,11.5)',
drawbox=x='1040-500*mod(t-4.1,2.4)/2.4':y=620:w=320:h=9:color=0xffb52e@0.96:t=fill:enable='between(t,4.1,6.5)+between(t,10.3,12.7)',
drawbox=x=355:y='-260+620*mod(t-2.0,3.0)/3.0':w=8:h=300:color=0x6fdcff@0.90:t=fill:enable='between(t,2.0,5.0)+between(t,8.0,11.0)',
drawbox=x=712:y='-300+650*mod(t-4.8,2.8)/2.8':w=9:h=330:color=0xffcf55@0.95:t=fill:enable='between(t,4.8,7.6)+between(t,10.8,13.6)',
drawbox=x='90+34*sin(9*t)':y='610+28*sin(13*t)':w=18:h=18:color=0xffe7a1@0.95:t=fill:enable='gte(t,5.0)',
drawbox=x='965+28*sin(11*t)':y='1010+32*sin(15*t)':w=16:h=16:color=0x9eeaff@0.92:t=fill:enable='gte(t,6.0)',
split=3[base][glow][detail];
[glow]gblur=sigma=27,eq=brightness='0.02+0.045*t/15+0.02*sin(2*PI*(0.45+0.055*t)*t)':contrast=1.16:saturation=1.45[halo];
[detail]unsharp=7:7:1.05:7:7:0,eq=contrast='1.05+0.12*t/15':saturation='1.08+0.24*t/15'[sharp];
[base][halo]blend=all_mode=screen:all_opacity=0.24[charged];
[charged][sharp]blend=all_mode=normal:all_opacity=0.72,
eq=brightness='0.006+0.020*sin(2*PI*(0.55+0.08*t)*t)*pow(t/15,1.5)':gamma='1.0+0.06*t/15',
vignette=PI/5.2:eval=frame,
fade=t=in:st=0:d=0.45,
fade=t=out:st=14.55:d=0.45,
format=yuv420p[v]
'@

ffmpeg -hide_banner -y -i $inputVideo -filter_complex $filter -map '[v]' -map '0:a?' -t 15 `
  -c:v libx264 -preset medium -crf 17 -profile:v high -level 4.1 -pix_fmt yuv420p `
  -c:a aac -b:a 192k -movflags +faststart $outputVideo

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputVideo)) {
  throw 'FFmpeg did not create the ring-charge intro.'
}

Write-Host "Created: $outputVideo"
