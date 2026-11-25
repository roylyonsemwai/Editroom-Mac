import Foundation

/// `editroom-cli`: make a project from media files, cut it with the same timeline code as the Mac app,
/// and export it with ffmpeg. Projects are ordinary `.room` files the Mac app opens too.
public enum EditroomCLI {
    static let usage = """
    Usage: editroom-cli <command> [options]

      new <project.room> <media>... [--width N --height N --fps N]
            Lays the files end to end on V1 (pictures) and A1 (sound) and saves a new project.
      info <project.room>
            Lists the tracks and clips.
      split <project.room> --at <time> [--track V1|A1|...] [-o out.room]
            Cuts every clip under <time> (or just the ones on one track).
      ripple-delete <project.room> (--from <time> --to <time> | --clip <n>) [-o out.room]
            Takes out a stretch of time on every track, or clip <n> (from `info`) and its linked
            sound, and closes the gap.
      close-gaps <project.room> [-o out.room]
            Closes every gap on every track.
      export <project.room> <out.mp4> [--height N] [--encoder NAME] [--dry-run]
            Renders H.264/AAC MP4 with ffmpeg.

    Times are seconds (12.5) or timecode (00:00:12:15). Tools: --ffmpeg/--ffprobe <path>,
    EDITROOM_FFMPEG/EDITROOM_FFPROBE, beside this program, or on PATH.
    """

    struct Args {
        var positional: [String] = []
        var options: [String: String] = [:]
        var flags: Set<String> = []

        init(_ raw: [String]) throws {
            let valueless: Set<String> = ["--dry-run", "--help", "-h"]
            var i = 0
            while i < raw.count {
                let a = raw[i]
                if a.hasPrefix("-") && a.count > 1 && Double(a) == nil {
                    if valueless.contains(a) { flags.insert(a) } else {
                        guard i + 1 < raw.count else { throw Tools.Failure(description: "\(a) needs a value") }
                        options[a] = raw[i + 1]
                        i += 1
                    }
                } else {
                    positional.append(a)
                }
                i += 1
            }
        }

        func int(_ k: String) throws -> Int? {
            guard let v = options[k] else { return nil }
            guard let n = Int(v) else { throw Tools.Failure(description: "\(k) must be a whole number") }
            return n
        }
    }

    public static func run(_ raw: [String]) -> Int32 {
        do {
            try execute(raw, print: { Swift.print($0) })
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }

    static func execute(_ raw: [String], print: (String) -> Void) throws {
        let args = try Args(raw)
        guard let command = args.positional.first, !args.flags.contains("--help"), !args.flags.contains("-h") else {
            print(usage)
            return
        }
        let rest = Array(args.positional.dropFirst())
        func projectURL() throws -> URL {
            guard let p = rest.first else { throw Tools.Failure(description: "\(command) needs a project file") }
            return URL(fileURLWithPath: p)
        }
        func saveEdit(_ project: Project, from url: URL) throws {
            let out = args.options["-o"].map { URL(fileURLWithPath: $0) } ?? url
            try RoomFile.save(project, to: out)
            print("Saved \(Tools.nativePath(out)) (\(Timecode.simple(project.duration)))")
        }

        switch command {
        case "new":
            let url = try projectURL()
            let files = rest.dropFirst().map { URL(fileURLWithPath: $0) }
            guard !files.isEmpty else { throw Tools.Failure(description: "new needs at least one media file") }
            let ffprobe = try Tools.find("ffprobe", explicit: args.options["--ffprobe"])
            let assets = try files.map { try MediaProbe.probe($0, ffprobe: ffprobe) }
            let project = try Assemble.project(assets, width: args.int("--width"), height: args.int("--height"),
                                               fps: args.options["--fps"].flatMap(Double.init))
            try RoomFile.save(project, to: url)
            print("Saved \(Tools.nativePath(url)): \(project.clips.count) clips, \(Timecode.simple(project.duration))")

        case "info":
            print(describe(try RoomFile.load(projectURL())))

        case "split":
            let url = try projectURL()
            var project = try RoomFile.load(url)
            guard let at = try args.options["--at"].map({ try time($0, fps: project.fps) }) else {
                throw Tools.Failure(description: "split needs --at <time>")
            }
            var under = project.clips.filter { $0.start < at && $0.end > at }
            if let name = args.options["--track"] {
                let id = try track(named: name, in: project)
                under = under.filter { $0.trackID == id }
            }
            under = under.filter { !project.isLocked($0.trackID) }
            let made = project.split(ids: Set(under.map(\.id)), at: project.snapFrame(at))
            guard !made.isEmpty else { throw Tools.Failure(description: "No clip to cut at \(Timecode.simple(at))") }
            print("Cut \(made.count) clip\(made.count == 1 ? "" : "s") at \(Timecode.simple(at))")
            try saveEdit(project, from: url)

        case "ripple-delete":
            let url = try projectURL()
            var project = try RoomFile.load(url)
            if let n = try args.int("--clip") {
                let ordered = orderedClips(project)
                guard ordered.indices.contains(n - 1) else { throw Tools.Failure(description: "No clip \(n); see `info`") }
                let ids = project.linked([ordered[n - 1].id])
                project.remove(ids: ids, ripple: true)
                print("Removed clip \(n)\(ids.count > 1 ? " and its linked clip" : "")")
            } else {
                guard let a = try args.options["--from"].map({ try time($0, fps: project.fps) }),
                      let b = try args.options["--to"].map({ try time($0, fps: project.fps) }), b > a else {
                    throw Tools.Failure(description: "ripple-delete needs --from <time> --to <time> (to after from), or --clip <n>")
                }
                let all = Set((project.videoTracks + project.audioTracks).map(\.id))
                project.rippleRemove(from: project.snapFrame(a), to: project.snapFrame(b), tracks: all)
                print("Took out \(Timecode.simple(a))–\(Timecode.simple(b))")
            }
            try saveEdit(project, from: url)

        case "close-gaps":
            let url = try projectURL()
            var project = try RoomFile.load(url)
            for t in project.videoTracks + project.audioTracks where !project.isLocked(t.id) {
                project.closeAllGaps(on: t.id)
            }
            try saveEdit(project, from: url)

        case "export":
            let url = try projectURL()
            guard rest.count >= 2 else { throw Tools.Failure(description: "export needs an output file, e.g. out.mp4") }
            let out = URL(fileURLWithPath: rest[1])
            let project = try RoomFile.load(url)
            let missing = RoomFile.missingMedia(project)
            guard missing.isEmpty else {
                throw Tools.Failure(description: "Missing media:\n" + missing.map { "  \($0.name) (\($0.path))" }.joined(separator: "\n"))
            }
            let dry = args.flags.contains("--dry-run")
            let ffmpeg = dry ? nil : try Tools.find("ffmpeg", explicit: args.options["--ffmpeg"])
            var options = FFmpegRender.Options()
            options.height = try args.int("--height")
            options.encoder = args.options["--encoder"] ?? ffmpeg.map(FFmpegRender.pickEncoder) ?? "libx264"
            let render = FFmpegRender(project: project, options: options)
            for note in render.unsupported { print("note: \(note)") }
            if dry {
                print((["ffmpeg"] + (try render.arguments(output: Tools.nativePath(out)))).map(quoted).joined(separator: " "))
                return
            }
            let size = render.outputSize
            print("Exporting \(Timecode.simple(project.duration)) at \(size.width)x\(size.height) with \(options.encoder)…")
            try render.render(to: out, ffmpeg: ffmpeg!)
            print("Exported \(Tools.nativePath(out))")

        default:
            throw Tools.Failure(description: "Unknown command \(command)\n\n\(usage)")
        }
    }

    static func time(_ s: String, fps: Double) throws -> Double {
        if let v = Double(s), v >= 0 { return v }
        if let v = Timecode.parse(s, fps: fps) { return v }
        throw Tools.Failure(description: "Can't read time \(s)")
    }

    static func track(named name: String, in project: Project) throws -> UUID {
        let upper = name.uppercased()
        let kind: TrackKind? = upper.hasPrefix("V") ? .video : upper.hasPrefix("A") ? .audio : nil
        guard let kind, let n = Int(upper.dropFirst()), project.tracks(kind).indices.contains(n - 1) else {
            throw Tools.Failure(description: "No track \(name)")
        }
        return project.tracks(kind)[n - 1].id
    }

    static func orderedClips(_ project: Project) -> [Clip] {
        let order = Dictionary(uniqueKeysWithValues: (project.videoTracks + project.audioTracks).enumerated().map { ($1.id, $0) })
        return project.clips.sorted { (order[$0.trackID] ?? 0, $0.start) < (order[$1.trackID] ?? 0, $1.start) }
    }

    static func describe(_ project: Project) -> String {
        var lines = ["\(project.width)x\(project.height) @ \(project.fps) fps, \(Timecode.simple(project.duration)), \(project.assets.count) files"]
        var n = 0
        for (kind, tracks) in [(TrackKind.video, project.videoTracks), (.audio, project.audioTracks)] {
            for (i, t) in tracks.enumerated() {
                let name = (kind == .video ? "V" : "A") + String(i + 1)
                var flags = [String]()
                if t.hidden { flags.append("hidden") }
                if t.muted { flags.append("muted") }
                if t.locked { flags.append("locked") }
                lines.append("\(name)\(flags.isEmpty ? "" : " (" + flags.joined(separator: ", ") + ")")")
                for c in project.clips.filter({ $0.trackID == t.id }).sorted(by: { $0.start < $1.start }) {
                    n += 1
                    let src = c.kind.usesSource ? String(format: "  from %.2fs", c.sourceStart) : ""
                    let speed = abs(c.speed - 1) > 1e-6 ? String(format: "  %.2fx", c.speed) : ""
                    lines.append(String(format: "  %3d  %@ – %@  %@\(src)\(speed)", n,
                                        Timecode.simple(c.start), Timecode.simple(c.end), project.name(of: c)))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func quoted(_ s: String) -> String {
        s.contains(where: { $0 == " " || $0 == ";" || $0 == "|" || $0 == "[" || $0 == "(" }) ? "\"\(s)\"" : s
    }
}

/// A new project with files laid end to end, video + linked sound as the Mac app places them.
enum Assemble {
    static func project(_ assets: [MediaAsset], width: Int? = nil, height: Int? = nil, fps: Double? = nil) throws -> Project {
        var p = Project()
        let first = assets.first { $0.kind == .video } ?? assets.first { $0.kind == .image }
        if let first, first.width > 0, first.height > 0 { p.width = first.width; p.height = first.height }
        if let first, first.kind == .video, first.fps > 0 { p.fps = (first.fps * 1000).rounded() / 1000 }
        if let width { p.width = width }
        if let height { p.height = height }
        if let fps { p.fps = fps }
        guard p.width > 0, p.height > 0, p.fps > 0 else { throw Tools.Failure(description: "Width, height and fps must be positive") }
        p.assets = assets
        let v = p.videoTracks[0].id, a = p.audioTracks[0].id
        var t = 0.0
        for asset in assets {
            let dur = asset.kind == .image ? 5 : max(1 / p.fps, floor(asset.duration * p.fps + 1e-6) / p.fps)
            switch asset.kind {
            case .image:
                p.clips.append(Clip(trackID: v, kind: .image, assetID: asset.id, start: t, duration: dur))
            case .audio:
                p.clips.append(Clip(trackID: a, kind: .audio, assetID: asset.id, start: t, duration: dur))
            case .video:
                var clip = Clip(trackID: v, kind: .video, assetID: asset.id, start: t, duration: dur)
                if asset.hasAudio {
                    let link = UUID()
                    clip.linkID = link
                    var sound = Clip(trackID: a, kind: .audio, assetID: asset.id, start: t, duration: dur)
                    sound.linkID = link
                    p.clips.append(sound)
                }
                p.clips.append(clip)
            }
            t += dur
        }
        return p
    }
}
