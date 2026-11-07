// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingNotesKit",
    platforms: [
        .iOS("26.0"),
        .macOS("27.0")
    ],
    products: [
        .library(name: "MeetingNotesKit", targets: ["MeetingNotesKit"])
    ],
    dependencies: [
        // On-device speaker diarization and the briefing voice (CoreML). The
        // `Diarizer` and `TTS` traits are enabled; the NeMo text-normalisation
        // binary is not. All models are bundled (Resources/DiarizerModels,
        // Resources/KokoroModels) and loaded from disk; the library's Hugging
        // Face download path is never called.
        .package(
            url: "https://github.com/FluidInference/FluidAudio",
            exact: "0.18.2",
            traits: ["Diarizer", "TTS"]
        )
    ],
    targets: [
        .target(
            name: "MeetingNotesKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            resources: [
                .copy("Resources/DiarizerModels"),
                .copy("Resources/KokoroModels")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MeetingNotesKitTests",
            dependencies: ["MeetingNotesKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
