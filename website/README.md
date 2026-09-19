# Mac 空间清理官网

这是一个无需后端的静态网站，包含主页、隐私政策、使用帮助、FAQ 和可下载的 DMG。

主页已加入 canonical、Open Graph、SoftwareApplication JSON-LD；FAQ 页已加入 FAQPage JSON-LD；`sitemap.xml`、`robots.txt` 和 `llms.txt` 用于搜索引擎与生成式搜索理解网站内容。

## 更换正式域名

当前结构化数据和站点地图暂使用 Vercel 域名 `mac-space-cleaner.vercel.app`。绑定自定义域名后，请全局替换 HTML、`robots.txt`、`sitemap.xml` 和 `llms.txt` 中的域名，并重新部署。

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
