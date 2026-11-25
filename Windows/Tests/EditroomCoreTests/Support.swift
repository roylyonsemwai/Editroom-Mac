import Foundation
@testable import EditroomCore

func asset(_ name: String, kind: MediaKind = .video, duration: Double, audio: Bool = true) -> MediaAsset {
    MediaAsset(path: "/media/\(name)", name: name, kind: kind, duration: duration, width: 1920, height: 1080,
               fps: kind == .video ? 30 : 0, hasAudio: audio)
}

func tempDir(_ name: String = "editroom tests") throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) \(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures", isDirectory: true)

extension Project {
    func clips(on track: Track) -> [Clip] { clips.filter { $0.trackID == track.id }.sorted { $0.start < $1.start } }
}
