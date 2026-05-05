# HyesRead

<div align="center">
  <img src="assets/icon/icon.png" alt="HyesRead Logo" width="128" height="128">
  
  <h3>优雅的跨平台电子书阅读器</h3>
  
  <p>
    <a href="#特性">特性</a> •
    <a href="#安装">安装</a> •
    <a href="#使用">使用</a> •
    <a href="#开发">开发</a> •
    <a href="#贡献">贡献</a>
  </p>
  
  <p>
    <img src="https://img.shields.io/badge/Flutter-3.24.0-blue?logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
    <img src="https://img.shields.io/github/v/release/yourusername/hyesread" alt="Release">
  </p>
</div>

---

## 特性

### 🎨 优雅的设计
- **毛玻璃效果 UI**：现代化的视觉体验，支持 macOS、iOS、Android
- **多主题支持**：内置 Gruvbox、Nord、Sepia、Solarized、Catppuccin、Dracula 等 7 种精心调校的配色方案
- **响应式布局**：完美适配手机、平板、桌面端

### 📚 强大的阅读功能
- **多格式支持**：EPUB、PDF、TXT、MOBI、AZW3
- **智能排版**：自定义字体、字号、行高、字间距
- **双阅读模式**：滚动模式 / 翻页模式
- **双页布局**：桌面端支持左右双页显示（仿真纸质书）
- **全文搜索**：快速定位内容
- **书签与笔记**：随时标记重要内容

### 🤖 AI 增强
- **智能百科卡片**：选中文字即可查看 AI 生成的解释和维基百科摘要
- **多 AI 支持**：OpenAI GPT-4、Claude 3、Grok
- **翻译与解释**：一键翻译、深度解释复杂概念
- **TTS 朗读**：支持多语言文本转语音

### ☁️ 云同步
- **私有云支持**：自建服务器，数据完全掌控
- **分片上传**：大文件智能分片，断点续传
- **跨设备同步**：阅读进度、书签、笔记实时同步

### ⚡ 性能优化
- **Isolate 解析**：EPUB 解析在独立线程，不阻塞 UI
- **增量渲染**：大文件分块加载，流畅阅读
- **内存优化**：智能缓存策略，低内存占用

---

## 安装

### 预编译版本

从 [Releases](https://github.com/yourusername/hyesread/releases) 下载对应平台的安装包：

- **Windows**: `hyesread-windows-x64.zip`
- **macOS**: `hyesread-macos.dmg`
- **Linux**: `hyesread-linux-x64.tar.gz`
- **Android**: `hyesread-android.apk`
- **iOS**: 通过 TestFlight 或 App Store

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/yourusername/hyesread.git
cd hyesread

# 安装依赖
flutter pub get

# 生成 Isar 数据库代码
dart run build_runner build

# 运行应用
flutter run

# 构建发布版本
flutter build [platform] --release
# 例如: flutter build apk --release