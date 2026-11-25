# Editroom on Windows (milestone 1: command-line edit and export)

The Mac app is unchanged and still builds from `Editroom.xcodeproj`. On Windows, `Package.swift` builds
`editroom-cli`, which uses the Mac app's timeline code (`Editroom/Model/*.swift`) for editing and ffmpeg
for import and export. Projects are ordinary `.room` files, so a project folder copied from a Mac opens
here, and `.room` files saved here open on the Mac.

## What works

- `new`: lays media files end to end on V1 (pictures) and A1 (linked sound).
- `split`, `ripple-delete` (a time range on every track, or one clip and its linked sound), and `close-gaps`.
- `info`: lists tracks and clips.
- `export`: writes H.264/AAC MP4. It handles video, image and solid clips, track order, hidden, muted
  and solo tracks, constant speed, fades, and clip and track gain.

Not rendered yet (`export` prints a note when a project uses any of these): text, colour grades and LUTs,
transitions, position and scale, reverse, freeze frames, captions, and ducking. Speed ramps play at their
average speed. There's no GUI, preview, Magic, MCP or installer yet.

## One-time setup (PowerShell)

```powershell
# Visual Studio Build Tools with the Windows SDK (needed by Swift on Windows)
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
# Swift toolchain
winget install --id Swift.Toolchain --exact
# FFmpeg (ffmpeg.exe and ffprobe.exe on PATH)
winget install --id Gyan.FFmpeg --exact
# Git, if you don't have it
winget install --id Git.Git --exact
```

Close and reopen PowerShell so the new PATH applies, then check:

```powershell
swift --version
ffmpeg -hide_banner -version | Select-Object -First 1
```

## Build, test, run

```powershell
git clone https://github.com/roylyonsemwai/Editroom-Mac.git
cd Editroom-Mac
git checkout devin/1795598912-windows-cli-milestone

swift build
swift test
.\Windows\scripts\smoke.ps1
```

`smoke.ps1` makes two test clips, builds a project, cuts it, exports `trip export.mp4` to
`%TEMP%\editroom smoke`, and checks the export's length and pictures.

Use your own footage like this:

```powershell
$cli = ".\.build\debug\editroom-cli.exe"
& $cli new "$HOME\Videos\Trip\trip.room" "$HOME\Videos\Trip\a.mp4" "$HOME\Videos\Trip\b.mov"
& $cli info "$HOME\Videos\Trip\trip.room"
& $cli split "$HOME\Videos\Trip\trip.room" --at 12.5
& $cli ripple-delete "$HOME\Videos\Trip\trip.room" --from 12.5 --to 20
& $cli ripple-delete "$HOME\Videos\Trip\trip.room" --clip 3
& $cli export "$HOME\Videos\Trip\trip.room" "$HOME\Videos\Trip\trip.mp4" --height 1080
```

Times can be seconds (`12.5`) or timecode (`00:00:12:15`). Editing commands save over the project unless
you pass `-o other.room`.

To open a Mac project, copy its folder with the media. Files are found through their paths relative to
the `.room` file. ffmpeg is found through `--ffmpeg <path>`, then `EDITROOM_FFMPEG`, then beside
`editroom-cli.exe`, then PATH. ffprobe is found the same way.

## Encoders and licensing

`export` picks the first H.264 encoder that ffmpeg has, in this order: `libx264`, `h264_mf` (Windows
Media Foundation), then `libopenh264`. To choose one yourself, pass `--encoder h264_mf`. The winget FFmpeg
build is GPL, which is fine for personal use. Shipping ffmpeg with a Windows build would need an LGPL
build (one without libx264) and its source, as `Vendor/ffmpeg/README.md` does for the Mac build.
