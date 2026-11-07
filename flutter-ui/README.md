# HyesRead · Flutter 阅读器

HyesRead 是一款以本地藏书和舒适阅读为中心的应用。这个 Flutter 版本提供 Android 和 Windows 界面，与既有桌面版本分别安装，书库不自动互相迁移。

## 功能

- 导入、检索、收藏和管理本机书籍，支持继续阅读、书签与阅读百分比。
- TXT / Markdown：分页或滚动阅读、书内全文搜索、字体和纸张设置。
- EPUB：章节阅读、目录、排版调节和阅读位置恢复。
- PDF：原生 PDF 浏览与页码定位。
- 浅色、深色共用一套界面布局；减少动画模式可关闭装饰动效。

## 安装

**Windows：** 解压完整的 Windows x64 便携包，运行 `HyesRead.exe`。不要只复制 EXE；同目录中的 DLL 和 `data` 文件夹都必须保留。

**Android：** 安装项目构建的 APK。当前 APK 使用调试密钥签名，并非应用商店签名版。

本版本使用独立应用数据目录，不会自动修改旧版 HyesRead 的藏书。重要书籍仍建议保留原件备份。

## 源码构建

需要 Flutter SDK、相应平台工具链和 Android SDK（构建 Android 时）。在本目录执行：

```sh
flutter pub get --enforce-lockfile
flutter test
flutter build apk --release
```

Windows 的 Flutter 插件需要符号链接支持，普通构建可能要求启用开发者模式；缺少该权限时 `flutter pub get` 可能在解析依赖后失败。可使用 `flutter build windows --release`；项目内 `tool/build_windows_portable.ps1` 是原开发环境的辅助脚本，依赖项目内 `.flutter_sdk` 和脚本指定的 Visual Studio 2022 Community 路径，换环境时需调整。指定其他 pub 镜像或 SDK 版本可能导致锁文件无法严格复用，应先核对配置，不要静默升级依赖。

## 当前限制

TXT / Markdown 采用 UTF-8，单本不超过 20 MiB；EPUB 单本不超过 50 MiB。EPUB 和 PDF 暂不提供书内全文搜索。阅读百分比反映当前阅读位置，EPUB 依据全书内容块计算，不能视为剩余阅读时间。

第三方组件及字体的授权信息见依赖清单和 `assets/fonts/LICENSE_NOTICE.md`。
