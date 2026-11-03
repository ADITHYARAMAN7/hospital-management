# Draws a synthetic chest X-ray style image and saves it as scan.jpg
Add-Type -AssemblyName System.Drawing
$out = "D:\AA sem 7\Cloud_endsem\hospital\files\scan.jpg"
$w = 800; $h = 900
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::FromArgb(8, 8, 10))

function brush($a, $v) { New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $v, $v, $v + 5)) }
# body / torso glow
for ($i = 0; $i -lt 30; $i++) { $g.FillEllipse((brush 6 150), 130 + $i * 2, 120 + $i * 2, 540 - $i * 4, 760 - $i * 4) }
# lungs (darker)
$g.FillEllipse((brush 200 25), 190, 230, 190, 430)
$g.FillEllipse((brush 200 25), 420, 230, 190, 430)
# spine
for ($y = 140; $y -lt 840; $y += 34) { $g.FillRectangle((brush 220 200), 382, $y, 36, 26) }
# heart
$g.FillEllipse((brush 140 170), 360, 430, 170, 190)
# ribs
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(170, 215, 215, 220)), 9
for ($k = 0; $k -lt 9; $k++) {
  $y = 250 + $k * 45
  $g.DrawArc($pen, 160, $y, 250, 120, 190, 120)
  $g.DrawArc($pen, 390, $y, 250, 120, 230, 120)
}
# clavicles
$g.DrawLine($pen, 210, 200, 390, 230); $g.DrawLine($pen, 410, 230, 590, 200)
# labels
$font = New-Object System.Drawing.Font "Consolas", 16
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230, 230, 230))
$g.DrawString("CITY CARE HOSPITAL - RADIOLOGY", $font, $white, 20, 15)
$g.DrawString("Patient: P1001  Arjun Menon", $font, $white, 20, 42)
$g.DrawString("Chest X-Ray PA   2026-10-21", $font, $white, 20, 840)
$g.DrawString("R", (New-Object System.Drawing.Font "Arial", 36, ([System.Drawing.FontStyle]::Bold)), $white, 700, 60)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $bmp.Dispose()
Get-Item $out | Select-Object Name, Length
