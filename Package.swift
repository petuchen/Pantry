// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pantry",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PantryCore", targets: ["PantryCore"]),
        .executable(name: "Pantry", targets: ["Pantry"]),
    ],
    targets: [
        // All logic that can be tested without a UI lives here (scanners,
        // classification, duplicate detection, removal planning, downloads).
        .target(name: "PantryCore"),
        // SwiftUI app. Thin: views + an observable AppModel that calls PantryCore.
        .executableTarget(name: "Pantry", dependencies: ["PantryCore"]),
        .testTarget(name: "PantryCoreTests", dependencies: ["PantryCore"]),
    ]
)
