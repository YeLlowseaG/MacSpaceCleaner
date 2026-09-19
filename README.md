# Mac 空间清理

一个原生 macOS SwiftUI 清理工具，以及它的静态官网。

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
