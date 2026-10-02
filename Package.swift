// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScheduleWidget",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScheduleWidget",
            path: "Sources/ScheduleWidget"
        )
    ]
)
