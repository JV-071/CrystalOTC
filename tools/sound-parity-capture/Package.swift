// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundParityCapture",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "sound-parity-capture", targets: ["SoundParityCapture"]),
    ],
    targets: [
        .executableTarget(
            name: "SoundParityCapture",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
