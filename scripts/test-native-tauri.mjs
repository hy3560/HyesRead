import { chromium } from "@playwright/test";
import { spawn, spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, rm, unlink, writeFile } from "node:fs/promises";
import net from "node:net";
import { dirname, join, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

if (process.platform !== "win32") {
  throw new Error("The native Tauri acceptance check requires Windows and WebView2.");
}

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const executable = resolve(projectRoot, "src-tauri/target/release/hyes-read.exe");
const fixture = resolve(projectRoot, "tests/fixtures/hyesread-acceptance.epub");
const storageDirectory = join(process.env.APPDATA ?? "", "com.hyes.read");
const recoveryDirectory = await mkdtemp(join(tmpdir(), "hyesread-store-recovery-"));
const webviewDirectory = await mkdtemp(join(tmpdir(), "hyesread-webview2-"));
const managedStoreFiles = ["hyes_master.json", "hyes_stats.json"];
const originalStoreFiles = new Set();
let app;
let secondLaunch;
let browser;
let storeSnapshotTaken = false;

function log(stage) {
  console.log(`[native acceptance] ${stage}`);
}

function stopProcess(child) {
  if (!child?.pid) return;
  spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { stdio: "ignore" });
}

async function choosePort() {
  const server = net.createServer();
  await new Promise((resolvePromise, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolvePromise);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Could not reserve a WebView2 debug port.");
  await new Promise((resolvePromise, reject) => server.close(error => error ? reject(error) : resolvePromise()));
  return address.port;
}

async function waitForDebugEndpoint(port, child, timeoutMs = 60_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`HyesRead exited during startup (${child.exitCode}).`);
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (response.ok) return;
    } catch {}
    await delay(250);
  }
  throw new Error("HyesRead did not expose its local WebView2 acceptance endpoint.");
}

function createPdfFixture() {
  const content = "BT\n/F1 18 Tf\n72 720 Td\n(HyesRead native PDF acceptance) Tj\nET";
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`,
  ];
  const parts = [Buffer.from("%PDF-1.4\n", "ascii")];
  const offsets = [0];
  let length = parts[0].length;
  objects.forEach((object, index) => {
    offsets.push(length);
    const part = Buffer.from(`${index + 1} 0 obj\n${object}\nendobj\n`, "ascii");
    parts.push(part);
    length += part.length;
  });
  const xrefOffset = length;
  const xref = `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${offsets.slice(1).map(offset => `${String(offset).padStart(10, "0")} 00000 n \n`).join("")}trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
  parts.push(Buffer.from(xref, "ascii"));
  return Buffer.concat(parts);
}

async function restoreStore() {
  await mkdir(storageDirectory, { recursive: true });
  for (const name of managedStoreFiles) {
    const backup = join(recoveryDirectory, name);
    const destination = join(storageDirectory, name);
    if (originalStoreFiles.has(name)) await copyFile(backup, destination);
    else await unlink(destination).catch(error => { if (error.code !== "ENOENT") throw error; });
  }
}

try {
  log("checking app state");
  const running = spawnSync("tasklist", ["/FI", "IMAGENAME eq hyes-read.exe", "/FO", "CSV", "/NH"], { encoding: "utf8" });
  if (running.error) throw running.error;
  if (running.stdout.toLowerCase().includes('"hyes-read.exe"')) {
    throw new Error("Close the running HyesRead app before starting the isolated native acceptance check.");
  }

  for (const name of managedStoreFiles) {
    const path = join(storageDirectory, name);
    try {
      await copyFile(path, join(recoveryDirectory, name));
      originalStoreFiles.add(name);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  storeSnapshotTaken = true;

  const port = await choosePort();
  const pdfFixture = join(webviewDirectory, "hyesread-native-acceptance.pdf");
  await writeFile(pdfFixture, createPdfFixture());
  const appEnvironment = {
    ...process.env,
    WEBVIEW2_USER_DATA_FOLDER: webviewDirectory,
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port}`,
  };
  app = spawn(executable, [fixture], {
    cwd: projectRoot,
    stdio: "ignore",
    env: appEnvironment,
  });
  log("waiting for desktop WebView2");
  await waitForDebugEndpoint(port, app);
  browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);

  const deadline = Date.now() + 30_000;
  let page;
  while (Date.now() < deadline) {
    page = browser.contexts().flatMap(context => context.pages())
      .find(candidate => candidate.url().includes("/reader?path="));
    if (page) break;
    await delay(200);
  }
  if (!page) throw new Error("Opening the EPUB did not navigate the desktop app to its reader.");

  const failures = [];
  page.on("pageerror", error => failures.push(error.message));
  page.on("console", message => {
    if (message.type() === "error" && /Content Security Policy|ERR_BLOCKED_BY_CSP/i.test(message.text())) {
      failures.push(message.text());
    }
  });
  await page.reload({ waitUntil: "domcontentloaded" });

  let readerFrame;
  const readerDeadline = Date.now() + 30_000;
  while (Date.now() < readerDeadline) {
    readerFrame = page.frames().find(frame => frame.url().includes("/assets/web_reader/foliate-js/reader.html"));
    if (readerFrame) break;
    await delay(100);
  }
  if (!readerFrame) throw new Error("The bundled Foliate reader did not load in WebView2.");
  await readerFrame.locator("foliate-view").waitFor({ state: "visible", timeout: 30_000 });
  log("checking EPUB chapter rendering");

  let chapterText = "";
  let chapterFrame;
  const chapterDeadline = Date.now() + 30_000;
  while (Date.now() < chapterDeadline) {
    chapterFrame = page.frames().find(frame => frame.url().startsWith("blob:") || frame.url().startsWith("chrome-error://"));
    if (chapterFrame) {
      try { chapterText = await chapterFrame.locator("body").innerText({ timeout: 500 }); } catch {}
      if (chapterText.includes("这是用于检查离线 EPUB 阅读路径的测试内容。") || chapterText.includes("ERR_BLOCKED_BY_CSP")) break;
    }
    await delay(250);
  }

  if (!chapterText.includes("这是用于检查离线 EPUB 阅读路径的测试内容。")) {
    throw new Error(`WebView2 did not render the EPUB chapter. Frame: ${chapterFrame?.url() ?? "missing"}; content: ${chapterText.slice(0, 300)}`);
  }
  if (failures.length) throw new Error(`Native WebView2 runtime errors: ${failures.join("\n")}`);

  const progress = await readerFrame.locator("#progress-slider").getAttribute("title");
  if (!progress?.includes("Loc")) throw new Error("The EPUB location controls did not initialize in WebView2.");

  log("checking PDF and second-instance forwarding");
  secondLaunch = spawn(executable, [pdfFixture], { cwd: projectRoot, stdio: "ignore", env: appEnvironment });
  const secondExitCode = await Promise.race([
    new Promise(resolvePromise => secondLaunch.once("exit", resolvePromise)),
    delay(15_000).then(() => null),
  ]);
  if (secondExitCode === null) {
    stopProcess(secondLaunch);
    throw new Error("A second desktop launch did not hand its PDF to the running HyesRead instance.");
  }

  await page.waitForURL(url => url.href.includes("/reader?path=") && url.href.includes("acceptance.pdf"), { timeout: 30_000 });
  let pdfReaderFrame;
  const pdfReaderDeadline = Date.now() + 30_000;
  while (Date.now() < pdfReaderDeadline) {
    pdfReaderFrame = page.frames().find(frame => frame.url().includes("/assets/web_reader/foliate-js/reader.html"));
    if (pdfReaderFrame) break;
    await delay(100);
  }
  if (!pdfReaderFrame) throw new Error("The running desktop app did not load its PDF reader.");
  await pdfReaderFrame.locator("foliate-view").waitFor({ state: "visible", timeout: 30_000 });
  let pdfState = {};
  const pdfStateDeadline = Date.now() + 30_000;
  while (Date.now() < pdfStateDeadline) {
    pdfState = await pdfReaderFrame.locator("body").evaluate(() => {
      const host = window;
      const book = host.reader?.view?.book;
      return { layout: book?.rendition?.layout, pageCount: book?.sections?.length };
    });
    if (pdfState.layout === "pre-paginated" && pdfState.pageCount === 1) break;
    await delay(250);
  }
  if (pdfState.layout !== "pre-paginated" || pdfState.pageCount !== 1) {
    const details = await pdfReaderFrame.evaluate(() => ({ title: document.title, text: document.body.innerText.slice(0, 250) }));
    throw new Error(`WebView2 did not render the one-page PDF correctly: ${JSON.stringify({ pdfState, details, frameUrl: pdfReaderFrame.url(), failures })}`);
  }
  if (failures.length) throw new Error(`Native WebView2 runtime errors: ${failures.join("\n")}`);

  log(JSON.stringify({ result: "passed", desktop: "Windows WebView2", epubChapterRendered: true, pdfPageRendered: true, secondLaunchForwarded: true }));
} finally {
  if (browser) await browser.close().catch(() => undefined);
  for (const child of [secondLaunch, app]) {
    if (child?.exitCode === null) {
      stopProcess(child);
      await Promise.race([new Promise(resolvePromise => child.once("exit", resolvePromise)), delay(5_000)]);
    }
  }
  if (storeSnapshotTaken) await restoreStore();

  const tempRoot = resolve(tmpdir()) + sep;
  for (const directory of [webviewDirectory, recoveryDirectory]) {
    const target = resolve(directory);
    if (!target.startsWith(tempRoot)) throw new Error(`Refusing to remove a non-temporary path: ${target}`);
  }
  await rm(webviewDirectory, { recursive: true, force: true, maxRetries: 10, retryDelay: 500 });
  await rm(recoveryDirectory, { recursive: true, force: true, maxRetries: 10, retryDelay: 500 });
}
