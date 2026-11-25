import Foundation

/// Finding and running the external programs (ffmpeg, ffprobe) the port uses in place of AVFoundation.
enum Tools {
    #if os(Windows)
    static let exeSuffix = ".exe"
    static let pathSeparator: Character = ";"
    #else
    static let exeSuffix = ""
    static let pathSeparator: Character = ":"
    #endif

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// A path in the form the OS (and programs we start) expect, e.g. `C:\Media\a.mp4` on Windows.
    static func nativePath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    }

    /// Where a tool is: an explicit path, then `EDITROOM_<NAME>`, then beside this program, then PATH.
    static func find(_ name: String, explicit: String? = nil) throws -> URL {
        let fm = FileManager.default
        if let explicit {
            if fm.isExecutableFile(atPath: explicit) || fm.fileExists(atPath: explicit) { return URL(fileURLWithPath: explicit) }
            throw Failure(description: "\(name) not found at \(explicit)")
        }
        let env = ProcessInfo.processInfo.environment
        if let path = env["EDITROOM_\(name.uppercased())"], fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        var dirs: [URL] = []
        if let exe = Bundle.main.executableURL { dirs.append(exe.deletingLastPathComponent()) }
        let pathVar = env["PATH"] ?? env["Path"] ?? ""
        dirs += pathVar.split(separator: pathSeparator).map { URL(fileURLWithPath: String($0), isDirectory: true) }
        for dir in dirs {
            let candidate = dir.appendingPathComponent(name + exeSuffix)
            if fm.fileExists(atPath: nativePath(candidate)) { return candidate }
        }
        throw Failure(description: "Couldn't find \(name)\(exeSuffix). Install FFmpeg and put it on PATH, set EDITROOM_\(name.uppercased()), or pass --\(name) <path>.")
    }

    struct Result {
        var status: Int32
        var stdout: Data
        var stderr: String
    }

    /// Runs a program to completion, collecting its output.
    static func run(_ exe: URL, _ args: [String]) throws -> Result {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        try p.run()
        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        let errData = errBox.data
        p.waitUntilExit()
        return Result(status: p.terminationStatus, stdout: outData, stderr: String(decoding: errData, as: UTF8.self))
    }
}
