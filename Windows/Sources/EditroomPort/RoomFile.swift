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
        // playablePath is the Mac's AVFoundation conversion cache; when it didn't come along, ffmpeg reads the original.
        for i in project.assets.indices where project.assets[i].playablePath.map({ !FileManager.default.fileExists(atPath: $0) }) ?? false {
            project.assets[i].playablePath = nil
        }
        return project
    }

    static func save(_ project: Project, to url: URL) throws {
        var saved = project
        saved.sanitize()
        // Files not found here keep the link they came with, so copying the footage over later still finds it.
        let kept = Dictionary(uniqueKeysWithValues: saved.assets.compactMap { a in
            FileManager.default.fileExists(atPath: a.path) ? nil : a.relativePath.map { (a.id, $0) }
        })
        saved.stampRelativePaths(projectDir: url.deletingLastPathComponent())
        for i in saved.assets.indices { if let rel = kept[saved.assets[i].id] { saved.assets[i].relativePath = rel } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Document(project: saved)).write(to: url, options: .atomic)
    }

    /// Files the project uses that aren't on this computer.
    static func missingMedia(_ project: Project) -> [MediaAsset] {
        let used = Set(project.clips.compactMap(\.assetID))
        return project.assets.filter { used.contains($0.id) && !FileManager.default.fileExists(atPath: Tools.nativePath($0.url)) }
    }
}
