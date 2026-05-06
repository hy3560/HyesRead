# Hyes Read

<div align="center">
  <img src="assets/icon/icon.png" alt="HyesRead Logo" width="128" height="128">
  
  <h3>一款跨平台的本地电子书阅读与管理工具</h3>
  
  <p>
    <a href="#特性">特性</a> •
    <a href="#状态">状态</a> •
    <a href="#安装">安装</a> •
    <a href="#构建">构建</a>
  </p>
  
  <p>
    <img src="https://img.shields.io/badge/Tauri-2.0-FFC131?logo=tauri&logoColor=white" alt="Tauri 2.0">
    <img src="https://img.shields.io/badge/Rust-2021-000000?logo=rust&logoColor=white" alt="Rust">
    <img src="https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black" alt="React">
    <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
  </p>
</div>

---

## 💡 开发状态 (Status)

**当前版本：Alpha（持续开发中）**

> **注**：在早期版本中，受限于前端 Webview 权限，曾出现过调用系统应用失败或文件删除报错的问题。在最新的架构中，我们已将相关操作交由 Rust 底层模块（`opener` 与 `fs`）接管。现在可以稳定地调用系统默认应用打开电子书，并正常进行文件管理。

## ✨ 核心特性

- 🚀 **本地书库扫描**：使用 Rust 的 `walkdir` 与 `rayon` 实现多线程文件扫描，快速读取本地目录。
- 📚 **多格式支持**：支持提取 `EPUB`, `MOBI`, `AZW3`, `PDF`, `CBZ` 等多种常见电子书格式的元数据与封面。
- 🛡️ **原生文件调用**：调用系统默认关联软件打开阅读文件，并支持安全的文件删除操作。
- 📊 **阅读统计**：基于 Recharts 提供的阅读时长追踪与活跃度图表。
- 🧠 **AI & TTS 预留**：内置了大语言模型与文字转语音（TTS）的自定义 API 配置界面，方便后续接入 AI 辅助功能。
- 🎨 **现代化 UI**：基于 TailwindCSS + Framer Motion 构建的深色模式交互界面。

## 📦 安装

### 预编译版本

从 [Releases](https://github.com/hy3560/HyesRead/releases) 下载对应平台的安装包：

- **Windows**: `HyesRead_x64-setup.exe` / `HyesRead_x64.msi`
- **macOS**: `HyesRead_aarch64.dmg` (Apple Silicon) / `HyesRead_x64.dmg` (Intel)
- **Linux**: `hyesread_amd64.AppImage` / `hyesread_amd64.deb`

## 🛠️ 从源码构建

本项目基于 Tauri V2 + Rust + React 构建。在开始之前，请确保你的操作系统已安装 [Node.js](https://nodejs.org/) 以及 [Rust 工具链](https://rustup.rs/)。
```bash
# 克隆仓库
git clone [https://github.com/hy3560/HyesRead.git](https://github.com/hy3560/HyesRead.git)
cd HyesRead

# 安装前端依赖
npm install

# 运行开发环境
npm run tauri dev

# 打包正式版本
npm run tauri build
