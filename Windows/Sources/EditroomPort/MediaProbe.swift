import Foundation

/// What's in a media file, read with ffprobe (the Mac app uses AVFoundation for this).
enum MediaProbe {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp", "gif"]

    private struct Output: Decodable {
        struct Stream: Decodable {
            var codec_type: String?
            var width: Int?
            var height: Int?
            var avg_frame_rate: String?
            var r_frame_rate: String?
            var duration: String?
            var tags: [String: String]?
            var side_data_list: [SideData]?
        }
        struct SideData: Decodable {
            var rotation: Double?
        }
        struct Format: Decodable {
            var duration: String?
        }
        var streams: [Stream]?
        var format: Format?
    }

    static func probe(_ url: URL, ffprobe: URL) throws -> MediaAsset {
        let path = Tools.nativePath(url)
        guard FileManager.default.fileExists(atPath: path) else { throw Tools.Failure(description: "No such file: \(path)") }
        let r = try Tools.run(ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", path])
        guard r.status == 0 else { throw Tools.Failure(description: "ffprobe couldn't read \(path): \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return try asset(fromJSON: r.stdout, url: url)
    }

    /// Builds the library entry from ffprobe's JSON (split out so it's testable without ffprobe).
    static func asset(fromJSON data: Data, url: URL) throws -> MediaAsset {
        let out = try JSONDecoder().decode(Output.self, from: data)
        let streams = out.streams ?? []
        let video = streams.first { $0.codec_type == "video" }
        let hasAudio = streams.contains { $0.codec_type == "audio" }
        let isImage = imageExtensions.contains(url.pathExtension.lowercased())
        let kind: MediaKind = isImage ? .image : (video != nil ? .video : .audio)
        guard kind != .audio || hasAudio else { throw Tools.Failure(description: "\(url.lastPathComponent) has no video or audio") }

        var width = video?.width ?? 0, height = video?.height ?? 0
        let sideRotation: Double? = video?.side_data_list?.compactMap(\.rotation).first
        let tagRotation: Double? = video?.tags?["rotate"].flatMap { Double($0) }
        let rotation = sideRotation ?? tagRotation ?? 0
        if Int(abs(rotation.rounded())) % 180 == 90 { swap(&width, &height) }

        let fps = rate(video?.avg_frame_rate) ?? rate(video?.r_frame_rate) ?? 30
        let duration = kind == .image ? 0 : (Double(out.format?.duration ?? "") ?? Double(video?.duration ?? "") ?? 0)
        return MediaAsset(path: Tools.nativePath(url), name: url.lastPathComponent, kind: kind,
                          duration: duration, width: width, height: height,
                          fps: kind == .video ? fps : 0, hasAudio: kind != .image && hasAudio)
    }

    static func rate(_ s: String?) -> Double? {
        guard let s else { return nil }
        let parts = s.split(separator: "/").compactMap { Double($0) }
        if parts.count == 2, parts[1] > 0, parts[0] > 0 { return parts[0] / parts[1] }
        if parts.count == 1, parts[0] > 0 { return parts[0] }
        return nil
    }
}
