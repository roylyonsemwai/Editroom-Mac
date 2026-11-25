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
            XCTAssertTrue(FileManager.default.fileExists(atPath: Tools.nativePath(a.url)), a.path)
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
}
