// swift-tools-version: 6.2
import PackageDescription

// Reiner Domänenkern (ARCHITEKTUR A-01): keine UI, keine Persistenz, kein HealthKit, keine Systemuhr.
// Namensunabhängig; Deployment Target iOS 26+ (E-02). Keine Drittanbieter-Pakete (A-06).
let package = Package(
    name: "GearCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GearCore", targets: ["GearCore"]),
    ],
    targets: [
        .target(name: "GearCore"),
        .testTarget(name: "GearCoreTests", dependencies: ["GearCore"]),
    ]
)
