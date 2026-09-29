# HyesRead

HyesRead is a local e-book reader that keeps your library, reading position, and reading history on your device.

## Features

- Read EPUB, PDF, MOBI, AZW3/KF8, FB2/FBZ, CBZ, TXT, and Markdown files.
- Scan local folders in the desktop app, or add books directly in a browser.
- Search and sort your library by title or author.
- Save your reading position and view reading time and activity.
- No account required. Library data and reading history stay on your device.

## Windows installer

Download the Windows x64 installer from [GitHub Releases](https://github.com/hy3560/HyesRead/releases/latest). You can also run or build the desktop app from source below.

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

GitHub Actions builds the Windows installer for every main-branch update and pull request.
