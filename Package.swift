// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DockerignoreClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "DockerignoreClaimKit", targets: ["DockerignoreClaimKit"]),
        .executable(name: "DockerignoreClaimDemo", targets: ["DockerignoreClaimDemo"])
    ],
    dependencies: [
        .package(url: "https://github.com/rajatslakhina/gitignore-claim-kit.git", from: "1.0.2")
    ],
    targets: [
        .target(
            name: "DockerignoreClaimKit",
            dependencies: [.product(name: "GitignoreClaimKit", package: "gitignore-claim-kit")]
        ),
        .executableTarget(
            name: "DockerignoreClaimDemo",
            dependencies: [
                "DockerignoreClaimKit",
                .product(name: "GitignoreClaimKit", package: "gitignore-claim-kit")
            ]
        ),
        .testTarget(
            name: "DockerignoreClaimKitTests",
            dependencies: ["DockerignoreClaimKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
