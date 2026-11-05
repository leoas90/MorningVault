// swift-tools-version: 6.0
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
    targets: [
        .target(
            name: "MeetingNotesKit",
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
