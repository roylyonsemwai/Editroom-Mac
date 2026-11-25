// swift-tools-version:5.9
// Cross-platform build of Editroom's timeline core plus a command-line editor/exporter for Windows
// (also builds on Linux and macOS). The Mac app is still built from Editroom.xcodeproj; this package
// compiles the shared model files in place and doesn't change that build.
import PackageDescription

let core = [
    "Editroom/Model/Project.swift",
    "Editroom/Model/Captions.swift",
    "Editroom/Model/SpeedRamp.swift",
    "Editroom/Model/ColorGrade.swift",
    "Editroom/Model/Transcript.swift",
    "Editroom/Magic/MagicHistory.swift",
]

let port = [
    "Windows/Sources/EditroomPort/Tools.swift",
    "Windows/Sources/EditroomPort/RoomFile.swift",
    "Windows/Sources/EditroomPort/MediaProbe.swift",
    "Windows/Sources/EditroomPort/FFmpegRender.swift",
    "Windows/Sources/EditroomPort/CLI.swift",
]

// Everything else under the package root (the Mac app's other sources, resources, scripts) isn't part of it.
let notCore = [
    "Editroom/App", "Editroom/Assets.xcassets", "Editroom/Engine", "Editroom/MCP", "Editroom/Resources", "Editroom/UI",
    "Editroom/Model/EditorModel.swift", "Editroom/Model/SourcePreview.swift",
    "Editroom/Magic/AgentPresence.swift", "Editroom/Magic/AutoPlanner.swift", "Editroom/Magic/LocalAdd.swift",
    "Editroom/Magic/LocalBrain.swift", "Editroom/Magic/LocalCaptions.swift", "Editroom/Magic/LocalCombined.swift",
    "Editroom/Magic/LocalImprover.swift", "Editroom/Magic/LocalPointed.swift", "Editroom/Magic/LocalRamp.swift",
    "Editroom/Magic/LocalSpeech.swift", "Editroom/Magic/LocalTitle.swift", "Editroom/Magic/MCPDraft.swift",
    "Editroom/Magic/MagicAgent.swift", "Editroom/Magic/MagicMentions.swift", "Editroom/Magic/MagicPlan.swift",
    "Editroom/Magic/MagicShow.swift", "Editroom/Magic/MagicThinking.swift", "Editroom/Magic/MediaAnalyzer.swift",
    "Editroom/Magic/MediaNotes.swift",
    "Editroom.xcodeproj", "Info.plist", "LICENSE", "README.md", "appcast.xml", "Vendor", "design", "docs", "scripts",
    "Windows/Sources/editroom-cli", "Windows/Tests", "Windows/scripts",
]

let package = Package(
    name: "Editroom",
    products: [
        .executable(name: "editroom-cli", targets: ["editroom-cli"]),
    ],
    targets: [
        .target(
            name: "EditroomCore",
            path: ".",
            exclude: notCore,
            sources: core + port,
            swiftSettings: [.define("EDITROOM_CORE")]
        ),
        .executableTarget(
            name: "editroom-cli",
            dependencies: ["EditroomCore"],
            path: "Windows/Sources/editroom-cli"
        ),
        .testTarget(
            name: "EditroomCoreTests",
            dependencies: ["EditroomCore"],
            path: "Windows/Tests/EditroomCoreTests",
            exclude: ["Fixtures"]
        ),
    ]
)
