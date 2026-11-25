import Foundation

/// Renders a project to a file with ffmpeg: each clip becomes an input trimmed to its footage, placed at
/// its timeline time and stacked in track order over black (video), or mixed (audio). This stands in for
/// the Mac app's AVFoundation composition/export for the features listed in `supported`.
struct FFmpegRender {
    struct Options {
        var encoder = "libx264"
        var height: Int?
        var crf = 20
        var audioBitrate = "192k"
    }

    let project: Project
    let options: Options

    /// Things this renderer doesn't draw yet, as human-readable notes (empty when it's all covered).
    var unsupported: [String] {
        var notes: [String] = []
        func note(_ what: String, _ n: Int) { if n > 0 { notes.append("\(what) (\(n) clip\(n == 1 ? "" : "s")) not rendered yet") } }
        let clips = project.clips
        note("Text", clips.filter { $0.kind == .text }.count)
        note("Colour grades", clips.filter { $0.grade != nil }.count)
        note("Transitions", clips.filter { $0.transitionIn != nil }.count)
        note("Position/scale", clips.filter { !($0.transform?.isIdentity ?? true) }.count)
        note("Reverse", clips.filter { $0.isReversed }.count)
        note("Freeze frames", clips.filter { $0.isFreeze }.count)
        note("Speed ramps (played at their average speed)", clips.filter { $0.ramp != nil }.count)
        if project.captions != nil { notes.append("Captions not rendered yet") }
        if (project.audioTracks.contains { $0.duckUnder != nil }) { notes.append("Ducking not applied yet") }
        return notes
    }

    var outputSize: (width: Int, height: Int) {
        guard let h = options.height, h > 0, h < project.height else { return (even(project.width), even(project.height)) }
        let w = Double(project.width) * Double(h) / Double(max(1, project.height))
        return (even(Int(w.rounded())), even(h))
    }

    private func even(_ v: Int) -> Int { max(2, v - v % 2) }

    private static func num(_ v: Double) -> String { String(format: "%.6f", v) }

    /// The ffmpeg arguments (without the program) that write the project to `output`.
    func arguments(output: String) throws -> [String] {
        let total = project.duration
        guard total > 0 else { throw Tools.Failure(description: "The timeline is empty.") }
        let (w, h) = outputSize
        let fps = project.fps > 0 ? project.fps : 30
        let n = Self.num

        var inputs: [String] = []
        var graph: [String] = []
        var inputCount = 0

        func addInput(_ args: [String]) -> Int {
            inputs += args
            inputCount += 1
            return inputCount - 1
        }

        // Video: black, then each visible track's clips on top, first track at the bottom (as the Mac compositor draws).
        graph.append("color=c=black:s=\(w)x\(h):r=\(n(fps)):d=\(n(total)),format=yuva420p[base]")
        var current = "base", overlays = 0
        for track in project.videoTracks where !track.hidden {
            for clip in project.clips.filter({ $0.trackID == track.id }).sorted(by: { $0.start < $1.start }) {
                var chain: String
                switch clip.kind {
                case .video where !clip.isReversed && !clip.isFreeze:
                    guard let asset = project.asset(clip.assetID), asset.kind == .video else { continue }
                    let length = max(clip.sourceLength, 1 / fps)
                    let k = addInput(["-ss", n(clip.sourceStart), "-t", n(length), "-i", Tools.nativePath(asset.source)])
                    let speed = length / clip.duration
                    chain = "[\(k):v]setpts=(PTS-STARTPTS)/\(n(speed)),fps=\(n(fps)),\(fit(w, h))"
                case .image:
                    guard let asset = project.asset(clip.assetID) else { continue }
                    // `-loop` belongs to the still-image reader; GIFs have their own demuxer, so they're looped as a stream.
                    let gif = asset.source.pathExtension.lowercased() == "gif"
                    let loop = gif ? ["-stream_loop", "-1"] : ["-loop", "1", "-framerate", n(fps)]
                    let k = addInput(loop + ["-t", n(clip.duration), "-i", Tools.nativePath(asset.source)])
                    chain = "[\(k):v]setpts=PTS-STARTPTS,\(gif ? "fps=\(n(fps))," : "")\(fit(w, h))"
                case .solid:
                    let c = clip.color
                    let hex = [c.r, c.g, c.b].map { String(format: "%02X", Int(($0.clamped(to: 0...1) * 255).rounded())) }.joined()
                    chain = "color=c=0x\(hex)@\(n(c.a.clamped(to: 0...1))):s=\(w)x\(h):r=\(n(fps)):d=\(n(clip.duration)),format=yuva420p"
                default:
                    continue
                }
                chain += ",trim=duration=\(n(clip.duration))"
                if clip.fadeIn > 0 { chain += ",fade=t=in:st=0:d=\(n(clip.fadeIn)):alpha=1" }
                if clip.fadeOut > 0 { chain += ",fade=t=out:st=\(n(max(0, clip.duration - clip.fadeOut))):d=\(n(clip.fadeOut)):alpha=1" }
                chain += ",setpts=PTS+\(n(clip.start))/TB"
                overlays += 1
                graph.append(chain + "[v\(overlays)]")
                graph.append("[\(current)][v\(overlays)]overlay=eof_action=pass:format=auto[o\(overlays)]")
                current = "o\(overlays)"
            }
        }
        graph.append("[\(current)]format=yuv420p[vout]")

        // Audio: each audible clip trimmed, retimed, faded, delayed to its place, then mixed with silence the timeline's length.
        graph.append("anullsrc=r=48000:cl=stereo,atrim=duration=\(n(total))[silence]")
        var mixed = ["[silence]"]
        for track in project.audioTracks where project.isAudible(track) {
            for clip in project.clips.filter({ $0.trackID == track.id && $0.kind == .audio }).sorted(by: { $0.start < $1.start }) {
                guard let asset = project.asset(clip.assetID), asset.hasAudio else { continue }
                let length = max(clip.sourceLength, 1 / fps)
                let k = addInput(["-ss", n(clip.sourceStart), "-t", n(length), "-i", Tools.nativePath(asset.source)])
                var chain = "[\(k):a]asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo"
                for t in Self.atempo(length / clip.duration) { chain += ",atempo=\(n(t))" }
                chain += ",atrim=duration=\(n(clip.duration))"
                let gain = dbToLinear(track.gainDB + clip.gainDB)
                if abs(gain - 1) > 1e-6 { chain += ",volume=\(n(gain))" }
                if clip.fadeIn > 0 { chain += ",afade=t=in:st=0:d=\(n(clip.fadeIn)):curve=\(Self.curve(clip.inCurve, rising: true))" }
                if clip.fadeOut > 0 {
                    chain += ",afade=t=out:st=\(n(max(0, clip.duration - clip.fadeOut))):d=\(n(clip.fadeOut)):curve=\(Self.curve(clip.outCurve, rising: false))"
                }
                let ms = Int((clip.start * 1000).rounded())
                // Padded to the full length so the mix never rescales when a clip ends.
                chain += ",adelay=\(ms)|\(ms),apad=whole_dur=\(n(total))"
                let label = "a\(mixed.count)"
                graph.append(chain + "[\(label)]")
                mixed.append("[\(label)]")
            }
        }
        if mixed.count == 1 {
            graph.append("[silence]anull[aout]")
        } else {
            graph.append(mixed.joined() + "amix=inputs=\(mixed.count):duration=first:dropout_transition=0,volume=\(mixed.count)[aout]")
        }

        var video = ["-c:v", options.encoder]
        switch options.encoder {
        case "libx264": video += ["-preset", "medium", "-crf", String(options.crf)]
        case "h264_mf": video += ["-b:v", "\(max(2, w * h / 200_000))M"]
        default: break
        }
        return ["-hide_banner", "-y"] + inputs + [
            "-filter_complex", graph.joined(separator: ";"),
            "-map", "[vout]", "-map", "[aout]",
        ] + video + [
            "-pix_fmt", "yuv420p", "-r", n(fps),
            "-c:a", "aac", "-b:a", options.audioBitrate, "-ar", "48000",
            "-t", n(total), "-movflags", "+faststart", output,
        ]
    }

    /// Scales a picture to fit the frame (keeping its shape) and centres it on a transparent frame.
    private func fit(_ w: Int, _ h: Int) -> String {
        "scale=\(w):\(h):force_original_aspect_ratio=decrease,setsar=1,format=yuva420p,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2:color=black@0"
    }

    /// atempo steps that multiply to `speed` (each step must be 0.5…2 to work on every ffmpeg version).
    static func atempo(_ speed: Double) -> [Double] {
        guard speed > 0, abs(speed - 1) > 1e-6 else { return [] }
        var left = speed, out: [Double] = []
        while left > 2 { out.append(2); left /= 2 }
        while left < 0.5 { out.append(0.5); left /= 0.5 }
        out.append(left)
        return out
    }

    /// ffmpeg's afade curve closest to the timeline's fade curve.
    static func curve(_ c: FadeCurve, rising: Bool) -> String {
        switch c {
        case .linear: return "tri"
        case .easeIn: return "cub"
        case .easeOut: return "icub"
        case .smooth: return "hsin"
        }
    }

    /// The first H.264 encoder this ffmpeg has, preferring x264, then Windows Media Foundation, then OpenH264.
    static func pickEncoder(ffmpeg: URL) -> String {
        guard let r = try? Tools.run(ffmpeg, ["-hide_banner", "-encoders"]), r.status == 0 else { return "libx264" }
        let list = String(decoding: r.stdout, as: UTF8.self)
        for name in ["libx264", "h264_mf", "libopenh264"] where list.contains(" \(name) ") { return name }
        return "mpeg4"
    }

    /// `-/filter_complex <file>` on FFmpeg 7.1+, `-filter_complex_script <file>` before (removed later).
    static func scriptFlag(ffmpeg: URL) -> String {
        guard let r = try? Tools.run(ffmpeg, ["-hide_banner", "-version"]) else { return "-/filter_complex" }
        let first = String(decoding: r.stdout, as: UTF8.self).components(separatedBy: .newlines).first ?? ""
        guard let word = first.split(separator: " ").dropFirst(2).first else { return "-/filter_complex" }
        let parts = word.split(whereSeparator: { !$0.isNumber }).prefix(2).compactMap { Int($0) }
        guard parts.count == 2, word.first?.isNumber == true, parts[0] < 1000 else { return "-/filter_complex" }
        return (parts[0], parts[1]) >= (7, 1) ? "-/filter_complex" : "-filter_complex_script"
    }

    /// Runs ffmpeg. Long timelines go through a filter script, as Windows command lines are limited to 32k characters.
    func render(to output: URL, ffmpeg: URL) throws {
        var args = try arguments(output: Tools.nativePath(output))
        var script: URL?
        if let i = args.firstIndex(of: "-filter_complex"), args[i + 1].count > 6000 {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("editroom-\(UUID().uuidString).ffgraph")
            try args[i + 1].write(to: url, atomically: true, encoding: .utf8)
            args[i] = Self.scriptFlag(ffmpeg: ffmpeg)
            args[i + 1] = Tools.nativePath(url)
            script = url
        }
        defer { if let script { try? FileManager.default.removeItem(at: script) } }
        let r = try Tools.run(ffmpeg, args)
        guard r.status == 0 else {
            let tail = r.stderr.components(separatedBy: .newlines).filter { !$0.isEmpty }.suffix(15).joined(separator: "\n")
            throw Tools.Failure(description: "ffmpeg failed (exit \(r.status)):\n\(tail)")
        }
    }
}
