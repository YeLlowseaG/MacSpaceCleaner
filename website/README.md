# Mac 空间清理官网

这是一个无需后端的静态网站，包含主页、隐私政策、使用帮助和可下载的 DMG。

## 本地预览

```bash
cd "/Volumes/MacT7/projectDocuments/MacSpaceCleaner/website"
python3 -m http.server 8080
```

然后访问 `http://localhost:8080/`。

## 部署前检查

- 确认 `downloads/` 中的 DMG、版本号和 SHA-256 已更新
- 决定正式域名和反馈联系方式
- 部署后测试下载链接和移动端页面
- 如果托管平台启用了访问分析或 Cookie，更新隐私政策

## 可选托管平台

- GitHub Pages
- Cloudflare Pages
- Vercel
- Netlify
- 任意支持静态文件的服务器
