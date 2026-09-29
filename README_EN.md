# HyesRead

HyesRead is a local e-book reader that keeps your library, reading position, and reading history on your device.

## Features

- Read EPUB, PDF, MOBI, AZW3/KF8, FB2, CBZ, TXT, and Markdown files.
- Scan local folders in the desktop app, or add books directly in a browser.
- Search and sort your library by title or author.
- Save your reading position and view reading time and activity.
- No account required. Library data and reading history stay on your device.

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

There are no prebuilt installers published yet. You can run the source or build an installer locally.
