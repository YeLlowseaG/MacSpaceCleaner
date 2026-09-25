# Mac 空间清理

一个原生 macOS SwiftUI 缓存清理工具，以及它的静态官网。

**看清缓存，再决定清理。**

Mac 空间清理用于识别常见应用缓存、开发工具缓存，以及 Xcode 的三类大块占用：旧版模拟器运行时、构建缓存（DerivedData）和真机调试支持文件（DeviceSupport）。建议清理与可选清理分开显示；下载、iCloud 云盘、微信聊天数据和 WPS 备份只读展示，不会进入一键清理。

- 官网：<https://mac-space-cleaner.vercel.app/>
- 下载：<https://mac-space-cleaner.vercel.app/downloads/MacSpaceCleaner-1.3.dmg>
- 常见问题：<https://mac-space-cleaner.vercel.app/faq.html>
- 隐私政策：<https://mac-space-cleaner.vercel.app/privacy.html>

## 产品信息

- 当前版本：1.3（Build 5）
- 系统要求：macOS 14 或更高版本
- 架构：Apple Silicon 与 Intel Universal Binary
- 分发：Developer ID 签名、Hardened Runtime、Apple 公证与票据装订
- 隐私：扫描在本机完成，不上传文件路径、扫描结果或清理记录

## 主要功能

- 扫描常见应用缓存、日志和更新缓存
- 识别 npm、pnpm、bun、Homebrew、Playwright 等开发缓存
- 识别旧版 Xcode 模拟器，并保留每个平台的最新版本
- 识别 Xcode 构建缓存（DerivedData），删除后下次编译自动重建
- 识别真机调试支持文件（DeviceSupport），按平台和版本逐个列出
- 显示模拟器 dyld 共享缓存
- 清理前查看路径、目录内容、大小和修改时间
- 可选项目默认不勾选，个人数据不参与一键清理

## 项目目录

- `MacSpaceCleaner.swift`：App 主程序
- `release.sh`：编译通用版本、签名并生成 DMG
- `notarize.sh`：提交 Apple 公证并装订票据
- `website/`：可部署到 Vercel、GitHub Pages、Cloudflare Pages 等平台的静态官网
- `website/downloads/`：官网提供下载的已公证 DMG
- `docs/`：产品和发布说明

## Vercel 部署

从 GitHub 导入仓库后，在 Vercel 项目设置中填写：

- Framework Preset：`Other`
- Root Directory：`website`
- Build Command：留空
- Output Directory：`.`
- Install Command：留空

这是纯静态网站，不需要 Node.js 构建或服务器端环境变量。

## 本地预览官网

```bash
cd website
python3 -m http.server 8080
```

然后访问 `http://127.0.0.1:8080/`。

## 本地构建 App

```bash
./release.sh
./notarize.sh
```

签名证书私钥和公证凭据只保存在开发者自己的 Mac 钥匙串中，不应提交到 GitHub。
