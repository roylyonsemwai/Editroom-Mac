import Foundation

/// Reading and writing `.room` files exactly as the Mac app does (`SavedDocument` in EditorModel.swift):
/// pretty-printed, sorted-key JSON of `{ "version": 1, "project": … }`, with each file's path relative to
/// the project's folder stamped in, so a project folder copied from a Mac opens here.
enum RoomFile {
    struct Document: Codable {
        var version = 1
        var project: Project
    }

    static func load(_ url: URL) throws -> Project {
        let doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        var project = doc.project
        project.resolveMovedMedia(projectDir: url.deletingLastPathComponent())
        return project
    }

    /// `source` is where the project was read from, so files not found here keep pointing at the same place
    /// relative to it when saving somewhere else (and copying the footage over later still finds it).
    static func save(_ project: Project, to url: URL, from source: URL? = nil) throws {
        var saved = project
        saved.sanitize()
        let fromDir = (source ?? url).deletingLastPathComponent()
        var stamped = saved
        for i in stamped.assets.indices where !FileManager.default.fileExists(atPath: stamped.assets[i].path) {
            guard let rel = stamped.assets[i].relativePath else { continue }
            stamped.assets[i].path = fromDir.appendingPathComponent(rel).standardizedFileURL.path
        }
        stamped.stampRelativePaths(projectDir: url.deletingLastPathComponent())
        for i in saved.assets.indices { saved.assets[i].relativePath = stamped.assets[i].relativePath }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Document(project: saved)).write(to: url, options: .atomic)
    }

    /// Files the project uses that aren't on this computer.
    static func missingMedia(_ project: Project) -> [MediaAsset] {
        let used = Set(project.clips.compactMap(\.assetID))
        return project.assets.filter { used.contains($0.id) && !FileManager.default.fileExists(atPath: Tools.nativePath($0.source)) }
    }
}

extension MediaAsset {
    /// The file ffmpeg reads: the Mac's conversion (`playablePath`) when it came along, else the original.
    /// `playablePath` itself is left as saved so the Mac app can still convert again when it reopens the project.
    var source: URL {
        if let p = playablePath, FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: path)
    }
}
