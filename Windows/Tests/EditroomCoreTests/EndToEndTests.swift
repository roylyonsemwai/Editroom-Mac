import XCTest
@testable import EditroomCore

/// The whole workflow through the CLI with real ffmpeg: new → split → ripple delete → export, then checks
/// the MP4's length, streams and which picture is where. Skipped without ffmpeg unless
/// EDITROOM_REQUIRE_FFMPEG=1 (set in CI so it can't silently skip).
final class EndToEndTests: XCTestCase {
    var ffmpeg: URL!
    var ffprobe: URL!

    override func setUpWithError() throws {
        do {
            ffmpeg = try Tools.find("ffmpeg")
            ffprobe = try Tools.find("ffprobe")
        } catch {
            if ProcessInfo.processInfo.environment["EDITROOM_REQUIRE_FFMPEG"] == "1" { throw error }
            throw XCTSkip("ffmpeg/ffprobe not found")
        }
    }

    func ff(_ args: [String]) throws -> Tools.Result {
        let r = try Tools.run(ffmpeg, ["-hide_banner", "-v", "error", "-y"] + args)
        XCTAssertEqual(r.status, 0, r.stderr)
        return r
    }

    func makeClip(_ url: URL, color: String, seconds: Int, tone: Int) throws {
        _ = try ff(["-f", "lavfi", "-i", "color=c=\(color):s=320x180:r=30:d=\(seconds)",
                    "-f", "lavfi", "-i", "sine=frequency=\(tone):duration=\(seconds)",
                    "-c:v", "mpeg4", "-q:v", "3", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", Tools.nativePath(url)])
    }

    /// Average colour of the frame at `t`.
    func color(_ file: URL, at t: Double) throws -> [Int] {
        let r = try ff(["-ss", String(t), "-i", Tools.nativePath(file), "-frames:v", "1", "-vf", "scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
        return r.stdout.prefix(3).map(Int.init)
    }

    func meanVolume(_ file: URL, from t: Double, length: Double) throws -> Double {
        let r = try Tools.run(ffmpeg, ["-hide_banner", "-ss", String(t), "-t", String(length), "-i", Tools.nativePath(file), "-af", "volumedetect", "-vn", "-f", "null", "-"])
        let line = r.stderr.split(separator: "\n").first { $0.contains("mean_volume:") } ?? ""
        return Double(line.split(separator: ":").last?.replacingOccurrences(of: "dB", with: "").trimmingCharacters(in: .whitespaces) ?? "") ?? -999
    }

    func testCutAndExport() throws {
        let dir = try tempDir("editroom e2e")
        defer { try? FileManager.default.removeItem(at: dir) }
        let red = dir.appendingPathComponent("red.mp4"), blue = dir.appendingPathComponent("blue clip.mp4")
        try makeClip(red, color: "red", seconds: 3, tone: 440)
        try makeClip(blue, color: "blue", seconds: 2, tone: 880)
        let room = Tools.nativePath(dir.appendingPathComponent("trip.room"))
        let out = dir.appendingPathComponent("trip export.mp4")

        var log: [String] = []
        let say: (String) -> Void = { log.append($0) }
        try EditroomCLI.execute(["new", room, Tools.nativePath(red), Tools.nativePath(blue)], print: say)
        try EditroomCLI.execute(["split", room, "--at", "1"], print: say)
        try EditroomCLI.execute(["ripple-delete", room, "--from", "1", "--to", "2"], print: say)
        try EditroomCLI.execute(["export", room, Tools.nativePath(out)], print: say)
        print(log.joined(separator: "\n"))

        let probe = try Tools.run(ffprobe, ["-v", "error", "-show_entries", "format=duration:stream=codec_type,codec_name,width,height", "-of", "json", Tools.nativePath(out)])
        let info = try XCTUnwrap(JSONSerialization.jsonObject(with: probe.stdout) as? [String: Any])
        let duration = Double(((info["format"] as? [String: Any])?["duration"] as? String) ?? "") ?? 0
        XCTAssertEqual(duration, 4, accuracy: 0.1)
        let streams = (info["streams"] as? [[String: Any]]) ?? []
        XCTAssertEqual(Set(streams.compactMap { $0["codec_type"] as? String }), ["video", "audio"])
        XCTAssertEqual(streams.first { $0["codec_type"] as? String == "video" }?["codec_name"] as? String, "h264")

        // 0–2s: red (its first and last second), 2–4s: blue.
        for t in [0.5, 1.5] {
            let c = try color(out, at: t)
            XCTAssertTrue(c[0] > 180 && c[2] < 80, "expected red at \(t)s, got \(c)")
        }
        for t in [2.5, 3.5] {
            let c = try color(out, at: t)
            XCTAssertTrue(c[2] > 180 && c[0] < 80, "expected blue at \(t)s, got \(c)")
        }
        XCTAssertGreaterThan(try meanVolume(out, from: 0.2, length: 3.6), -40)
    }
}
