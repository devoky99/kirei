// swift-tools-version: 6.0
// Gemeinsamer Code für iPhone, iPad und Mac.
// KireiCore entscheidet über Fotos und kennt keine Oberfläche.
// KireiUI enthält gemeinsame SwiftUI-Bausteine.

import PackageDescription

let package = Package(
    name: "KireiKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "KireiCore", targets: ["KireiCore"]),
        .library(name: "KireiUI", targets: ["KireiUI"]),
    ],
    targets: [
        .target(name: "KireiCore"),
        .target(name: "KireiUI", dependencies: ["KireiCore"]),
        .testTarget(name: "KireiCoreTests", dependencies: ["KireiCore"]),
    ]
)
