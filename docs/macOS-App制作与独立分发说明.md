# macOS App 制作与独立分发说明

## 这种方式叫什么

这个项目采用的是：

**原生 macOS App 的命令行构建与 Developer ID 独立分发。**

也可以简称为：

- SwiftUI 原生 macOS App
- 无 Xcode 工程的命令行构建
- Developer ID 独立分发
- DMG 分发

它不是网页套壳，也不是脚本工具。最终生成的是正常的原生 `.app`，只是没有使用 Xcode 的图形化工程界面来管理构建过程。

## 整体流程

```text
Swift 源代码
    ↓ swiftc 编译
通用二进制（Apple Silicon + Intel）
    ↓ 组装 App Bundle
Mac 空间清理.app
    ↓ Developer ID 签名 + Hardened Runtime
已签名 App
    ↓ Apple Notary Service 公证
已公证 App
    ↓ hdiutil 封装并签名
DMG 安装包
    ↓ 再次公证并装订票据
可通过网站或网盘分发的最终 DMG
```

## 1. 使用 SwiftUI 编写原生界面

主程序位于：

`MacSpaceCleaner.swift`

它使用 Apple 官方的 Swift 和 SwiftUI 框架，因此界面、按钮、窗口、列表和系统权限都属于原生 macOS 技术。

## 2. 不使用 Xcode 工程也能编译

Xcode 本质上也是调用编译器和系统工具完成构建。这个项目直接通过命令行调用 `swiftc`：

```bash
xcrun --sdk macosx swiftc ...
```

发布脚本会分别编译：

- `arm64`：Apple Silicon Mac
- `x86_64`：Intel Mac

然后通过 `lipo` 合并为 Universal Binary，因此同一个 App 可以在两种 Mac 上运行。

## 3. 手工组装 App Bundle

macOS 的 `.app` 实际上是一个具有固定结构的文件夹：

```text
Mac 空间清理.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── MacSpaceCleaner
    └── Resources/
        └── AppIcon.icns
```

其中：

- `Info.plist` 描述名称、版本、Bundle ID 和最低系统版本
- `MacOS/` 保存编译后的程序
- `Resources/` 保存图标等资源

## 4. Developer ID 签名

如果 App 不通过 Mac App Store 发布，需要使用 Apple Developer 账户中的 `Developer ID Application` 证书签名。

签名的作用是让 macOS 确认：

- App 来自已验证的开发者
- App 自签名后没有被篡改
- App 启用了 Hardened Runtime 安全机制

这个项目的签名由 `release.sh` 自动完成。

## 5. Apple 公证

签名不等于公证。公证时，App 会上传到 Apple Notary Service 进行自动安全检查。

审核通过后，脚本使用 `stapler` 把公证票据装订到 App 和 DMG 中。这样即使用户临时没有联网，macOS 也能识别公证结果。

这个项目的公证由 `notarize.sh` 自动完成。

## 6. 封装为 DMG

DMG 是 Mac 常见的软件分发格式。用户打开 DMG 后，把 App 拖入“应用程序”文件夹即可完成安装。

DMG 不是 App 本身，而是一个只读磁盘映像，类似用于交付软件的安装容器。

## 7. 为什么不放 Mac App Store

Mac App Store 通常要求 App 启用 App Sandbox。清理工具需要读取多个缓存目录，并调用 Xcode 的 `simctl` 管理旧模拟器；沙盒会限制这些核心功能。

因此，这类工具更适合：

- 使用 Developer ID 签名
- 通过 Apple 公证
- 在官方网站、GitHub Release 或可信网盘提供 DMG 下载

这仍然是 Apple 官方支持的正规 macOS 软件分发方式。

## 与普通 Xcode 项目的区别

| 项目 | 当前方式 | 常规 Xcode 工程 |
| --- | --- | --- |
| 源码 | Swift / SwiftUI | Swift / SwiftUI |
| 编译器 | `swiftc` | Xcode 调用相同工具链 |
| 工程管理 | Shell 脚本 | `.xcodeproj` 或 `.xcworkspace` |
| 签名 | `codesign` 命令 | Xcode Signing 设置 |
| 公证 | `notarytool` 命令 | Xcode Organizer 或命令行 |
| 最终 App | 原生 macOS App | 原生 macOS App |

两种方式生成的都是真正的原生 App。当前项目文件较少，使用命令行脚本更直接；当项目出现多个模块、测试目标、第三方依赖或复杂资源时，改用 Xcode 工程通常更方便。

## 当前项目中的关键文件

- `MacSpaceCleaner.swift`：App 主程序
- `Info.plist`：App 元数据
- `IconGenerator.swift`：图标生成程序
- `release.sh`：编译、组装、签名并生成 DMG
- `notarize.sh`：公证 App 和 DMG、装订票据并生成 SHA-256
- `release-package/`：最终可分发文件

## 日后发布新版本

修改源码和版本号后，在终端运行：

```bash
cd "/Volumes/MacT7/projectDocuments/MacSpaceCleaner"
./release.sh
./notarize.sh
```

完成后，还需要确认：

- App 和 DMG 的 Gatekeeper 结果为 `Notarized Developer ID`
- 在另一台 Mac 上完成一次实际安装测试
- 更新版本说明和 SHA-256 校验值
- 不要把证书私钥或 App 专用密码放进项目文件夹或上传到网站

## 当前项目状态

当前 `MacSpaceCleaner-1.2.dmg` 已完成：

- Apple Silicon 与 Intel 通用构建
- Developer ID 正式签名
- Hardened Runtime
- Apple 公证与票据装订
- Gatekeeper 验证
- SHA-256 校验文件

因此它可以通过官网、GitHub Release 或其他可信下载渠道独立分发。
