# Hyes Read

<div align="center">
  <img src="assets/icon/icon.png" alt="HyesRead Logo" width="128" height="128">
  
  <h3>A cross-platform local e-book reading and management tool</h3>
  
  <p>
    <a href="#features">Features</a> •
    <a href="#status">Status</a> •
    <a href="#installation">Installation</a> •
    <a href="#build-from-source">Build</a>
  </p>
  
  <p>
    <img src="https://img.shields.io/badge/Tauri-2.0-FFC131?logo=tauri&logoColor=white" alt="Tauri 2.0">
    <img src="https://img.shields.io/badge/Rust-2021-000000?logo=rust&logoColor=white" alt="Rust">
    <img src="https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black" alt="React">
    <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
  </p>
</div>

---

## 💡 Status

**Current Version: Alpha (Under Active Development)**

> **Note**: In earlier versions, due to frontend Webview sandbox limitations, there were occasional issues with launching system applications or deleting files. In the latest architecture, we have completely handed over these operations to the underlying Rust modules (`opener` and `fs`). It can now stably launch the system's default applications to open e-books and manage files securely without restriction.

## ✨ Features

- 🚀 **Local Library Scanning**: Utilizes Rust's `walkdir` and `rayon` for multi-threaded file scanning, enabling fast reading of local directories.
- 📚 **Multi-Format Support**: Supports extracting metadata and covers from various common e-book formats including `EPUB`, `MOBI`, `AZW3`, `PDF`, and `CBZ`.
- 🛡️ **Native File Operations**: Launches files using the system's default associated software and supports secure, native file deletion.
- 📊 **Reading Statistics**: Visual reading time tracking and activity charts powered by Recharts.
- 🧠 **AI & TTS Ready**: Features a built-in custom API configuration interface for Large Language Models and Text-to-Speech (TTS), paving the way for future AI-assisted features.
- 🎨 **Modern UI**: A dark-mode interactive interface built with TailwindCSS and Framer Motion.

## 📦 Installation

### Pre-compiled Releases

Download the installation package for your corresponding platform from the [Releases](https://github.com/hy3560/HyesRead/releases) page:

- **Windows**: `HyesRead_x64-setup.exe` / `HyesRead_x64.msi`
- **macOS**: `HyesRead_aarch64.dmg` (Apple Silicon) / `HyesRead_x64.dmg` (Intel)
- **Linux**: `hyesread_amd64.AppImage` / `hyesread_amd64.deb`

## 🛠️ Build from Source

This project is built with Tauri V2 + Rust + React. Before you begin, please ensure that you have [Node.js](https://nodejs.org/) and the [Rust toolchain](https://rustup.rs/) installed on your system.
```bash
# Clone the repository
git clone [https://github.com/hy3560/HyesRead.git](https://github.com/hy3560/HyesRead.git)
cd HyesRead

# Install frontend dependencies
npm install

# Run the development environment
npm run tauri dev

# Build for production
npm run tauri build
