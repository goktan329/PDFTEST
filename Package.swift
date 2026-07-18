// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YKSQuestionSolver",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "YKSQuestionSolver", targets: ["YKSQuestionSolver"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "YKSQuestionSolver",
            path: ".",
            exclude: [
                "README.md",
                "OfflineTestApp.xcodeproj",
                ".github",
                "build",
                "DerivedData"
            ],
            sources: [
                "Models",
                "Services",
                "Views",
                "ViewModels",
                "ML",
                "Utils"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
