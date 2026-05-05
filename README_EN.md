# HyesRead

<div align="center">
  <img src="assets/icon/icon.png" alt="HyesRead Logo" width="128" height="128">
  
  <h3>Elegant Cross-Platform eBook Reader</h3>
  
  <p>
    <a href="#features">Features</a> •
    <a href="#installation">Installation</a> •
    <a href="#usage">Usage</a> •
    <a href="#development">Development</a> •
    <a href="#contributing">Contributing</a>
  </p>
  
  <p>
    <img src="https://img.shields.io/badge/Flutter-3.24.0-blue?logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
    <img src="https://img.shields.io/github/v/release/yourusername/hyesread" alt="Release">
  </p>
</div>

---

## Features

### 🎨 Elegant Design
- **Glassmorphic UI**: Modern visual experience with backdrop blur support
- **Multiple Themes**: 7 carefully crafted color schemes including Gruvbox, Nord, Sepia, Solarized, Catppuccin, and Dracula
- **Responsive Layout**: Perfect adaptation for mobile, tablet, and desktop

### 📚 Powerful Reading
- **Multi-Format Support**: EPUB, PDF, TXT, MOBI, AZW3
- **Smart Typography**: Customizable font, size, line height, letter spacing
- **Dual Reading Modes**: Scroll mode / Page-flip mode
- **Double-Page Layout**: Desktop support for side-by-side pages (mimics physical books)
- **Full-Text Search**: Quickly locate content
- **Bookmarks & Notes**: Mark important content anytime

### 🤖 AI Enhancement
- **Smart Wiki Cards**: Select text to see AI-generated explanations and Wikipedia summaries
- **Multi-AI Support**: OpenAI GPT-4, Claude 3, Grok
- **Translation & Explanation**: One-click translation and in-depth concept explanation
- **TTS Reading**: Multi-language text-to-speech support

### ☁️ Cloud Sync
- **Private Cloud Support**: Self-hosted server, full data control
- **Chunked Upload**: Smart chunking for large files with resume capability
- **Cross-Device Sync**: Real-time sync of reading progress, bookmarks, and notes

### ⚡ Performance Optimization
- **Isolate Parsing**: EPUB parsing in separate thread, non-blocking UI
- **Incremental Rendering**: Large files loaded in chunks for smooth reading
- **Memory Optimization**: Smart caching strategy, low memory footprint

---

## Installation

### Pre-built Binaries

Download from [Releases](https://github.com/yourusername/hyesread/releases):

- **Windows**: `hyesread-windows-x64.zip`
- **macOS**: `hyesread-macos.dmg`
- **Linux**: `hyesread-linux-x64.tar.gz`
- **Android**: `hyesread-android.apk`
- **iOS**: Via TestFlight or App Store

### Build from Source

```bash
# Clone repository
git clone https://github.com/yourusername/hyesread.git
cd hyesread

# Install dependencies
flutter pub get

# Generate Isar database code
dart run build_runner build

# Run app
flutter run

# Build release
flutter build [platform] --release
# Example: flutter build apk --release