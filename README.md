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
现在还是半成品,在打开文件的时候和删除的时候会出现not found

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
