// swift-tools-version: 6.2
import PackageDescription

// AmmuttaCore is pure Swift (Foundation only) and also builds and tests on Linux.
// AmmuttaPersistence needs SwiftData, so it exists only on Apple platforms.
var products: [Product] = [
    .library(name: "AmmuttaCore", targets: ["AmmuttaCore"]),
]
var targets: [Target] = [
    .target(name: "AmmuttaCore"),
    .testTarget(name: "AmmuttaCoreTests", dependencies: ["AmmuttaCore"]),
]

#if !os(Linux)
products.append(.library(name: "AmmuttaPersistence", targets: ["AmmuttaPersistence"]))
targets.append(.target(name: "AmmuttaPersistence", dependencies: ["AmmuttaCore"]))
targets.append(.testTarget(name: "AmmuttaPersistenceTests", dependencies: ["AmmuttaPersistence", "AmmuttaCore"]))
#endif

let package = Package(
    name: "AmmuttaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
