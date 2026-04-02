// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchCode",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NotchCode",
            path: "Sources/NotchCode",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/NotchCode/Info.plist"])
            ]
        )
    ]
)
