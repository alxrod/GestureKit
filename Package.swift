// swift-tools-version: 6.2
import PackageDescription

// GestureCore: each gesture's rules and math, plain Swift, no SwiftUI or
// RealityKit, so it builds on the Mac and its tests run with `swift test`.
// GestureKit: the visionOS side, the components, systems, and modifiers that
// carry out GestureCore's rules on any RealityKit entity or SwiftUI view. Its
// sources compile only for visionOS (`#if os(visionOS)`), so on the Mac it
// builds empty.
// gesturekit-drive: a Mac tool that drives an app's gestures in a visionOS
// simulator through GestureKit's automation, in debug builds, which an app's
// own repository runs with `swift run gesturekit-drive`.
// SkillStamp: the stamp gesturekit-drive writes in the skill it installs,
// naming the GestureKit commit it came from, as plain values, tested on the
// Mac. No product: only the driver uses it.
let package = Package(
    name: "GestureKit",
    platforms: [
        .macOS(.v14),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "GestureCore", targets: ["GestureCore"]),
        .library(name: "GestureKit", targets: ["GestureKit"]),
        .executable(name: "gesturekit-drive", targets: ["GestureKitDrive"]),
    ],
    targets: [
        .target(name: "GestureCore"),
        .target(name: "GestureKit", dependencies: ["GestureCore"]),
        .target(name: "SkillStamp"),
        .executableTarget(name: "GestureKitDrive", dependencies: ["SkillStamp"]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
        .testTarget(name: "SkillStampTests", dependencies: ["SkillStamp"]),
    ],
    swiftLanguageModes: [.v6]
)
