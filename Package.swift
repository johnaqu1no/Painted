// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sketchy",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SketchyKit", path: "Sources/SketchyKit"),
        .executableTarget(name: "Sketchy", dependencies: ["SketchyKit"], path: "Sources/Sketchy",
                          exclude: ["Resources"]),
        // XCTest ships with Xcode, not the Command Line Tools, so the suite is a
        // plain executable: `swift run SketchySelfTest`.
        .executableTarget(name: "SketchySelfTest", dependencies: ["SketchyKit"], path: "Sources/SketchySelfTest")
    ]
)
