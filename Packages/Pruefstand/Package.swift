// swift-tools-version: 6.0
// Prüfstand: misst den Kern auf dem Mac mit markierten Testbildern statt der Mediathek.
// Getrennt vom App-Paket, damit nichts davon in der App landet.

import PackageDescription

let package = Package(
    name: "Pruefstand",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "kirei-pruefstand", targets: ["KireiPruefstand"]),
    ],
    dependencies: [
        .package(path: "../KireiKit"),
    ],
    targets: [
        .executableTarget(
            name: "KireiPruefstand",
            dependencies: [
                .product(name: "KireiCore", package: "KireiKit"),
            ]
        ),
    ]
)
