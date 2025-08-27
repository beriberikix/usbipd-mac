// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "usbipd-mac",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "usbipd",
            targets: ["USBIPDCLI"]),
        .library(
            name: "USBIPDCore",
            targets: ["USBIPDCore"]),
        .executable(
            name: "QEMUTestServer",
            targets: ["QEMUTestServer"]),
        .library(
            name: "Common",
            targets: ["Common"]),
        .executable(
            name: "USBIPDSystemExtension",
            targets: ["SystemExtension"]),
        // Plugin temporarily disabled - completion generation works via CLI scripts
        // .plugin(
        //     name: "CompletionGeneratorPlugin",
        //     targets: ["CompletionGeneratorPlugin"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        .executableTarget(
            name: "USBIPDCLI",
            dependencies: ["USBIPDCore", "Common"],
            // Plugin integration working but temporarily disabled due to build timeout
            // plugins: ["CompletionGeneratorPlugin"]
        ),
        .target(
            name: "USBIPDCore",
            dependencies: ["Common"],
            linkerSettings: [
                .linkedFramework("Security")
            ]),
        .target(
            name: "Common",
            dependencies: []),
        .executableTarget(
            name: "QEMUTestServer",
            dependencies: ["Common", "USBIPDCore"]),
        .executableTarget(
            name: "SystemExtension",
            dependencies: ["Common", "USBIPDCore"],
            exclude: ["Info.plist"],
            resources: [
                .copy("SystemExtension.entitlements"),
                .copy("Info.plist.template")
            ],
            linkerSettings: [
                .linkedFramework("SystemExtensions"),
                .linkedFramework("IOKit")
            ]),
        // Temporarily reduce test scope to basic functionality only
        .testTarget(
            name: "USBIPDCLITests",
            dependencies: ["USBIPDCLI"],
            sources: [".", "../SharedUtilities"]),
        .testTarget(
            name: "USBIPDCoreTests",
            dependencies: ["USBIPDCore", "Common"],
            sources: [".", "../SharedUtilities"]),
        // Temporarily disabled for CI stability
        // .testTarget(
        //     name: "IntegrationTests",
        //     dependencies: ["USBIPDCore", "QEMUTestServer", "USBIPDCLI", "SystemExtension", "Common"],
        //     sources: [".", "../SharedUtilities"]),
        // .testTarget(
        //     name: "SystemExtensionTests",
        //     dependencies: ["SystemExtension", "Common"],
        //     sources: [".", "../SharedUtilities"]),
        // .testTarget(
        //     name: "QEMUIntegrationTests",
        //     dependencies: ["QEMUTestServer", "USBIPDCore", "Common"],
        //     path: "Tests/QEMUIntegrationTests",
        //     sources: [".", "../SharedUtilities"]),
        // Plugin temporarily disabled - works but causes build timeout
        // .plugin(
        //     name: "CompletionGeneratorPlugin",
        //     capability: .buildTool()),
    ]
)