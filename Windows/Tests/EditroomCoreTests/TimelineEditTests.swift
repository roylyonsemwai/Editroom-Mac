import XCTest
@testable import EditroomCore

/// The Mac app's own timeline code (Editroom/Model/Project.swift), running off the Mac.
final class TimelineEditTests: XCTestCase {
    func testAssembleLaysFilesEndToEndWithLinkedSound() throws {
        let p = try Assemble.project([asset("a.mp4", duration: 3), asset("b.mp4", duration: 2, audio: false), asset("c.png", kind: .image, duration: 0)])
        let v = p.clips(on: p.videoTracks[0]), a = p.clips(on: p.audioTracks[0])
        XCTAssertEqual(v.map(\.start), [0, 3, 5])
        XCTAssertEqual(v.map(\.duration), [3, 2, 5])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].linkID, v[0].linkID)
        XCTAssertNotNil(a[0].linkID)
        XCTAssertEqual(p.duration, 10)
        XCTAssertEqual(p.width, 1920)
    }

    func testSplitThenRippleDeleteKeepsTracksInSync() throws {
        var p = try Assemble.project([asset("a.mp4", duration: 3), asset("b.mp4", duration: 2)])
        p.split(ids: Set(p.clips.map(\.id)), at: 1)
        XCTAssertEqual(p.clips.count, 6)
        p.rippleRemove(from: 1, to: 2, tracks: Set((p.videoTracks + p.audioTracks).map(\.id)))
        XCTAssertEqual(p.duration, 4, accuracy: 1e-9)
        for track in [p.videoTracks[0], p.audioTracks[0]] {
            let c = p.clips(on: track)
            XCTAssertEqual(c.map(\.start), [0, 1, 2])
            XCTAssertEqual(c.map(\.sourceStart), [0, 2, 0])
        }
    }

    func testRemovingALinkedClipRipplesBothTracks() throws {
        var p = try Assemble.project([asset("a.mp4", duration: 3), asset("b.mp4", duration: 2)])
        let first = p.clips(on: p.videoTracks[0])[0]
        p.remove(ids: p.linked([first.id]), ripple: true)
        XCTAssertEqual(p.clips.count, 2)
        XCTAssertEqual(p.clips.map(\.start), [0, 0])
        XCTAssertEqual(p.duration, 2)
    }

    func testCloseGaps() throws {
        var p = try Assemble.project([asset("a.mp4", duration: 3, audio: false), asset("b.mp4", duration: 2, audio: false)])
        let second = p.clips(on: p.videoTracks[0])[1].id
        p.clips[p.index(of: second)!].start = 6
        p.closeAllGaps(on: p.videoTracks[0].id)
        XCTAssertEqual(p.clip(second)?.start ?? -1, 3, accuracy: 1e-9)
    }

    func testCLITimeAndTrackParsing() throws {
        let p = Project()
        XCTAssertEqual(try EditroomCLI.time("12.5", fps: 30), 12.5)
        XCTAssertEqual(try EditroomCLI.track(named: "a2", in: p), p.audioTracks[1].id)
        XCTAssertThrowsError(try EditroomCLI.track(named: "V9", in: p))
        XCTAssertThrowsError(try EditroomCLI.Args(["split", "p.room", "--at", "1", "-O", "copy.room"]))
        XCTAssertEqual(try EditroomCLI.Args(["split", "p.room", "--at", "-1.5"]).options["--at"], "-1.5")
    }

    func testRippleDeleteLeavesLockedTracksAlone() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let room = dir.appendingPathComponent("p.room").path
        var p = try Assemble.project([asset("a.mp4", duration: 3), asset("b.mp4", duration: 2)])
        p.audioTracks[0].locked = true
        try RoomFile.save(p, to: URL(fileURLWithPath: room))
        try EditroomCLI.execute(["ripple-delete", room, "--clip", "1"], print: { _ in })
        let after = try RoomFile.load(URL(fileURLWithPath: room))
        XCTAssertEqual(after.clips(on: after.videoTracks[0]).map(\.start), [0])
        XCTAssertEqual(after.clips(on: after.audioTracks[0]).map(\.start), [0, 3])
        XCTAssertThrowsError(try EditroomCLI.execute(["ripple-delete", room, "--clip", "2"], print: { _ in }))
    }
}
