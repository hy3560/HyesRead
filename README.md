# HyesRead

HyesRead 是一款把书架、阅读进度和阅读统计保存在本机的电子书阅读器。

## 功能

- 阅读 EPUB、PDF、MOBI、AZW3/KF8、FB2/FBZ、CBZ、TXT 和 Markdown 文件。
- 桌面版可以扫描本地文件夹；浏览器版可选择文件直接阅读。
- Windows 桌面版可浏览 OPDS/Calibre 目录、进入分类、翻页并下载书籍到本地。
- 按书名和作者搜索、排序和管理书架。
- 在可重排格式中搜索正文和目录、标记文字高亮；文本型 PDF 可搜索正文、跳转到命中页并持久化文字高亮。切换分页或滚动，并调整字号、行距和背景主题；TXT/Markdown 支持滚动阅读及相同的显示设置。
- 在支持的阅读格式中添加书签并恢复阅读位置；书架信息、位置、高亮、书签和阅读统计保存在本机。桌面版从书架移除文件不会删除硬盘原件。
- 设置中可导出和合并恢复书架索引、进度、书签、标注、统计及目录来源；备份不包含书籍文件，阅读数据按书籍原路径关联。
- 无需账号；书架信息、阅读进度和统计存储在本机。
- 目录连接使用无需登录的 OPDS Atom 地址；浏览器版不提供在线目录。

## 运行

### Windows 安装版

在 [GitHub Releases](https://github.com/hy3560/HyesRead/releases/latest) 下载 Windows x64 安装包。也可以继续按下方步骤从源码运行。

### 浏览器版

安装 Node.js 和 pnpm 后，在项目目录运行：

```bash
pnpm install --frozen-lockfile
pnpm dev
```

打开终端显示的本地网址，选择“添加文件”即可阅读。静态部署时运行 `pnpm build`，将生成的 `out` 目录发布到静态网站服务。浏览器安全限制不允许网页扫描本机文件夹。

### 桌面版

除 Node.js 和 pnpm 外，还需要 Rust 工具链及 Tauri 对应平台的系统依赖。

```bash
pnpm install --frozen-lockfile
pnpm tauri dev
```

生成桌面安装包：

```bash
pnpm tauri build
```

## 验证

运行类型检查、依赖安全审计和桌面/手机尺寸的阅读器回归测试：

```bash
pnpm lint
pnpm audit --prod --registry=https://registry.npmjs.org
pnpm exec playwright install chromium
pnpm test:e2e
```

Windows 桌面端还可以直接启动 WebView2 并验证 EPUB 正文：

```powershell
pnpm tauri build --bundles msi
pnpm test:native
```

完整的 Windows 安装包构建由 GitHub Actions 在每次主分支更新和拉取请求时执行。
