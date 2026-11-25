# End-to-end check of editroom-cli on Windows: makes two test clips with ffmpeg, builds a project,
# cuts it, exports an MP4 and checks its length and pictures. Run from the repository root after `swift build`.
param(
    [string]$Cli = ".\.build\debug\editroom-cli.exe",
    [string]$Work = "$env:TEMP\editroom smoke"
)
$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

$Cli = (Resolve-Path $Cli).Path
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$red = Join-Path $Work "red.mp4"
$blue = Join-Path $Work "blue clip.mp4"
$room = Join-Path $Work "trip.room"
$out = Join-Path $Work "trip export.mp4"

Invoke-Checked ffmpeg @("-hide_banner", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=red:s=640x360:r=30:d=3", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:v", "mpeg4", "-q:v", "3", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", $red)
Invoke-Checked ffmpeg @("-hide_banner", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=blue:s=640x360:r=30:d=2", "-f", "lavfi", "-i", "sine=frequency=880:duration=2", "-c:v", "mpeg4", "-q:v", "3", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", $blue)

Invoke-Checked $Cli @("new", $room, $red, $blue)
Invoke-Checked $Cli @("split", $room, "--at", "1")
Invoke-Checked $Cli @("ripple-delete", $room, "--from", "1", "--to", "2")
Invoke-Checked $Cli @("info", $room)
Invoke-Checked $Cli @("export", $room, $out)

$duration = [double](& ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $out)
Write-Host "Exported duration: $duration s"
if ([math]::Abs($duration - 4.0) -gt 0.1) { throw "Expected a 4 s export, got $duration s" }

function Get-Rgb([double]$t) {
    $tmp = Join-Path $Work "frame.rgb"
    Invoke-Checked ffmpeg @("-hide_banner", "-v", "error", "-y", "-ss", "$t", "-i", $out, "-frames:v", "1", "-vf", "scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", $tmp)
    $b = [System.IO.File]::ReadAllBytes($tmp)
    Remove-Item $tmp
    return $b
}
foreach ($t in 0.5, 1.5) { $c = Get-Rgb $t; if (-not ($c[0] -gt 180 -and $c[2] -lt 80)) { throw "Expected red at $t s, got $($c -join ',')" } }
foreach ($t in 2.5, 3.5) { $c = Get-Rgb $t; if (-not ($c[2] -gt 180 -and $c[0] -lt 80)) { throw "Expected blue at $t s, got $($c -join ',')" } }
Write-Host "Smoke test passed: $out"
