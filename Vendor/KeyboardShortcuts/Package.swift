// swift-tools-version:5.10
import PackageDescription

// Vendored from sindresorhus/KeyboardShortcuts 2.3.0 (045cf17), the revision upstream
// SpotMenu pins. Only change: the three #Preview blocks at the end of Recorder.swift are
// removed, because the Command Line Tools cannot expand the PreviewsMacros plugin.
let package = Package(
	name: "KeyboardShortcuts",
	defaultLocalization: "en",
	platforms: [.macOS(.v10_15)],
	products: [.library(name: "KeyboardShortcuts", targets: ["KeyboardShortcuts"])],
	targets: [.target(name: "KeyboardShortcuts")]
)
