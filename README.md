# HyesRead

HyesRead 是一款把书架、阅读进度和阅读统计保存在本机的电子书阅读器。

## 功能

- 阅读 EPUB、PDF、MOBI、AZW3/KF8、FB2/FBZ、CBZ、TXT 和 Markdown 文件。
- Windows 可扫描本地文件夹，分批显示书籍并支持取消；浏览器版可选择文件直接阅读。
- Android 手机可安装 APK；手机浏览器也可直接使用网页版本。
- Windows 可浏览 OPDS/Calibre 目录、进入分类、翻页并下载书籍。需要登录时分别填写账号和密码，凭据保存在 Windows 系统凭据管理器，旧地址中的账号密码自动迁移。带账号的远程目录必须使用 HTTPS，本机回环地址允许 HTTP。详见[目录账号说明](docs/opds-credentials.md)。
- 按书名和作者搜索、排序和管理书架。
- 在可重排格式中搜索正文和目录、标记文字高亮；文本型 PDF 可搜索正文、跳转到命中页并持久化文字高亮。切换分页或滚动，并调整字号、行距和背景主题；TXT/Markdown 支持滚动阅读及相同的显示设置。
- 在支持的阅读格式中添加书签并恢复阅读位置；书架信息、位置、高亮、书签和阅读统计保存在本机。桌面版从书架移除文件不会删除硬盘原件。
- 设置中可导出和恢复书架索引、进度、书签、标注、统计及目录来源；新版备份带 SHA-256 清单完整性校验，导入前会拒绝被篡改或损坏的数据。导出时从目录地址移除账号和密码，换设备后需重新填写登录信息。换设备后选择书籍文件夹，可按相对路径恢复匹配的阅读数据；重复路径无法唯一判断时不会自动关联。
- 设置中提供本机系统自检与诊断报告导出。故障记录有数量和文件大小上限，不会自动上传；目录账号和用户主目录信息在报告中会先脱敏。
- 无需账号；书架信息、阅读进度和统计存储在本机。
- 浏览器版不提供在线目录。

## 运行

### Windows 安装版

在 [GitHub Releases](https://github.com/hy3560/HyesRead/releases/latest) 下载 Windows x64 安装包。也可以继续按下方步骤从源码运行。

### Android 安装版

Android ARM64 的签名 APK 与 Google Play AAB 会一起发布在 [GitHub Releases](https://github.com/hy3560/HyesRead/releases/latest)。APK 用于直接安装，AAB 用于 Google Play；签名密钥配置并完成验收后才会发布。多数近年的 Android 手机使用 ARM64。签名流程见[Android 发布说明](docs/android-release.md)。

正式 Release 同时提供 `SHA256SUMS.txt`，用于核对 Windows EXE、Android APK 和 AAB 的下载完整性。
Windows PowerShell 可运行 `./scripts/download-verified-release.ps1 -Tag v0.1.27`，将指定版本下载到 `dist/releases/版本号` 并核对摘要、大小和 SBOM；已存在但摘要不符的文件会报错并保留。
同时提供 SPDX JSON `sbom.spdx.json` 软件物料清单；Pull Request 新增依赖会经过漏洞等级与许可证门禁，避免无意引入高危或强 copyleft 依赖。

### 浏览器版

手机浏览器可直接打开 [HyesRead 手机网页](https://hy3560.github.io/HyesRead/)。网页书架和阅读记录保存在当前浏览器中；可通过“添加文件”选择书籍。浏览器无法扫描手机文件夹，且网页端暂不支持 OPDS 目录。

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
pnpm test:native
```

完整的 Windows 安装包构建由 GitHub Actions 在每次主分支更新和拉取请求时执行。
原生验收会自行构建独立标识的测试应用，检查真实阅读、重启恢复、目录扫描与取消；测试产物不用于日常安装。扫描行为和验证范围见[本机书库扫描](docs/library-scanning.md)。
