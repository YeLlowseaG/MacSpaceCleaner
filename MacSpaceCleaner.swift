import SwiftUI
import Foundation
import AppKit

enum AppLanguage {
    static var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }
}

struct CacheItem: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let path: String
    let bytes: Int64
    let recommended: Bool
    var selected: Bool
}

struct CacheTarget {
    let name: String
    let detail: String
    let path: String
    let recommended: Bool
    let minimumBytes: Int64
}

struct ReviewItem: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let path: String
    let bytes: Int64
}

struct RuntimeItem: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let bytes: Int64
    var selected: Bool
}

struct RuntimeInfo: Decodable {
    let identifier: String
    let platformIdentifier: String
    let runtimeIdentifier: String
    let version: String
    let build: String
    let sizeBytes: Int64?
    let state: String
    let deletable: Bool?
}

struct ScanResult {
    let cacheItems: [CacheItem]
    let reviewItems: [ReviewItem]
    let runtimeItems: [RuntimeItem]
    let keptRuntimes: [String]
    let sharedCacheBytes: Int64
    let freeBytes: Int64
    let totalBytes: Int64
    let runtimeError: String?
}

struct CleanupOutcome: Identifiable {
    let id = UUID()
    let cleanedItemCount: Int
    let selectedBytes: Int64
    let issues: [String]
}

struct ContentEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let bytes: Int64
    let isDirectory: Bool
    let modifiedAt: Date?
}

final class CacheDetailModel: ObservableObject {
    @Published var currentPath: String
    @Published var entries: [ContentEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isTruncated = false

    private var history: [String] = []
    private var loadRevision = 0

    init(rootPath: String) {
        currentPath = rootPath
        load(path: rootPath, addToHistory: false)
    }

    var canGoBack: Bool { !history.isEmpty }

    func open(_ entry: ContentEntry) {
        guard entry.isDirectory else {
            NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "")
            return
        }
        load(path: entry.path, addToHistory: true)
    }

    func goBack() {
        guard let previous = history.popLast() else { return }
        load(path: previous, addToHistory: false)
    }

    func revealCurrentPath() {
        NSWorkspace.shared.selectFile(currentPath, inFileViewerRootedAtPath: "")
    }

    private func load(path: String, addToHistory: Bool) {
        if addToHistory { history.append(currentPath) }
        currentPath = path
        isLoading = true
        error = nil
        loadRevision += 1
        let revision = loadRevision

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: path),
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                    options: []
                )
                var result: [ContentEntry] = []
                result.reserveCapacity(urls.count)

                for url in urls {
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    let isDirectory = values?.isDirectory ?? false
                    let bytes = isDirectory ? self.directorySize(url.path) : Int64(values?.fileSize ?? 0)
                    result.append(ContentEntry(
                        id: url.path,
                        name: url.lastPathComponent,
                        path: url.path,
                        bytes: bytes,
                        isDirectory: isDirectory,
                        modifiedAt: values?.contentModificationDate
                    ))
                }

                result.sort {
                    if $0.bytes == $1.bytes { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    return $0.bytes > $1.bytes
                }
                let truncated = result.count > 200
                if truncated { result = Array(result.prefix(200)) }

                DispatchQueue.main.async {
                    guard revision == self.loadRevision else { return }
                    self.entries = result
                    self.isTruncated = truncated
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard revision == self.loadRevision else { return }
                    self.entries = []
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func directorySize(_ path: String) -> Int64 {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8),
                  let first = output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
                  let kilobytes = Int64(first) else { return 0 }
            return kilobytes * 1024
        } catch {
            return 0
        }
    }
}

final class CleanerModel: ObservableObject {
    @Published var cacheItems: [CacheItem] = []
    @Published var reviewItems: [ReviewItem] = []
    @Published var runtimeItems: [RuntimeItem] = []
    @Published var keptRuntimes: [String] = []
    @Published var sharedCacheBytes: Int64 = 0
    @Published var cleanSharedCache = true
    @Published var freeBytes: Int64 = 0
    @Published var totalBytes: Int64 = 1
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var status = AppLanguage.text("准备扫描", "Ready to scan")
    @Published var runtimeError: String?
    @Published var scanRevision = 0
    @Published var cleanupOutcome: CleanupOutcome?

    private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"

    var selectedBytes: Int64 {
        let caches = cacheItems.filter(\.selected).reduce(Int64(0)) { $0 + $1.bytes }
        let runtimes = runtimeItems.filter(\.selected).reduce(Int64(0)) { $0 + $1.bytes }
        let shared = cleanSharedCache ? sharedCacheBytes : 0
        return caches + runtimes + shared
    }

    var hasSelection: Bool {
        selectedBytes > 0
    }

    var selectedOptionalCount: Int {
        cacheItems.filter { !$0.recommended && $0.selected }.count
    }

    var usageFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(totalBytes - freeBytes) / Double(totalBytes), 0), 1)
    }

    func setCacheSelection(recommended: Bool, selected: Bool) {
        for index in cacheItems.indices where cacheItems[index].recommended == recommended {
            cacheItems[index].selected = selected
        }
    }

    func scan(afterCleanup outcome: CleanupOutcome? = nil) {
        guard !isScanning && !isCleaning else { return }
        isScanning = true
        status = outcome == nil
            ? AppLanguage.text("正在扫描安全缓存和模拟器…", "Scanning safe caches and simulators…")
            : AppLanguage.text("清理完成，正在重新扫描…", "Cleanup complete. Scanning again…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.performScan()
            DispatchQueue.main.async {
                self.cacheItems = result.cacheItems
                self.reviewItems = result.reviewItems
                self.runtimeItems = result.runtimeItems
                self.keptRuntimes = result.keptRuntimes
                self.sharedCacheBytes = result.sharedCacheBytes
                self.cleanSharedCache = result.sharedCacheBytes > 0
                self.freeBytes = result.freeBytes
                self.totalBytes = max(result.totalBytes, 1)
                self.runtimeError = result.runtimeError
                if let outcome {
                    self.status = outcome.issues.isEmpty
                        ? AppLanguage.text("一键清理完成", "One-click cleanup complete")
                        : AppLanguage.text("清理完成，部分项目未处理", "Cleanup complete; some items were not processed")
                    self.cleanupOutcome = outcome
                } else {
                    self.status = AppLanguage.text("扫描完成", "Scan complete")
                }
                self.isScanning = false
                self.scanRevision += 1
            }
        }
    }

    func cleanSelected() {
        guard !isCleaning && hasSelection else { return }
        let selectedCaches = cacheItems.filter(\.selected)
        let selectedRuntimes = runtimeItems.filter(\.selected)
        let shouldCleanSharedCache = cleanSharedCache && sharedCacheBytes > 0
        let selectedBytes = self.selectedBytes

        isCleaning = true
        status = AppLanguage.text("正在清理，请不要退出应用…", "Cleaning. Please keep the app open…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var messages: [String] = []
            var cleanedItemCount = 0
            let fileManager = FileManager.default
            let approvedCachePaths = Set(self.discoverCacheTargets().map(\.path))

            for item in selectedCaches {
                do {
                    if fileManager.fileExists(atPath: item.path) {
                        guard self.isSafeCacheDeletion(item.path, approvedPaths: approvedCachePaths) else {
                            messages.append(AppLanguage.text("已跳过不安全的清理路径：\(item.name)", "Skipped an unsafe cleanup path: \(item.name)"))
                            continue
                        }
                        try fileManager.removeItem(atPath: item.path)
                        cleanedItemCount += 1
                    }
                } catch {
                    messages.append(AppLanguage.text("无法清理 \(item.name)：\(error.localizedDescription)", "Could not clean \(item.name): \(error.localizedDescription)"))
                }
            }

            for runtime in selectedRuntimes {
                let result = self.runProcess(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "runtime", "delete", runtime.id],
                    xcodeEnvironment: true
                )
                if result.status != 0 {
                    messages.append(AppLanguage.text("无法删除 \(runtime.name)：\(result.output)", "Could not remove \(runtime.name): \(result.output)"))
                } else {
                    cleanedItemCount += 1
                }
            }

            if shouldCleanSharedCache {
                let result = self.runProcess(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "runtime", "dyld_shared_cache", "remove", "--all"],
                    xcodeEnvironment: true
                )
                if result.status != 0 {
                    messages.append(AppLanguage.text("无法清理 Xcode 共享缓存：\(result.output)", "Could not clean the Xcode shared cache: \(result.output)"))
                } else {
                    cleanedItemCount += 1
                }
            }

            DispatchQueue.main.async {
                self.isCleaning = false
                self.scan(afterCleanup: CleanupOutcome(
                    cleanedItemCount: cleanedItemCount,
                    selectedBytes: selectedBytes,
                    issues: messages
                ))
            }
        }
    }

    private func isSafeCacheDeletion(_ path: String, approvedPaths: Set<String>) -> Bool {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let targetURL = URL(fileURLWithPath: path).standardizedFileURL

        guard approvedPaths.contains(targetURL.path),
              targetURL.path != homeURL.path,
              targetURL.path.hasPrefix(homeURL.path + "/") else {
            return false
        }

        guard let values = try? targetURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            return false
        }

        let resolvedHome = homeURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedParent = targetURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        return resolvedParent == resolvedHome || resolvedParent.hasPrefix(resolvedHome + "/")
    }

    private func performScan() -> ScanResult {
        let (free, total) = diskSpace()

        // DeviceSupport 单独发现，因为它要按平台 + 版本逐个建项，
        // 不能像其它缓存那样整目录一项。合并之后走同一套体积统计和展示逻辑。
        let cacheTargets = discoverCacheTargets() + discoverDeviceSupportTargets()
        let reviewTargets = discoverReviewTargets()
        let sharedCachePath = "/Library/Developer/CoreSimulator/Caches/dyld"
        let allPaths = cacheTargets.map(\.path) + reviewTargets.map(\.path) + [sharedCachePath]
        let sizes = directorySizes(allPaths)

        let caches = cacheTargets.compactMap { target -> CacheItem? in
            let bytes = sizes[target.path] ?? 0
            guard bytes >= target.minimumBytes else { return nil }
            return CacheItem(
                id: target.path,
                name: target.name,
                detail: target.detail,
                path: target.path,
                bytes: bytes,
                recommended: target.recommended,
                selected: target.recommended
            )
        }.sorted { $0.bytes > $1.bytes }

        let reviews = reviewTargets.compactMap { target -> ReviewItem? in
            let bytes = sizes[target.path] ?? 0
            guard bytes > 0 else { return nil }
            return ReviewItem(
                id: target.path,
                name: target.name,
                detail: target.detail,
                path: target.path,
                bytes: bytes
            )
        }.sorted { $0.bytes > $1.bytes }

        let runtimeScan = scanRuntimes()
        let shared = sizes[sharedCachePath] ?? 0

        return ScanResult(
            cacheItems: caches,
            reviewItems: reviews,
            runtimeItems: runtimeScan.items,
            keptRuntimes: runtimeScan.kept,
            sharedCacheBytes: shared,
            freeBytes: free,
            totalBytes: total,
            runtimeError: runtimeScan.error
        )
    }

    private func discoverCacheTargets() -> [CacheTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let always: Int64 = 1
        let fiveMB: Int64 = 5 * 1024 * 1024
        var targets: [CacheTarget] = [
            /**
             DerivedData —— 构建产物。

             ⚠️ 为什么放在【建议清理】而不是可选：
                它纯粹是编译中间产物，删掉之后下次编译自动重建，
                不丢任何源码、配置或已发布的东西。
                代价是下一次编译慢一些。这是开发者最熟悉的那个目录，
                也是「Xcode 占用空间」这个搜索里最先被问到的。

             ⚠️ 路径是 ~/Library/Developer/Xcode/DerivedData，
                不是项目目录里的 DerivedData（有人会在项目里自定义位置）。
                自定义位置的那个不在我们的白名单内，不会被扫到 —— 这是对的，
                我们只处理默认位置。
             */
            CacheTarget(name: AppLanguage.text("Xcode 构建缓存（DerivedData）", "Xcode build cache (DerivedData)"), detail: AppLanguage.text("编译中间产物；下次编译自动重建", "Build intermediates; rebuilt on the next build"), path: "\(home)/Library/Developer/Xcode/DerivedData", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Codex 运行时", "Codex runtimes"), detail: AppLanguage.text("可按需重新下载", "Downloaded again when needed"), path: "\(home)/.cache/codex-runtimes", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("npm 软件包缓存", "npm package cache"), detail: AppLanguage.text("不影响已安装项目", "Does not affect installed projects"), path: "\(home)/.npm/_cacache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("npm 临时执行缓存", "npm temporary execution cache"), detail: AppLanguage.text("不影响项目源码", "Does not affect project source"), path: "\(home)/.npm/_npx", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("bun 软件包缓存", "bun package cache"), detail: AppLanguage.text("可按需重新下载", "Downloaded again when needed"), path: "\(home)/.bun/install/cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("旧 pnpm 软件包仓库", "Old pnpm package store"), detail: AppLanguage.text("旧版本软件包可重新下载", "Old packages can be downloaded again"), path: "\(home)/Library/pnpm/store/v11", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Homebrew 下载缓存", "Homebrew download cache"), detail: AppLanguage.text("不影响已安装软件", "Does not affect installed software"), path: "\(home)/Library/Caches/Homebrew", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Google 应用缓存", "Google app cache"), detail: AppLanguage.text("不含书签和密码", "Does not include bookmarks or passwords"), path: "\(home)/Library/Caches/Google", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Codex 应用缓存", "Codex app cache"), detail: AppLanguage.text("不含任务和项目文件", "Does not include tasks or project files"), path: "\(home)/Library/Caches/Codex", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("pnpm 下载缓存", "pnpm download cache"), detail: AppLanguage.text("可按需重新下载", "Downloaded again when needed"), path: "\(home)/Library/Caches/pnpm", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("微信开发者工具缓存", "WeChat DevTools cache"), detail: AppLanguage.text("不含小程序项目源码", "Does not include Mini Program source"), path: "\(home)/Library/Caches/微信开发者工具", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Node.js 编译缓存", "Node.js build cache"), detail: AppLanguage.text("可按需重新生成", "Recreated when needed"), path: "\(home)/Library/Caches/node-gyp", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Playwright 浏览器缓存", "Playwright browser cache"), detail: AppLanguage.text("后续使用时可重新下载", "Downloaded again on future use"), path: "\(home)/Library/Caches/ms-playwright", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("GitHub Desktop 更新缓存", "GitHub Desktop update cache"), detail: AppLanguage.text("不影响本地仓库", "Does not affect local repositories"), path: "\(home)/Library/Caches/com.github.GitHubClient.ShipIt", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Cursor 更新缓存", "Cursor update cache"), detail: AppLanguage.text("不影响项目和设置", "Does not affect projects or settings"), path: "\(home)/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Chrome 更新缓存", "Chrome update cache"), detail: AppLanguage.text("不含浏览数据", "Does not include browsing data"), path: "\(home)/Library/Application Support/Google/GoogleUpdater/crx_cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Chrome 组件缓存", "Chrome component cache"), detail: AppLanguage.text("不含书签和登录信息", "Does not include bookmarks or sign-in data"), path: "\(home)/Library/Application Support/Google/Chrome/component_crx_cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Chrome 扩展安装缓存", "Chrome extension install cache"), detail: AppLanguage.text("不会删除已安装扩展", "Does not remove installed extensions"), path: "\(home)/Library/Application Support/Google/Chrome/extensions_crx_cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Chrome 本地 AI 模型", "Chrome on-device AI model"), detail: AppLanguage.text("需要时会自动重新下载", "Downloaded automatically when needed"), path: "\(home)/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Cursor 页面缓存", "Cursor page cache"), detail: AppLanguage.text("不影响设置和项目", "Does not affect settings or projects"), path: "\(home)/Library/Application Support/Cursor/Cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Cursor 版本缓存", "Cursor version cache"), detail: AppLanguage.text("不影响设置和项目", "Does not affect settings or projects"), path: "\(home)/Library/Application Support/Cursor/CachedData", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Cursor 日志", "Cursor logs"), detail: AppLanguage.text("仅诊断日志", "Diagnostic logs only"), path: "\(home)/Library/Application Support/Cursor/logs", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("飞书日志", "Lark logs"), detail: AppLanguage.text("仅诊断日志", "Diagnostic logs only"), path: "\(home)/Library/Application Support/LarkShell/sdk_storage/log", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("飞书代码缓存", "Lark code cache"), detail: AppLanguage.text("清理后会自动重建", "Rebuilt automatically after cleanup"), path: "\(home)/Library/Application Support/LarkShell/CodeCache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("飞书图形缓存", "Lark graphics cache"), detail: AppLanguage.text("清理后会自动重建", "Rebuilt automatically after cleanup"), path: "\(home)/Library/Application Support/LarkShell/GrShaderCache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Obsidian 页面缓存", "Obsidian page cache"), detail: AppLanguage.text("不含笔记库", "Does not include vaults"), path: "\(home)/Library/Application Support/obsidian/Cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Obsidian 代码缓存", "Obsidian code cache"), detail: AppLanguage.text("不含笔记库", "Does not include vaults"), path: "\(home)/Library/Application Support/obsidian/Code Cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("CodeBuddy 缓存", "CodeBuddy cache"), detail: AppLanguage.text("不含项目源码", "Does not include project source"), path: "\(home)/Library/Application Support/CodeBuddy/CachedData", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("CodeBuddy CN 缓存", "CodeBuddy CN cache"), detail: AppLanguage.text("不含项目源码", "Does not include project source"), path: "\(home)/Library/Application Support/CodeBuddy CN/CachedData", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("CodeBuddy CN 页面缓存", "CodeBuddy CN page cache"), detail: AppLanguage.text("不含项目源码", "Does not include project source"), path: "\(home)/Library/Application Support/CodeBuddy CN/Cache", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("CodeBuddy CN 日志", "CodeBuddy CN logs"), detail: AppLanguage.text("仅诊断日志", "Diagnostic logs only"), path: "\(home)/Library/Application Support/CodeBuddy CN/logs", recommended: true, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("CodeBuddy Extension 日志", "CodeBuddy Extension logs"), detail: AppLanguage.text("仅诊断日志", "Diagnostic logs only"), path: "\(home)/Library/Application Support/CodeBuddyExtension/Logs", recommended: true, minimumBytes: always),

            CacheTarget(name: AppLanguage.text("Chrome 网站离线缓存", "Chrome offline website cache"), detail: AppLanguage.text("可选；网站离线内容需要重新下载", "Optional; offline website content must be downloaded again"), path: "\(home)/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Chrome 语音识别模型", "Chrome speech recognition model"), detail: AppLanguage.text("可选；语音功能会重新下载模型", "Optional; speech features will download the model again"), path: "\(home)/Library/Application Support/Google/Chrome/SODA", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("Chrome 语音语言包", "Chrome speech language packs"), detail: AppLanguage.text("可选；语音功能会重新下载语言包", "Optional; speech features will download language packs again"), path: "\(home)/Library/Application Support/Google/Chrome/SODALanguagePacks", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("动态壁纸资源", "Dynamic wallpaper resources"), detail: AppLanguage.text("可选；使用时可能重新下载", "Optional; may be downloaded again when used"), path: "\(home)/Library/Application Support/com.apple.wallpaper/aerials", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("WPS PDF 预览缓存", "WPS PDF preview cache"), detail: AppLanguage.text("可选；PDF 首次打开会重新生成", "Optional; regenerated when a PDF is first opened"), path: "\(home)/Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/PDF/Cache", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("WPS 插件资源", "WPS add-on resources"), detail: AppLanguage.text("可选；使用相关功能时会重新下载", "Optional; downloaded again when the feature is used"), path: "\(home)/Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/wps/addons/pool", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("WPS 在线字体缓存", "WPS online font cache"), detail: AppLanguage.text("可选；使用字体时会重新下载", "Optional; fonts will be downloaded again when used"), path: "\(home)/Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/office6/data/fonts/online_ext_font_cache", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("微信日志", "WeChat logs"), detail: AppLanguage.text("可选；不含聊天消息和附件", "Optional; does not include messages or attachments"), path: "\(home)/Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/log", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("微信文件临时缓存", "WeChat temporary file cache"), detail: AppLanguage.text("可选；不含聊天消息数据库", "Optional; does not include the message database"), path: "\(home)/Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/radium/xfile/cache", recommended: false, minimumBytes: always),
            CacheTarget(name: AppLanguage.text("微信页面缓存", "WeChat page cache"), detail: AppLanguage.text("可选；页面内容会重新加载", "Optional; page content will be loaded again"), path: "\(home)/Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/radium/cache", recommended: false, minimumBytes: always)
        ]

        let wechatDevTools = "\(home)/Library/Application Support/微信开发者工具"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: wechatDevTools) {
            for entry in entries where !entry.hasPrefix(".") {
                let cachePath = "\(wechatDevTools)/\(entry)/WeappCache"
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: cachePath, isDirectory: &isDirectory), isDirectory.boolValue {
                    targets.append(CacheTarget(name: AppLanguage.text("微信开发者工具编译缓存", "WeChat DevTools build cache"), detail: AppLanguage.text("不含小程序项目源码", "Does not include Mini Program source"), path: cachePath, recommended: true, minimumBytes: always))
                }
            }
        }

        let wechatFiles = "\(home)/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files"
        if let accounts = try? FileManager.default.contentsOfDirectory(atPath: wechatFiles) {
            for account in accounts where account != "all_users" && !account.hasPrefix(".") {
                let cachePath = "\(wechatFiles)/\(account)/cache"
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: cachePath, isDirectory: &isDirectory), isDirectory.boolValue {
                    targets.append(CacheTarget(name: AppLanguage.text("微信账号临时缓存", "WeChat account temporary cache"), detail: AppLanguage.text("可选；不含消息、图片和附件原文件", "Optional; does not include original messages, images or attachments"), path: cachePath, recommended: false, minimumBytes: always))
                }
            }
        }

        var seen = Set<String>()
        targets = targets.compactMap { target in
            guard seen.insert(target.path).inserted else { return nil }
            return target
        }

        let libraryCaches = "\(home)/Library/Caches"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: libraryCaches) {
            for entry in entries where !entry.hasPrefix(".") {
                let path = "\(libraryCaches)/\(entry)"
                guard !seen.contains(path) else { continue }
                targets.append(CacheTarget(
                    name: AppLanguage.text("其他应用缓存 · \(entry)", "Other app cache · \(entry)"),
                    detail: AppLanguage.text("可选；应用可能在下次启动时重新生成", "Optional; the app may recreate it on next launch"),
                    path: path,
                    recommended: false,
                    minimumBytes: fiveMB
                ))
            }
        }

        return targets
    }

    /**
     真机调试支持文件（DeviceSupport）。

     ⚠️ 为什么按【每个版本】拆成独立一项，而不是整个目录一项：
        用户真正要做的决定是「留哪几个版本」——例如「只留最新的，其他删掉」。
        做成一项的话他只能全删或全不删，那不叫「看清了再决定」。
        和模拟器运行时的处理方式保持一致（也是每个运行时一项）。

     ⚠️ 为什么可以安全删除：
        它们是连接真机调试时 Xcode 从设备上抓取的符号文件。
        删掉后下次连接那台设备会重新抓取，等几分钟，不影响任何已构建的东西。
        换过设备的人，旧设备的这些文件基本永远不会再用。
     */
    private func discoverDeviceSupportTargets() -> [CacheTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let platforms: [(folder: String, label: String)] = [
            ("iOS DeviceSupport", "iOS"),
            ("watchOS DeviceSupport", "watchOS"),
            ("tvOS DeviceSupport", "tvOS"),
            ("visionOS DeviceSupport", "visionOS")
        ]

        var targets: [CacheTarget] = []
        for platform in platforms {
            let base = "\(home)/Library/Developer/Xcode/\(platform.folder)"
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }

            for entry in entries where !entry.hasPrefix(".") {
                let path = "\(base)/\(entry)"
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                targets.append(CacheTarget(
                    name: "\(platform.label) \(entry)",
                    detail: AppLanguage.text(
                        "真机调试支持文件；下次连接该设备会重新抓取",
                        "Device support files; fetched again next time that device connects"
                    ),
                    path: path,
                    recommended: false,
                    // ⚠️ 这里不能用 always —— 它是 discoverCacheTargets 里的局部常量。
                    //    语义相同：只要目录存在且大于 0 字节就显示。
                    minimumBytes: 1
                ))
            }
        }
        return targets
    }

    private func discoverReviewTargets() -> [(name: String, detail: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            (AppLanguage.text("下载文件", "Downloads"), AppLanguage.text("个人文件；请确认用途后在访达中处理", "Personal files; review them in Finder before removing"), "\(home)/Downloads"),
            (AppLanguage.text("iCloud 云盘", "iCloud Drive"), AppLanguage.text("云端个人文件；删除会同步到其他设备", "Cloud files; deletions sync to your other devices"), "\(home)/Library/Mobile Documents/com~apple~CloudDocs"),
            (AppLanguage.text("微信聊天数据", "WeChat chat data"), AppLanguage.text("请优先在微信的存储管理中清理", "Use WeChat Storage Management first"), "\(home)/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files"),
            (AppLanguage.text("WPS 自动备份", "WPS automatic backups"), AppLanguage.text("可能用于恢复未保存文档，不支持一键删除", "May recover unsaved documents; not included in one-click cleanup"), "\(home)/Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/office6/data/backup")
        ]
    }

    private func scanRuntimes() -> (items: [RuntimeItem], kept: [String], error: String?) {
        guard FileManager.default.fileExists(atPath: developerDirectory) else {
            return ([], [], AppLanguage.text("未找到 Xcode，已跳过模拟器扫描。", "Xcode was not found, so simulator scanning was skipped."))
        }

        let result = runProcess(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "runtime", "list", "--json"],
            xcodeEnvironment: true
        )
        guard result.status == 0, let data = result.output.data(using: .utf8) else {
            return ([], [], AppLanguage.text("无法读取 Xcode 模拟器：\(result.output)", "Could not read Xcode simulators: \(result.output)"))
        }

        do {
            let dictionary = try JSONDecoder().decode([String: RuntimeInfo].self, from: data)
            let ready = dictionary.values.filter { $0.state == "Ready" }
            let grouped = Dictionary(grouping: ready, by: \.platformIdentifier)
            var oldItems: [RuntimeItem] = []
            var kept: [String] = []

            for (_, values) in grouped {
                let sorted = values.sorted { lhs, rhs in
                    let versionOrder = lhs.version.compare(rhs.version, options: .numeric)
                    if versionOrder == .orderedSame {
                        return lhs.build.compare(rhs.build, options: .numeric) == .orderedDescending
                    }
                    return versionOrder == .orderedDescending
                }

                if let newest = sorted.first {
                    kept.append("\(platformName(newest.platformIdentifier)) \(newest.version)")
                }

                for runtime in sorted.dropFirst() where runtime.deletable != false {
                    oldItems.append(RuntimeItem(
                        id: runtime.identifier,
                        name: "\(platformName(runtime.platformIdentifier)) \(runtime.version)",
                        detail: AppLanguage.text("旧版运行时 · Build \(runtime.build)", "Old runtime · Build \(runtime.build)"),
                        bytes: runtime.sizeBytes ?? 0,
                        selected: true
                    ))
                }
            }

            oldItems.sort { lhs, rhs in
                if lhs.name == rhs.name { return lhs.detail < rhs.detail }
                return lhs.name < rhs.name
            }
            kept.sort()
            return (oldItems, kept, nil)
        } catch {
            return ([], [], AppLanguage.text("模拟器数据解析失败：\(error.localizedDescription)", "Could not parse simulator data: \(error.localizedDescription)"))
        }
    }

    private func platformName(_ identifier: String) -> String {
        if identifier.contains("iphone") { return "iOS" }
        if identifier.contains("watch") { return "watchOS" }
        if identifier.contains("appletv") { return "tvOS" }
        if identifier.contains("xrsimulator") { return "visionOS" }
        return "Simulator"
    }

    private func directorySize(_ path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let result = runProcess(executable: "/usr/bin/du", arguments: ["-sk", path], xcodeEnvironment: false)
        guard result.status == 0,
              let first = result.output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
              let kilobytes = Int64(first) else { return 0 }
        return kilobytes * 1024
    }

    private func directorySizes(_ paths: [String]) -> [String: Int64] {
        let existing = Array(Set(paths.filter { FileManager.default.fileExists(atPath: $0) })).sorted()
        guard !existing.isEmpty else { return [:] }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk"] + existing
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [:] }

            var result: [String: Int64] = [:]
            for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let tab = rawLine.firstIndex(of: "\t") else { continue }
                let sizePart = rawLine[..<tab]
                let pathPart = rawLine[rawLine.index(after: tab)...]
                guard let kilobytes = Int64(sizePart.trimmingCharacters(in: .whitespaces)) else { continue }
                result[String(pathPart)] = kilobytes * 1024
            }
            return result
        } catch {
            return [:]
        }
    }

    private func diskSpace() -> (Int64, Int64) {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/System/Volumes/Data")
            let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 1
            return (free, total)
        } catch {
            return (0, 1)
        }
    }

    private func runProcess(executable: String, arguments: [String], xcodeEnvironment: Bool) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        if xcodeEnvironment {
            var environment = ProcessInfo.processInfo.environment
            environment["DEVELOPER_DIR"] = developerDirectory
            process.environment = environment
        }

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}

struct CacheDetailView: View {
    let item: CacheItem
    @StateObject private var model: CacheDetailModel
    @Environment(\.dismiss) private var dismiss

    private let formatter: ByteCountFormatter = {
        let value = ByteCountFormatter()
        value.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        value.countStyle = .file
        value.isAdaptive = true
        return value
    }()

    private let dateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.dateStyle = .medium
        value.timeStyle = .short
        return value
    }()

    init(item: CacheItem) {
        self.item = item
        _model = StateObject(wrappedValue: CacheDetailModel(rootPath: item.path))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(item.recommended ? Color.green : Color.orange)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.title3.weight(.semibold))
                    Text(AppLanguage.text("总大小 \(format(item.bytes))", "Total size \(format(item.bytes))"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(AppLanguage.text("完成", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            HStack(spacing: 10) {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help(AppLanguage.text("返回上级", "Go back"))
                .disabled(!model.canGoBack || model.isLoading)

                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(model.currentPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    model.revealCurrentPath()
                } label: {
                    Image(systemName: "arrow.forward.circle")
                }
                .buttonStyle(.borderless)
                .help(AppLanguage.text("在访达中显示", "Show in Finder"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            if model.isLoading {
                Spacer()
                ProgressView(AppLanguage.text("正在读取内容…", "Loading contents…"))
                Spacer()
            } else if let error = model.error {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text(error).foregroundStyle(.secondary)
                }
                Spacer()
            } else if model.entries.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(AppLanguage.text("目录为空", "This folder is empty")).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(model.entries) { entry in
                    Button {
                        model.open(entry)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let modifiedAt = entry.modifiedAt {
                                    Text(dateFormatter.string(from: modifiedAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(format(entry.bytes))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: entry.isDirectory ? "chevron.right" : "arrow.forward.circle")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Image(systemName: "eye.fill").foregroundStyle(.secondary)
                Text(model.isTruncated ? AppLanguage.text("只读预览 · 显示最大的 200 个项目", "Read-only preview · Showing the 200 largest items") : AppLanguage.text("只读预览", "Read-only preview"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AppLanguage.text("清理时将移除整个所选缓存目录", "Cleanup removes the entire selected cache folder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 720, height: 560)
    }

    private func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(bytes, 0))
    }
}

struct CleanerView: View {
    @StateObject private var model = CleanerModel()
    @State private var showConfirmation = false
    @State private var inspectedCache: CacheItem?

    private let formatter: ByteCountFormatter = {
        let value = ByteCountFormatter()
        value.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        value.countStyle = .file
        value.includesUnit = true
        value.isAdaptive = true
        return value
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 0).id("scanTop")
                        recommendedCacheSection
                        optionalCacheSection
                        runtimeSection
                        sharedCacheSection
                        reviewSection
                    }
                    .padding(24)
                }
                .onChange(of: model.scanRevision) { _, _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo("scanTop", anchor: .top)
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: 780, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.scan() }
        .alert(AppLanguage.text("确认一键清理", "Confirm one-click cleanup"), isPresented: $showConfirmation) {
            Button(AppLanguage.text("取消", "Cancel"), role: .cancel) {}
            Button(AppLanguage.text("清理", "Clean"), role: .destructive) { model.cleanSelected() }
        } message: {
            Text(confirmationMessage)
        }
        .alert(item: $model.cleanupOutcome) { outcome in
            Alert(
                title: Text(outcome.issues.isEmpty
                    ? AppLanguage.text("一键清理完成", "One-click cleanup complete")
                    : AppLanguage.text("清理完成，部分项目未处理", "Cleanup complete; some items were not processed")),
                message: Text(cleanupOutcomeMessage(outcome)),
                dismissButton: .default(Text(AppLanguage.text("完成", "Done")))
            )
        }
        .sheet(item: $inspectedCache) { item in
            CacheDetailView(item: item)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .frame(width: 44, height: 44)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguage.text("Mac 空间清理", "Mac Space Cleaner"))
                    .font(.title2.weight(.semibold))
                Text(AppLanguage.text("仅清理可重新生成的缓存和旧版模拟器", "Clean regenerable caches and old simulators only"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppLanguage.text("可用 \(format(model.freeBytes))", "Available \(format(model.freeBytes))"))
                    .font(.headline)
                ProgressView(value: model.usageFraction)
                    .frame(width: 180)
                    .tint(model.usageFraction > 0.9 ? .red : (model.usageFraction > 0.8 ? .orange : .green))
                Text(AppLanguage.text("总计 \(format(model.totalBytes))", "Total \(format(model.totalBytes))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.scan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(AppLanguage.text("重新扫描", "Scan again"))
            .disabled(model.isScanning || model.isCleaning)
        }
        .padding(20)
    }

    private var recommendedCacheSection: some View {
        let indices = model.cacheItems.indices.filter { model.cacheItems[$0].recommended }
        return VStack(alignment: .leading, spacing: 10) {
            selectionSectionTitle(AppLanguage.text("建议清理", "Recommended cleanup"), icon: "checkmark.shield.fill", recommended: true)
            Text(AppLanguage.text("经过核实的缓存和日志，默认勾选；不会删除个人内容。", "Verified caches and logs are selected by default. Personal content is not removed."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if indices.isEmpty {
                emptyRow(AppLanguage.text("未发现建议清理的缓存", "No recommended caches found"))
            } else {
                VStack(spacing: 0) {
                    ForEach(indices, id: \.self) { index in
                        targetRow(
                            title: model.cacheItems[index].name,
                            detail: model.cacheItems[index].detail,
                            bytes: model.cacheItems[index].bytes,
                            selected: $model.cacheItems[index].selected,
                            icon: "checkmark.shield",
                            onInspect: { inspectedCache = model.cacheItems[index] }
                        )
                        if index != indices.last { Divider().padding(.leading, 44) }
                    }
                }
            }
        }
    }

    private var optionalCacheSection: some View {
        let indices = model.cacheItems.indices.filter { !model.cacheItems[$0].recommended }
        return VStack(alignment: .leading, spacing: 10) {
            selectionSectionTitle(AppLanguage.text("可选清理", "Optional cleanup"), icon: "slider.horizontal.3", recommended: false)
            Text(AppLanguage.text("默认不勾选。清理后可能重新下载资源、重新生成预览或丢失离线网页。", "Not selected by default. Resources may be downloaded again, previews rebuilt, or offline pages removed."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if indices.isEmpty {
                emptyRow(AppLanguage.text("未发现较大的可选缓存", "No large optional caches found"))
            } else {
                VStack(spacing: 0) {
                    ForEach(indices, id: \.self) { index in
                        targetRow(
                            title: model.cacheItems[index].name,
                            detail: model.cacheItems[index].detail,
                            bytes: model.cacheItems[index].bytes,
                            selected: $model.cacheItems[index].selected,
                            icon: "shippingbox",
                            onInspect: { inspectedCache = model.cacheItems[index] }
                        )
                        if index != indices.last { Divider().padding(.leading, 44) }
                    }
                }
            }
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLanguage.text("旧版 Xcode 模拟器", "Old Xcode simulators"), icon: "iphone.gen3")
            if let error = model.runtimeError {
                messageRow(error, icon: "exclamationmark.triangle.fill", color: .orange)
            } else if model.runtimeItems.isEmpty {
                emptyRow(AppLanguage.text("没有旧版运行时；已保留 \(model.keptRuntimes.joined(separator: "、"))", "No old runtimes found; kept \(model.keptRuntimes.joined(separator: ", "))"))
            } else {
                VStack(spacing: 0) {
                    ForEach(model.runtimeItems.indices, id: \.self) { index in
                        targetRow(
                            title: model.runtimeItems[index].name,
                            detail: model.runtimeItems[index].detail,
                            bytes: model.runtimeItems[index].bytes,
                            selected: $model.runtimeItems[index].selected,
                            icon: "iphone.gen3"
                        )
                        if index < model.runtimeItems.indices.last! { Divider().padding(.leading, 44) }
                    }
                }
                Text(AppLanguage.text("自动保留每个平台的最新版本：\(model.keptRuntimes.joined(separator: "、"))", "The newest version for each platform is kept automatically: \(model.keptRuntimes.joined(separator: ", "))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sharedCacheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLanguage.text("Xcode 共享缓存", "Xcode shared cache"), icon: "hammer.fill")
            if model.sharedCacheBytes > 0 {
                targetRow(
                    title: AppLanguage.text("模拟器 dyld 共享缓存", "Simulator dyld shared cache"),
                    detail: AppLanguage.text("删除后按需重建；首次启动模拟器会稍慢", "Rebuilt when needed; the first simulator launch may be slower"),
                    bytes: model.sharedCacheBytes,
                    selected: $model.cleanSharedCache,
                    icon: "hammer"
                )
            } else {
                emptyRow(AppLanguage.text("当前没有 Xcode 共享缓存", "No Xcode shared cache found"))
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLanguage.text("仅查看的个人数据", "Personal data — view only"), icon: "folder.badge.questionmark")
            Text(AppLanguage.text("这些内容不会参与一键清理。需要处理时，请先在对应应用或访达中确认。", "These items are never included in one-click cleanup. Review them in the relevant app or Finder first."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.reviewItems.isEmpty {
                emptyRow(AppLanguage.text("未发现需要人工检查的目录", "No folders require manual review"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.reviewItems.enumerated()), id: \.element.id) { offset, item in
                        reviewRow(item)
                        if offset < model.reviewItems.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.isScanning || model.isCleaning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: model.runtimeError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.runtimeError == nil ? .green : .orange)
            }

            Text(model.status)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(AppLanguage.text("预计最多释放", "Up to"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(format(model.selectedBytes))
                    .font(.headline.monospacedDigit())
            }

            Button {
                showConfirmation = true
            } label: {
                Label(AppLanguage.text("一键清理", "Clean selected"), systemImage: "sparkles")
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.hasSelection || model.isScanning || model.isCleaning)
        }
        .padding(18)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.headline)
        }
    }

    private func selectionSectionTitle(_ title: String, icon: String, recommended: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(recommended ? Color.green : Color.orange)
                .frame(width: 20)
            Text(title)
                .font(.headline)
            Spacer()
            Button(AppLanguage.text("全选", "Select all")) { model.setCacheSelection(recommended: recommended, selected: true) }
                .buttonStyle(.borderless)
                .disabled(model.isScanning || model.isCleaning)
            Button(AppLanguage.text("取消", "Clear")) { model.setCacheSelection(recommended: recommended, selected: false) }
                .buttonStyle(.borderless)
                .disabled(model.isScanning || model.isCleaning)
        }
    }

    private func targetRow(
        title: String,
        detail: String,
        bytes: Int64,
        selected: Binding<Bool>,
        icon: String,
        onInspect: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: selected)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(format(bytes))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            if let onInspect {
                Button(action: onInspect) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help(AppLanguage.text("查看具体内容", "View contents"))
            }
        }
        .frame(minHeight: 50)
    }

    private func reviewRow(_ item: ReviewItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.medium))
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(format(item.bytes))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "arrow.forward.circle")
            }
            .buttonStyle(.borderless)
            .help(AppLanguage.text("在访达中显示", "Show in Finder"))
        }
        .frame(minHeight: 50)
    }

    private func emptyRow(_ text: String) -> some View {
        messageRow(text, icon: "checkmark.circle", color: .green)
    }

    private func messageRow(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(minHeight: 44)
    }

    private func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(bytes, 0))
    }

    private var confirmationMessage: String {
        var text = AppLanguage.text("预计最多释放 \(format(model.selectedBytes))。", "Up to \(format(model.selectedBytes)) will be released. ")
        if model.selectedOptionalCount > 0 {
            text += AppLanguage.text("你选择了 \(model.selectedOptionalCount) 个可选项目，相关资源之后可能重新下载。", "You selected \(model.selectedOptionalCount) optional item(s); related resources may be downloaded again. ")
        }
        text += AppLanguage.text("不会删除文稿、下载、iCloud、微信聊天附件或项目文件。", "Documents, Downloads, iCloud files, WeChat attachments and project files will not be removed.")
        return text
    }

    private func cleanupOutcomeMessage(_ outcome: CleanupOutcome) -> String {
        let cleanedSummary = AppLanguage.text(
            "已处理 \(outcome.cleanedItemCount) 个项目，本次选择约 \(format(outcome.selectedBytes))。磁盘已重新扫描。",
            "Processed \(outcome.cleanedItemCount) item\(outcome.cleanedItemCount == 1 ? "" : "s") totaling about \(format(outcome.selectedBytes)). The disk has been scanned again."
        )
        guard !outcome.issues.isEmpty else { return cleanedSummary }

        let visibleIssues = outcome.issues.prefix(3).joined(separator: "\n")
        let remainingCount = outcome.issues.count - min(outcome.issues.count, 3)
        let remaining = remainingCount > 0
            ? AppLanguage.text("\n另有 \(remainingCount) 条未显示。", "\n\(remainingCount) more issue\(remainingCount == 1 ? "" : "s") not shown.")
            : ""
        return "\(cleanedSummary)\n\n\(visibleIssues)\(remaining)"
    }
}

@main
struct MacSpaceCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            CleanerView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
