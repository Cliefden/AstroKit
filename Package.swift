// swift-tools-version: 6.0
import PackageDescription

// Pure-Foundation sun, moon and solunar astronomy shared by Equinox, Lunker
// and Otta. No backend, no external dependencies, no resources — safe to keep
// as a public repo. See README.md for the API overview and per-app adoption.
let package = Package(
    name: "AstroKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "AstroKit", targets: ["AstroKit"]),
    ],
    targets: [
        .target(name: "AstroKit"),
        .testTarget(name: "AstroKitTests", dependencies: ["AstroKit"]),
    ]
)
