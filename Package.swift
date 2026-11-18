// swift-tools-version:5.10
import PackageDescription

// Builds this fork without Xcode (Command Line Tools only), bundled by make-app.sh.
// The Xcode project stays for upstream; this manifest drops Sparkle so the fork never
// updates itself from kmikiy's appcast, and SPM_BUILD hides the #Preview blocks the
// Command Line Tools cannot expand.
let package = Package(
    name: "SpotMenu",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "Vendor/KeyboardShortcuts"),
    ],
    targets: [
        .executableTarget(
            name: "SpotMenu",
            dependencies: [.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            path: "SpotMenu",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "SpotMenu.entitlements",
                "App/UpdaterManager.swift",
            ],
            swiftSettings: [.define("SPM_BUILD")]
        ),
    ]
)
