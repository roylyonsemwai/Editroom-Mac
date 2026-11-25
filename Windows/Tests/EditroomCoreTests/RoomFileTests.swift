import XCTest
@testable import EditroomCore

/// `.room` files stay interchangeable with the Mac app.
final class RoomFileTests: XCTestCase {
    func testOpensMacProjectAndFindsMovedMedia() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let footage = dir.appendingPathComponent("footage", isDirectory: true)
        try FileManager.default.createDirectory(at: footage, withIntermediateDirectories: true)
        for name in ["red.mp4", "blue clip.mp4"] { try Data().write(to: footage.appendingPathComponent(name)) }
        let room = dir.appendingPathComponent("trip.room")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("mac-trip.room"), to: room)

        let p = try RoomFile.load(room)
        XCTAssertEqual(p.clips.count, 6)
        XCTAssertEqual(p.duration, 4, accuracy: 1e-9)
        XCTAssertEqual(p.width, 640)
        XCTAssertEqual(RoomFile.missingMedia(p).map(\.name), [])
        for a in p.assets {
            XCTAssertTrue(FileManager.default.fileExists(atPath: Tools.nativePath(a.source)), a.path)
        }
    }

    func testReportsMissingMedia() throws {
        let p = try RoomFile.load(fixtures.appendingPathComponent("mac-trip.room"))
        XCTAssertEqual(Set(RoomFile.missingMedia(p).map(\.name)), ["red.mp4", "blue clip.mp4"])
    }

    func testSaveRoundTripsInTheMacFormat() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try Assemble.project([asset("a.mp4", duration: 3)])
        let url = dir.appendingPathComponent("p.room")
        try RoomFile.save(original, to: url)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, 1)
        XCTAssertNotNil(json?["project"])
        var loaded = try RoomFile.load(url)
        XCTAssertNotNil(loaded.assets[0].relativePath)
        loaded.assets[0].relativePath = nil
        XCTAssertEqual(loaded, original)
    }

    func testReadsTheOriginalWhenTheMacConversionCacheDidNotComeAlong() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("a.mp4")
        try Data().write(to: media)
        var p = try Assemble.project([asset("a.mp4", duration: 3)])
        p.assets[0].path = media.path
        p.assets[0].playablePath = "/Users/roy/Library/Caches/Editroom/a.mov"
        let url = dir.appendingPathComponent("p.room")
        try RoomFile.save(p, to: url)
        let loaded = try RoomFile.load(url)
        XCTAssertEqual(loaded.assets[0].source.path, media.path)
        XCTAssertEqual(RoomFile.missingMedia(loaded).count, 0)
        try RoomFile.save(loaded, to: url)
        XCTAssertEqual(try RoomFile.load(url).assets[0].playablePath, p.assets[0].playablePath)
    }

    func testEditingBeforeTheFootageArrivesKeepsItsLinks() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let room = dir.appendingPathComponent("trip.room")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("mac-trip.room"), to: room)
        try EditroomCLI.execute(["close-gaps", room.path], print: { _ in })

        let footage = dir.appendingPathComponent("footage", isDirectory: true)
        try FileManager.default.createDirectory(at: footage, withIntermediateDirectories: true)
        for name in ["red.mp4", "blue clip.mp4"] { try Data().write(to: footage.appendingPathComponent(name)) }
        XCTAssertEqual(RoomFile.missingMedia(try RoomFile.load(room)).map(\.name), [])
    }

    func testSavingElsewhereBeforeTheFootageArrivesKeepsPointingAtIt() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let room = dir.appendingPathComponent("trip.room")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("mac-trip.room"), to: room)
        let copy = dir.appendingPathComponent("cuts", isDirectory: true).appendingPathComponent("copy.room")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try EditroomCLI.execute(["close-gaps", room.path, "-o", copy.path], print: { _ in })

        XCTAssertEqual(Set(try RoomFile.load(copy).assets.compactMap(\.relativePath)), ["../footage/red.mp4", "../footage/blue clip.mp4"])
        let footage = dir.appendingPathComponent("footage", isDirectory: true)
        try FileManager.default.createDirectory(at: footage, withIntermediateDirectories: true)
        for name in ["red.mp4", "blue clip.mp4"] { try Data().write(to: footage.appendingPathComponent(name)) }
        XCTAssertEqual(RoomFile.missingMedia(try RoomFile.load(copy)).map(\.name), [])
    }
}
