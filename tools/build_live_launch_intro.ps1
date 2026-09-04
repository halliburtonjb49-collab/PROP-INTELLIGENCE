$ErrorActionPreference = 'Stop'

$output = 'C:\Users\PI\OneDrive\Desktop\PI-LIVE-LAUNCH-INTRO.mp4'
$font = 'C\:/Windows/Fonts/bahnschrift.ttf'
$workspace = 'marketing_site/assets/ads/one-workspace-every-screen-vertical.png'
$mobile = 'marketing_site/assets/ads/stop-guessing-vertical.png'
$props = 'C:\Users\PI\Downloads\IMG_2590.PNG'
$feature = 'marketing_site/assets/ads/one-prop-20-seconds-vertical.png'

$filter = @"
[0:v]drawbox=x='-1080+2200*t':y=680:w=1080:h=8:color=0xD7B45A@0.95:t=fill,drawbox=x='1080-2200*t':y=1240:w=1080:h=8:color=0xD7B45A@0.95:t=fill,drawtext=fontfile='$font':text='IT’S LIVE':fontcolor=white:fontsize=150:x=(w-text_w)/2:y=760,drawtext=fontfile='$font':text='LET’S GO.':fontcolor=0xD7B45A:fontsize=132:x=(w-text_w)/2:y=960,drawtext=fontfile='$font':text='PROP INTELLIGENCE':fontcolor=0x8FAFC4:fontsize=44:x=(w-text_w)/2:y=1160,fps=30,settb=AVTB,format=yuv420p[t];
[1:v]split[a1][b1];[a1]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=32[bg1];[b1]scale=1010:1800:force_original_aspect_ratio=decrease[fg1];[bg1][fg1]overlay=(W-w)/2:(H-h)/2,fps=30,settb=AVTB,format=yuv420p[v1];
[2:v]split[a2][b2];[a2]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=32[bg2];[b2]scale=1010:1800:force_original_aspect_ratio=decrease[fg2];[bg2][fg2]overlay=(W-w)/2:(H-h)/2,fps=30,settb=AVTB,format=yuv420p[v2];
[3:v]split[a3][b3];[a3]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=32[bg3];[b3]scale=1010:1800:force_original_aspect_ratio=decrease[fg3];[bg3][fg3]overlay=(W-w)/2:(H-h)/2,fps=30,settb=AVTB,format=yuv420p[v3];
[4:v]split[a4][b4];[a4]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=32[bg4];[b4]scale=1010:1800:force_original_aspect_ratio=decrease[fg4];[bg4][fg4]overlay=(W-w)/2:(H-h)/2,fps=30,settb=AVTB,format=yuv420p[v4];
[5:v]drawbox=x=90:y=680:w=900:h=3:color=0xD7B45A@0.9:t=fill,drawbox=x=90:y=1235:w=900:h=3:color=0xD7B45A@0.9:t=fill,drawtext=fontfile='$font':text='PROP INTELLIGENCE':fontcolor=white:fontsize=66:x=(w-text_w)/2:y=790,drawtext=fontfile='$font':text='PIPROPSINTELL.COM':fontcolor=0xD7B45A:fontsize=92:x=(w-text_w)/2:y=965,drawtext=fontfile='$font':text='FIND THE EDGE.':fontcolor=0x8FAFC4:fontsize=42:x=(w-text_w)/2:y=1135,fps=30,settb=AVTB,format=yuv420p[e];
[t][v1]xfade=transition=wipeleft:duration=0.5:offset=2.5[x1];[x1][v2]xfade=transition=slideup:duration=0.5:offset=5.2[x2];[x2][v3]xfade=transition=wipeleft:duration=0.5:offset=7.9[x3];[x3][v4]xfade=transition=slidedown:duration=0.5:offset=10.6[x4];[x4][e]xfade=transition=fadeblack:duration=0.5:offset=13.3,fade=t=out:st=15.6:d=0.5[outv]
"@

ffmpeg -y `
  -f lavfi -t 3 -i 'color=c=0x020B13:s=1080x1920:r=30' `
  -loop 1 -t 3.2 -i $workspace `
  -loop 1 -t 3.2 -i $mobile `
  -loop 1 -t 3.2 -i $props `
  -loop 1 -t 3.2 -i $feature `
  -f lavfi -t 3 -i 'color=c=0x020B13:s=1080x1920:r=30' `
  -filter_complex $filter -map '[outv]' -t 16.1 -r 30 `
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p `
  -movflags +faststart -an $output

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output $output
