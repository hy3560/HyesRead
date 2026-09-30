# HyesRead

HyesRead is a local e-book reader that keeps your library, reading position, and reading history on your device.

## Features

- Read EPUB, PDF, MOBI, AZW3/KF8, FB2/FBZ, CBZ, TXT, and Markdown files.
- Scan local folders in the desktop app, or add books directly in a browser.
- Install the Android APK on a phone, or use the web app in a mobile browser.
- Browse OPDS/Calibre catalogs, open categories, paginate, and download books in the Windows desktop app. HTTP Basic authentication is supported with `https://username:password@host`; saved catalog URLs stay on this device, so use HTTPS to protect credentials.
- Search and sort your library by title or author.
- Search text and the table of contents in reflowable formats, highlight passages, choose paginated or scrolled layout, and adjust font size, line spacing, and theme. Text-based PDFs also support text search, jumping to matching pages, and persistent passage highlights. TXT and Markdown support scrolling and the same display settings.
- Add bookmarks and restore reading positions in supported formats. Your library, positions, highlights, bookmarks, and reading history stay on your device.
- Export and restore your library index, positions, bookmarks, highlights, statistics, and catalog sources from Settings. Exported catalog URLs omit usernames and passwords; enter credentials again on another device. Book files are not included. Select the library folder to restore reading data for books with a unique matching relative path; ambiguous matches are left untouched.
- No account required. Library data and reading history stay on your device.
- Online catalogs are not available in the browser app.

## Windows installer

Download the Windows x64 installer from [GitHub Releases](https://github.com/hy3560/HyesRead/releases/latest). You can also run or build the desktop app from source below.

## Android app

Download the Android ARM64 APK from [GitHub Releases](https://github.com/hy3560/HyesRead/releases/latest) and install it. Most recent Android phones use ARM64; Android may ask you to allow app installs from the browser for the first install.

## Run in a browser

Install Node.js and pnpm, then run:

```bash
pnpm install --frozen-lockfile
pnpm dev
```

Open the local address shown in the terminal and choose **Add files**. For static hosting, run `pnpm build` and publish the generated `out` directory. Browser security rules do not allow a website to scan local folders.

## Run the desktop app

Install Node.js, pnpm, the Rust toolchain, and the system dependencies required by Tauri on your platform.

```bash
pnpm install --frozen-lockfile
pnpm tauri dev
```

Build a desktop installer with:

```bash
pnpm tauri build
```

## Verification

Run type checking, the dependency security audit, and reader smoke tests at desktop and mobile sizes:

```bash
pnpm lint
pnpm audit --prod --registry=https://registry.npmjs.org
pnpm exec playwright install chromium
pnpm test:e2e
```

On Windows, also build the desktop app and verify that WebView2 renders an EPUB chapter:

```powershell
pnpm tauri build --bundles msi
pnpm test:native
```

GitHub Actions builds the Windows installer for every main-branch update and pull request.
