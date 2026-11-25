import XCTest
@testable import EditroomCore

/// The ffmpeg command built from a timeline (no ffmpeg needed).
final class RenderPlanTests: XCTestCase {
    func testArgumentsFollowTheTimeline() throws {
        var p = try Assemble.project([asset("a.mp4", duration: 3), asset("b.mp4", duration: 2)])
        p.split(ids: Set(p.clips.map(\.id)), at: 1)
        p.rippleRemove(from: 1, to: 2, tracks: Set((p.videoTracks + p.audioTracks).map(\.id)))
        let args = try FFmpegRender(project: p, options: .init()).arguments(output: "out.mp4")
        XCTAssertEqual(args.filter { $0 == "-i" }.count, 6)
        let seeks = args.indices.filter { args[$0] == "-ss" }.map { args[$0 + 1] }
        XCTAssertEqual(seeks.filter { $0 == "2.000000" }.count, 2)
        let graph = try XCTUnwrap(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        XCTAssertEqual(graph.components(separatedBy: "overlay=").count - 1, 3)
        XCTAssertTrue(graph.contains("adelay=2000|2000"))
        XCTAssertTrue(graph.contains("amix=inputs=4"))
        XCTAssertEqual(args.last, "out.mp4")
        XCTAssertEqual(args[args.lastIndex(of: "-t")! + 1], "4.000000")
    }

    func testMutedAndHiddenTracksAreLeftOut() throws {
        var p = try Assemble.project([asset("a.mp4", duration: 3)])
        p.videoTracks[0].hidden = true
        p.audioTracks[0].muted = true
        let graph = try FFmpegRender(project: p, options: .init()).arguments(output: "o.mp4").joined(separator: " ")
        XCTAssertFalse(graph.contains("overlay="))
        XCTAssertTrue(graph.contains("[silence]anull[aout]"))
    }

    func testSpeedGainAndFades() throws {
        var p = try Assemble.project([asset("a.mp4", duration: 4)])
        p.setSpeed(ids: Set(p.clips.map(\.id)), speed: 4)
        for i in p.clips.indices { p.clips[i].fadeIn = 0.5; p.clips[i].gainDB = -6 }
        let graph = try FFmpegRender(project: p, options: .init()).arguments(output: "o.mp4").joined(separator: " ")
        XCTAssertTrue(graph.contains("setpts=(PTS-STARTPTS)/4.000000"))
        XCTAssertTrue(graph.contains("atempo=2.000000,atempo=2.000000"))
        XCTAssertTrue(graph.contains("fade=t=in:st=0:d=0.500000:alpha=1"))
        XCTAssertTrue(graph.contains("volume=0.501187"))
    }

    func testUnsupportedFeaturesAreReported() throws {
        var p = try Assemble.project([asset("a.mp4", duration: 4, audio: false)])
        p.clips[0].transitionIn = Transition()
        p.clips.append(Clip(trackID: p.videoTracks[1].id, kind: .text, start: 0, duration: 1))
        let notes = FFmpegRender(project: p, options: .init()).unsupported
        XCTAssertEqual(notes.count, 2)
    }

    func testOutputSizeAndAtempo() throws {
        let p = try Assemble.project([asset("a.mp4", duration: 1)])
        var o = FFmpegRender.Options()
        o.height = 720
        XCTAssertTrue(FFmpegRender(project: p, options: o).outputSize == (1280, 720))
        XCTAssertEqual(FFmpegRender.atempo(0.2).reduce(1, *), 0.2, accuracy: 1e-9)
        XCTAssertTrue(FFmpegRender.atempo(0.2).allSatisfy { (0.5...2).contains($0) })
        XCTAssertEqual(FFmpegRender.atempo(1), [])
    }

    func testProbeJSON() throws {
        let json = #"{"streams":[{"codec_type":"video","width":1920,"height":1080,"avg_frame_rate":"30000/1001","side_data_list":[{"rotation":-90}]},{"codec_type":"audio"}],"format":{"duration":"12.5"}}"#
        let a = try MediaProbe.asset(fromJSON: Data(json.utf8), url: URL(fileURLWithPath: "/m/phone.mov"))
        XCTAssertEqual(a.kind, .video)
        XCTAssertEqual(a.width, 1080)
        XCTAssertEqual(a.height, 1920)
        XCTAssertEqual(a.fps, 29.97, accuracy: 0.01)
        XCTAssertEqual(a.duration, 12.5)
        XCTAssertTrue(a.hasAudio)
        let still = try MediaProbe.asset(fromJSON: Data(#"{"streams":[{"codec_type":"video","width":10,"height":20}]}"#.utf8), url: URL(fileURLWithPath: "/m/x.PNG"))
        XCTAssertEqual(still.kind, .image)
        XCTAssertFalse(still.hasAudio)
    }
}
