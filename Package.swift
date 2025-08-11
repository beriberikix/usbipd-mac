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
            name: "SystemExtension",
            targets: ["SystemExtension"]),
        .plugin(
            name: "SystemExtensionBundleBuilder",
            targets: ["SystemExtensionBundleBuilder"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        .executableTarget(
            name: "USBIPDCLI",
            dependencies: ["USBIPDCore", "Common"]),
        .target(
            name: "USBIPDCore",
            dependencies: ["Common"],
            exclude: ["README-USB-Implementation.md"]),
        .target(
            name: "Common",
            dependencies: []),
        .executableTarget(
            name: "QEMUTestServer",
            dependencies: ["Common"]),
        .executableTarget(
            name: "SystemExtension",
            dependencies: ["Common", "USBIPDCore"],
            exclude: ["Info.plist"],
            resources: [
                .copy("SystemExtension.entitlements"),
                .copy("SYSTEM_EXTENSION_SETUP.md"),
                .copy("Info.plist.template")
            ],
            linkerSettings: [
                .linkedFramework("SystemExtensions"),
                .linkedFramework("IOKit")
            ]),
        .plugin(
            name: "SystemExtensionBundleBuilder",
            capability: .buildTool()),
        .testTarget(
            name: "USBIPDCoreTests",
            dependencies: ["USBIPDCore"]),
        .testTarget(
            name: "USBIPDCLITests",
            dependencies: ["USBIPDCLI"]),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["USBIPDCore", "QEMUTestServer", "USBIPDCLI", "SystemExtension", "Common"]),
        .testTarget(
            name: "SystemExtensionTests",
            dependencies: ["SystemExtension", "Common"]),
    ]
)