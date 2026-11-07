# HyesRead

HyesRead is a local e-book reader that keeps your library, reading position, and reading history on your device.

## Flutter for Windows and Android (2026-11-07)

[Download the Windows portable ZIP and Android APK](https://github.com/hy3560/HyesRead/releases/tag/flutter-20261107). This is the current Windows and Android edition, installed and stored separately from the Tauri and web editions below. Libraries and reading positions are not migrated automatically, and feature sets differ. Flutter source is in [flutter-ui](flutter-ui/).

- **Windows x64:** Download `HyesRead-Windows-x64-clean-bilingual-20261107.zip`, extract the entire archive, and run `HyesRead.exe`. Keep the DLL files and `data` folder together. This package is unsigned and has no installer or automatic updates; the Visual C++ 2015–2022 x64 runtime may be required.
- **Android:** Download and install `app-release.apk`. Its package ID is `com.hyes.hyesread_flutter`, separate from the older app. It is signed with a debug key, not a production store key. Android may ask you to allow installation from the download source.
- Import and manage local TXT, Markdown, EPUB and PDF books, resume reading, and use bookmarks and saved positions. TXT / Markdown support text search, EPUB has a table of contents, and PDF supports page navigation. Reading appearance is adjustable; Simplified Chinese and English are available. Book content is not translated, and some third-party or system messages may remain untranslated.
- TXT / Markdown must be UTF-8 and are limited to 20 MiB per book; EPUB is limited to 50 MiB. Full-text search is not yet available for EPUB or PDF. Complex EPUB layouts and behavior across devices still need further testing. The Flutter edition does not yet have all older-edition formats, OPDS, annotations, or data migration.
- Check downloads against `SHA256SUMS.txt` in the release and retain backups of your original books.

The features and build instructions below describe the existing Tauri / web editions unless stated otherwise.

## Features

- Read EPUB, PDF, MOBI, AZW3/KF8, FB2/FBZ, CBZ, TXT, and Markdown files.
- Scan local folders in the desktop app, or add books directly in a browser.
- Install the Android APK on a phone, or use the web app in a mobile browser.
- Browse OPDS/Calibre catalogs, open categories, paginate, and download books in the Windows desktop app. Enter usernames and passwords separately; credentials are stored in Windows Credential Manager. Authenticated remote catalogs require HTTPS; HTTP is permitted for loopback addresses. See the [credential notes](docs/opds-credentials.md).
- Search and sort your library by title or author.
- Search text and the table of contents in reflowable formats, highlight passages, choose paginated or scrolled layout, and adjust font size, line spacing, and theme. Text-based PDFs also support text search, jumping to matching pages, and persistent passage highlights. TXT and Markdown support scrolling and the same display settings.
- Add bookmarks and restore reading positions in supported formats. Your library, positions, highlights, bookmarks, and reading history stay on your device.
- Export and restore your library index, positions, bookmarks, highlights, statistics, and catalog sources from Settings. Exported catalog URLs omit usernames and passwords; enter credentials again on another device. Book files are not included. Select the library folder to restore reading data for books with a unique matching relative path; ambiguous matches are left untouched.
- No account required. Library data and reading history stay on your device.
- Online catalogs are not available in the browser app.

## Windows installer

Download the older Windows x64 Tauri installer from [v0.1.29](https://github.com/hy3560/HyesRead/releases/tag/v0.1.29). You can also run or build it from source below.

## Android app

Download the older Android ARM64 APK from [v0.1.29](https://github.com/hy3560/HyesRead/releases/tag/v0.1.29). Android may ask you to allow app installs from the browser for the first install.

## Run in a browser

Open the [HyesRead mobile web app](https://hy3560.github.io/HyesRead/) in a phone browser. Bookshelves and reading data stay in that browser. Use **Add files** to choose books; browser security does not allow scanning phone folders. OPDS catalogs are not available in the web app.

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
