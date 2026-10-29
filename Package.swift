// swift-tools-version: 6.2
//
// 仓库自带的测试目标：让任何人 clone 之后一条命令就能跑纯逻辑测试，
// 不必先搭 Xcode 工程、也不必有模拟器或真机。
//
//     swift test
//
// 只打包不依赖 UIKit 的部分（`iPhone/Code/` 与授权判定），
// 相机/界面链路仍需真机验证 —— 见 docs/BUILD.md。

import PackageDescription

let package = Package(
    name: "AimFind",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AimFind",
            path: "iPhone",
            exclude: ["Code/PhotoCodeImporter.swift"],   // 它依赖 UIKit，只服务 iOS 相册导入
            sources: ["Code", "Camera/CameraAccess.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AimFindTests",
            dependencies: ["AimFind"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
