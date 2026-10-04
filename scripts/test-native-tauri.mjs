import { chromium } from "@playwright/test";
import { createHash } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { access, copyFile, mkdir, mkdtemp, readFile, rm, unlink, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
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
const acceptanceIdentifier = "com.hyes.read.acceptance";
const storageDirectory = join(process.env.APPDATA ?? "", acceptanceIdentifier);
const recoveryDirectory = await mkdtemp(join(tmpdir(), "hyesread-store-recovery-"));
const webviewDirectory = await mkdtemp(join(tmpdir(), "hyesread-webview2-"));
const managedStoreFiles = ["hyes_master.json", "hyes_stats.json", "hyes_catalogs.json", "hyes_system.json"];
const originalStoreFiles = new Set();
let app;
let secondLaunch;
let browser;
let catalogServer;
let acceptanceCredentialUrl;
let storeSnapshotTaken = false;
let appOutput = "";

function captureAppOutput(stream, label) {
  stream?.on("data", chunk => {
    appOutput = `${appOutput}[${label}] ${chunk.toString()}`.slice(-16_000);
  });
}

function log(stage) {
  console.log(`[native acceptance] ${stage}`);
}

function stopProcess(child) {
  if (!child?.pid) return;
  spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { stdio: "ignore" });
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
  const diagnostics = spawnSync("powershell", [
    "-NoProfile", "-Command",
    "Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('hyes-read.exe','msedgewebview2.exe') } | Select-Object ProcessId,ParentProcessId,SessionId,Name,CommandLine | Format-List | Out-String -Width 300",
  ], { encoding: "utf8", timeout: 10_000 });
  throw new Error([
    `HyesRead did not expose its local WebView2 acceptance endpoint on port ${port}.`,
    `App process: ${JSON.stringify({ pid: child.pid, exitCode: child.exitCode })}`,
    `WebView2 processes:\n${diagnostics.stdout || diagnostics.stderr || "unavailable"}`,
    `App output:\n${appOutput || "none"}`,
  ].join("\n"));
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

function createAcceptanceConfig(port) {
  return JSON.stringify({
    identifier: acceptanceIdentifier,
    app: {
      windows: [{ label: "main", additionalBrowserArgs: `--remote-debugging-port=${port}` }],
    },
  });
}

function runBuildWithAcceptanceConfig(configPath) {
  const command = process.platform === "win32" ? "cmd.exe" : "pnpm";
  const args = process.platform === "win32"
    ? ["/d", "/s", "/c", `pnpm exec tauri build --bundles msi --config ${configPath}`]
    : ["tauri", "build", "--bundles", "msi", "--config", configPath];
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    encoding: "utf8",
    stdio: "inherit",
    timeout: 15 * 60_000,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`The native acceptance build failed (${result.status ?? result.signal}).`);
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
  const existingEndpoint = await fetch(`http://127.0.0.1:${port}/json/version`).catch(() => null);
  if (existingEndpoint?.ok) throw new Error(`WebView2 acceptance port ${port} is already in use.`);
  const acceptanceConfig = join(webviewDirectory, "tauri.acceptance.conf.json");
  await writeFile(acceptanceConfig, createAcceptanceConfig(port));
  log("building isolated acceptance binary");
  runBuildWithAcceptanceConfig(acceptanceConfig);
  const pdfFixture = join(webviewDirectory, "hyesread-native-acceptance.pdf");
  await writeFile(pdfFixture, createPdfFixture());
  const appEnvironment = {
    ...process.env,
    WEBVIEW2_USER_DATA_FOLDER: webviewDirectory,
  };
  app = spawn(executable, [fixture], {
    cwd: projectRoot,
    stdio: ["ignore", "pipe", "pipe"],
    env: appEnvironment,
  });
  captureAppOutput(app.stdout, "stdout");
  captureAppOutput(app.stderr, "stderr");
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
  log("checking incremental native scanning and cancellation");
  const scanFixture = join(webviewDirectory, "scan-books");
  await mkdir(scanFixture);
  const scanEpub = await readFile(fixture);
  for (let offset = 0; offset < 1_000; offset += 32) {
    await Promise.all(Array.from({ length: Math.min(32, 1_000 - offset) }, (_, index) =>
      (offset + index) % 4 === 0
        ? writeFile(join(scanFixture, `scan-${offset + index}.epub`), scanEpub)
        : writeFile(join(scanFixture, `scan-${offset + index}.txt`), "Native scan acceptance")));
  }
  const nativeScan = await page.evaluate(async root => {
    const internals = window.__TAURI_INTERNALS__;
    const invoke = (command, args) => internals.invoke(command, args);
    const normal = await invoke("scan_library_incremental", { folderPath: root, scanId: "acceptance-complete" });
    if (normal.books.length !== 1_000 || !normal.complete) throw new Error("Native scan did not return all books");
    let cancellation;
    const handler = internals.transformCallback(event => {
      if (event.payload.scanId === "acceptance-cancel") cancellation = invoke("cancel_library_scan", { scanId: "acceptance-cancel" });
    });
    const listener = await invoke("plugin:event|listen", { event: "hyesread:scan-progress", target: { kind: "Any" }, handler });
    try {
      const cancelled = await invoke("scan_library_incremental", { folderPath: root, scanId: "acceptance-cancel" });
      await cancellation;
      if (!cancelled.cancelled || cancelled.complete) throw new Error("Native scan was not cancelled");
      const resumed = await invoke("scan_library_incremental", { folderPath: root, scanId: "acceptance-resume" });
      if (!resumed.complete || resumed.books.length !== 1_000) throw new Error("Native scan registry did not recover after cancellation");
      return { books: normal.books.length, cancelledAt: cancelled.scanned, resumed: resumed.complete };
    } finally {
      window.__TAURI_EVENT_PLUGIN_INTERNALS__.unregisterListener("hyesread:scan-progress", listener);
      await invoke("plugin:event|unlisten", { event: "hyesread:scan-progress", eventId: listener });
      internals.unregisterCallback(handler);
    }
  }, scanFixture);
  log(JSON.stringify({ nativeScan }));

  if (failures.length) throw new Error(`Native WebView2 runtime errors: ${failures.join("\n")}`);

  const progress = await readerFrame.locator("#progress-slider").getAttribute("title");
  if (!progress?.includes("Loc")) throw new Error("The EPUB location controls did not initialize in WebView2.");

  log("checking EPUB search, settings, and bookmarks in WebView2");
  await page.getByRole("button", { name: "阅读设置" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("button", { name: "阅读设置" }).click();
  await readerFrame.locator("#reading-theme").selectOption("sepia");
  await readerFrame.locator("#reading-flow").selectOption("scrolled");
  await readerFrame.locator("#font-size").evaluate(element => {
    const input = element;
    input.value = "24";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const nativeSettings = await readerFrame.evaluate(() => ({
    settings: JSON.parse(localStorage.getItem("hyesread:reader-settings") || "{}"),
    flow: window.reader?.view?.renderer?.getAttribute("flow"),
  }));
  if (nativeSettings.settings?.style?.theme !== "sepia" || nativeSettings.settings?.style?.fontSize !== 24 || nativeSettings.flow !== "scrolled") {
    throw new Error(`WebView2 did not save and apply reader settings: ${JSON.stringify(nativeSettings)}`);
  }

  await page.getByRole("button", { name: "搜索正文" }).click();
  await readerFrame.locator("#search-query").fill("离线 EPUB 阅读路径");
  await readerFrame.getByRole("button", { name: "搜索", exact: true }).click();
  const searchDeadline = Date.now() + 10_000;
  while (Date.now() < searchDeadline && await readerFrame.locator("#search-status").innerText() !== "1 处") await delay(100);
  const searchResult = await readerFrame.locator(".search-result").first().innerText().catch(() => "");
  if (!searchResult.includes("离线 EPUB 阅读路径")) throw new Error(`WebView2 EPUB search did not find the passage: ${searchResult}`);

  const selectedPassage = await readerFrame.locator("foliate-view").evaluate(() => {
    const contents = window.reader?.view?.renderer?.getContents?.() ?? [];
    for (const { doc } of contents) {
      const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        const text = node.textContent || "";
        const start = text.indexOf("离线 EPUB 阅读路径");
        if (start < 0) continue;
        const range = doc.createRange();
        range.setStart(node, start);
        range.setEnd(node, start + "离线 EPUB 阅读路径".length);
        const selection = doc.getSelection();
        selection?.removeAllRanges();
        selection?.addRange(range);
        return true;
      }
    }
    return false;
  });
  if (!selectedPassage) throw new Error("WebView2 could not select the EPUB passage for highlighting.");
  await page.getByRole("button", { name: "高亮所选文字" }).click();
  let highlightState = { count: 0, rendered: 0 };
  const highlightDeadline = Date.now() + 10_000;
  while (Date.now() < highlightDeadline && (highlightState.count !== 1 || highlightState.rendered !== 1)) {
    highlightState = await page.evaluate(() => {
      const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-highlights:"));
      return {
        count: entry ? JSON.parse(entry[1]).length : 0,
        rendered: document.querySelector("#foliate-reader")?.contentWindow?.reader?.annotationsByValue?.size || 0,
      };
    });
    if (highlightState.count !== 1 || highlightState.rendered !== 1) await delay(100);
  }
  if (highlightState.count !== 1 || highlightState.rendered !== 1) {
    throw new Error(`WebView2 did not persist and render the EPUB highlight: ${JSON.stringify(highlightState)}`);
  }
  await page.getByRole("button", { name: "打开高亮列表" }).click();
  await page.getByRole("button", { name: /离线 EPUB 阅读路径/ }).click();

  await page.getByRole("button", { name: "添加或移除当前书签" }).click();
  const bookmarkCount = await page.evaluate(() => {
    const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-bookmarks:"));
    return entry ? JSON.parse(entry[1]).length : 0;
  });
  if (bookmarkCount !== 1) throw new Error(`WebView2 did not persist the EPUB bookmark: ${bookmarkCount}`);

  log("checking OPDS navigation and pagination");
  await page.getByRole("button", { name: "← 返回书库" }).click();
  await page.getByRole("button", { name: "在线目录" }).click();
  const epubBytes = await readFile(fixture);
  catalogServer = createServer((request, response) => {
    if (request.url.startsWith("/private")) {
      if (request.headers.authorization !== `Basic ${Buffer.from("reader:secret").toString("base64")}`) {
        response.writeHead(401, { "www-authenticate": 'Basic realm="HyesRead acceptance"' });
        response.end();
        return;
      }
      response.writeHead(200, { "content-type": "application/atom+xml; charset=utf-8" });
      if (request.url === "/private/category") response.end(`<feed xmlns="http://www.w3.org/2005/Atom"><title>登录分类</title></feed>`);
      else if (request.url === "/private?page=2") response.end(`<feed xmlns="http://www.w3.org/2005/Atom"><title>已验证目录</title><entry><id>private-page-two</id><title>登录目录第二页</title></entry></feed>`);
      else response.end(`<feed xmlns="http://www.w3.org/2005/Atom"><title>已验证目录</title><link rel="next" href="/private?page=2"/><entry><id>private-book</id><title>登录目录中的书籍</title><link rel="subsection" href="/private/category" title="登录分类"/></entry></feed>`);
      return;
    }
    if (request.url === "/opds") {
      response.writeHead(200, { "content-type": "application/atom+xml; charset=utf-8" });
      response.end(`<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>本机 OPDS 验收</title><link rel="next" href="/opds?page=2" type="application/atom+xml;profile=opds-catalog"/><entry><id>acceptance-series</id><title>测试分类</title><link rel="subsection" href="/category.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/></entry><entry><id>acceptance-book</id><title>在线验收电子书</title><author><name>HyesRead</name></author><summary>由本地 OPDS 服务提供。</summary><link rel="http://opds-spec.org/acquisition" href="/books/acceptance.epub" type="application/epub+zip" title="EPUB"/></entry></feed>`);
      return;
    }
    if (request.url === "/opds?page=2") {
      response.writeHead(200, { "content-type": "application/atom+xml; charset=utf-8" });
      response.end(`<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>本机 OPDS 验收</title><entry><id>second-page-book</id><title>第二页书籍</title></entry></feed>`);
      return;
    }
    if (request.url === "/category.xml") {
      response.writeHead(200, { "content-type": "application/atom+xml; charset=utf-8" });
      response.end(`<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>测试分类</title><entry><id>nested-book</id><title>分类内书籍</title></entry></feed>`);
      return;
    }
    if (request.url === "/books/acceptance.epub") {
      response.writeHead(200, { "content-type": "application/epub+zip", "content-length": epubBytes.length });
      response.end(epubBytes);
      return;
    }
    response.writeHead(404);
    response.end();
  });
  await new Promise((resolvePromise, reject) => {
    catalogServer.once("error", reject);
    catalogServer.listen(0, "127.0.0.1", resolvePromise);
  });
  const catalogAddress = catalogServer.address();
  if (!catalogAddress || typeof catalogAddress === "string") throw new Error("Could not start the local OPDS test server.");
  const catalogUrl = `http://127.0.0.1:${catalogAddress.port}/opds`;
  await page.getByRole("textbox", { name: "OPDS 地址" }).fill(catalogUrl);
  await page.getByRole("button", { name: "添加目录" }).click();
  await page.getByRole("heading", { name: "本机 OPDS 验收" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("button", { name: "打开 测试分类" }).click();
  await page.getByRole("heading", { name: "测试分类" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("button", { name: "返回上级目录" }).click();
  await page.getByRole("heading", { name: "本机 OPDS 验收" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("heading", { name: "在线验收电子书" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("button", { name: "下一页" }).click();
  await page.getByRole("heading", { name: "第二页书籍" }).waitFor({ state: "visible", timeout: 10_000 });
  log("checking authenticated OPDS access in the Windows app");
  acceptanceCredentialUrl = `http://127.0.0.1:${catalogAddress.port}/private`;
  await page.getByRole("textbox", { name: "OPDS 地址" }).fill(acceptanceCredentialUrl);
  await page.getByRole("textbox", { name: "目录账号" }).fill("reader");
  await page.getByLabel("目录密码").fill("secret");
  await page.getByRole("button", { name: "添加目录" }).click();
  await page.getByRole("heading", { name: "已验证目录" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("button", { name: "打开 登录分类" }).click();
  await page.getByRole("heading", { name: "登录分类" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("button", { name: "返回上级目录" }).click();
  await page.getByRole("button", { name: "下一页" }).click();
  await page.getByRole("heading", { name: "登录目录第二页" }).waitFor({ state: "visible", timeout: 10_000 });
  const catalogJson = await readFile(join(storageDirectory, "hyes_catalogs.json"), "utf8");
  if (catalogJson.includes("secret") || catalogJson.includes("reader:")) throw new Error("OPDS credentials were saved to the ordinary JSON store");
  await page.getByRole("button", { name: "移除目录 本机 OPDS 验收" }).click();

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
  log("checking PDF text search in WebView2");
  await page.getByRole("button", { name: "搜索正文" }).waitFor({ state: "visible", timeout: 10_000 });
  await page.getByRole("button", { name: "搜索正文" }).click();
  await pdfReaderFrame.locator("#search-query").fill("HyesRead");
  await pdfReaderFrame.getByRole("button", { name: "搜索", exact: true }).click();
  const pdfSearchDeadline = Date.now() + 10_000;
  while (Date.now() < pdfSearchDeadline && await pdfReaderFrame.locator("#search-status").innerText() !== "1 处") await delay(100);
  const pdfSearchResult = await pdfReaderFrame.locator(".search-result").first().innerText().catch(() => "");
  if (!pdfSearchResult.includes("HyesRead")) throw new Error(`WebView2 PDF search did not find the passage: ${pdfSearchResult}`);
  await pdfReaderFrame.locator(".search-result").first().click();
  const selectedPdfPassage = await pdfReaderFrame.locator("foliate-view").evaluate(async () => {
    for (const { doc } of window.reader?.view?.renderer?.getContents?.() ?? []) {
      const walker = doc.createTreeWalker(doc.querySelector(".textLayer") || doc.body, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        const text = node.textContent || "";
        const start = text.indexOf("HyesRead native PDF acceptance");
        if (start < 0) continue;
        const range = doc.createRange();
        range.setStart(node, start);
        range.setEnd(node, start + "HyesRead native PDF acceptance".length);
        doc.getSelection()?.removeAllRanges();
        doc.getSelection()?.addRange(range);
        doc.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
        doc.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true }));
        return true;
      }
    }
    return false;
  });
  if (!selectedPdfPassage) throw new Error("WebView2 could not select the PDF text layer passage.");
  const nativePageState = await page.evaluate(() => ({
    href: location.href,
    path: new URL(location.href).searchParams.get("path"),
    title: document.querySelector("#foliate-reader")?.getAttribute("title"),
    highlightButtonDisabled: Array.from(document.querySelectorAll("button")).find(button => button.getAttribute("aria-label") === "高亮所选文字")?.disabled,
    selected: document.querySelector("#foliate-reader")?.contentWindow?.reader?.view?.renderer?.getContents?.().map(item => item.doc?.getSelection()?.toString()),
    localStorageAvailable: (() => { try { localStorage.setItem("hyesread:test", "1"); const v = localStorage.getItem("hyesread:test"); localStorage.removeItem("hyesread:test"); return v === "1"; } catch { return false; } })(),
  }));
  const highlightButton = page.getByRole("button", { name: "高亮所选文字" });
  await highlightButton.waitFor({ state: "visible", timeout: 10_000 });
  const selectionDeadline = Date.now() + 5_000;
  while (Date.now() < selectionDeadline && await highlightButton.isDisabled()) await delay(50);
  if (await highlightButton.isDisabled()) throw new Error(`WebView2 did not expose the selected PDF text to the app: ${JSON.stringify(nativePageState)}`);
  await highlightButton.click();
  await delay(100);
  let pdfHighlightState = { count: 0, rendered: 0 };
  const pdfHighlightDeadline = Date.now() + 10_000;
  while (Date.now() < pdfHighlightDeadline && (pdfHighlightState.count !== 1 || pdfHighlightState.rendered !== 1)) {
    pdfHighlightState = await page.evaluate(() => {
      const activePath = decodeURIComponent(new URL(location.href).searchParams.get("path") || "");
      const saved = JSON.parse(localStorage.getItem(`hyes-highlights:${activePath}`) || "[]");
      const frame = document.querySelector("#foliate-reader");
      const view = frame?.contentWindow?.reader?.view;
      const pdfPage = view?.renderer?.getContents?.().find(item => item.index === 0);
      return { count: saved.length, rendered: pdfPage?.overlayer?.element.childElementCount || 0 };
    });
    if (pdfHighlightState.count !== 1 || pdfHighlightState.rendered !== 1) await delay(100);
  }
  if (pdfHighlightState.count !== 1 || pdfHighlightState.rendered !== 1) {
    const pageErrors = await page.evaluate(() => ({ url: location.href, errors: Array.from(document.querySelectorAll("main > div, [role=alert]")).map(element => element.textContent).filter(Boolean), buttons: Array.from(document.querySelectorAll("button")).map(button => ({ label: button.getAttribute("aria-label"), text: button.textContent, disabled: button.disabled })) }));
    throw new Error(`WebView2 did not persist and render the PDF highlight: ${JSON.stringify({ pdfHighlightState, failures, nativePageState, pageErrors })}`);
  }
  log("checking shelf removal persistence without deleting the source file");
  await page.getByRole("button", { name: "← 返回书库" }).click();
  const cardDeadline = Date.now() + 10_000;
  let bookLabel = "";
  while (Date.now() < cardDeadline) {
    const labels = await page.locator("button[aria-label^='打开《']").evaluateAll(elements => elements.map(element => element.getAttribute("aria-label") || ""));
    bookLabel = labels.find(label => label.toLocaleLowerCase().includes("native-acceptance")) || "";
    if (bookLabel) break;
    await delay(100);
  }
  if (!bookLabel) {
    const labels = await page.locator("button[aria-label]").evaluateAll(elements => elements.map(element => element.getAttribute("aria-label")));
    throw new Error(`The externally opened PDF did not appear on the shelf. URL: ${page.url()}; buttons: ${JSON.stringify(labels)}`);
  }
  const nativeBook = page.locator(`button[aria-label=${JSON.stringify(bookLabel)}]`);
  await nativeBook.waitFor({ state: "visible", timeout: 10_000 });
  const title = bookLabel.slice("打开《".length, -1);
  await page.getByRole("button", { name: `从书架移除《${title}》` }).click();
  await nativeBook.waitFor({ state: "detached", timeout: 10_000 });
  if (failures.length) throw new Error(`Native WebView2 runtime errors: ${failures.join("\n")}`);
  const beforeRestartStorage = await page.evaluate(path => ({
    path,
    saved: JSON.parse(localStorage.getItem(`hyes-highlights:${path}`) || "[]"),
  }), pdfFixture);
  if (beforeRestartStorage.saved.length !== 1 || beforeRestartStorage.saved[0]?.value !== "hyespdf:0:0:30") {
    throw new Error("The PDF highlight was not saved under the book path before app exit.");
  }
  const appExit = new Promise(resolvePromise => app.once("exit", resolvePromise));
  await page.close().catch(() => undefined);
  await Promise.race([appExit, delay(15_000)]);
  if (app.exitCode === null) stopProcess(app);
  await Promise.race([appExit, delay(5_000)]);
  await browser.close();
  browser = undefined;
  if (app.exitCode === null) throw new Error("The desktop app did not exit before the restart check.");
  app = spawn(executable, [], { cwd: projectRoot, stdio: ["ignore", "pipe", "pipe"], env: appEnvironment });
  captureAppOutput(app.stdout, "stdout");
  captureAppOutput(app.stderr, "stderr");
  await waitForDebugEndpoint(port, app);
  browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
  let shelfPage;
  const shelfDeadline = Date.now() + 30_000;
  while (Date.now() < shelfDeadline) {
    shelfPage = browser.contexts().flatMap(context => context.pages()).find(candidate => new URL(candidate.url()).pathname === "/");
    if (shelfPage) break;
    await delay(200);
  }
  if (!shelfPage) throw new Error("The restarted desktop app did not open its shelf.");
  await shelfPage.getByRole("button", { name: "添加文件" }).waitFor({ state: "visible", timeout: 10_000 });
  try {
    await shelfPage.locator("button[aria-label^='打开《']").first().waitFor({ state: "visible", timeout: 10_000 });
  } catch (error) {
    const state = await shelfPage.evaluate(async () => {
      const invoke = (command, args) => window.__TAURI_INTERNALS__.invoke(command, args);
      const rid = await invoke("plugin:store|load", { path: "hyes_master.json" });
      const entries = await invoke("plugin:store|entries", { rid });
      return { entries, body: document.body.innerText, url: location.href };
    });
    throw new Error(`Shelf restart failed: ${JSON.stringify(state)}; ${error}`);
  }
  if (await shelfPage.locator("button[aria-label^='打开《']").evaluateAll(elements => elements.some(element => (element.getAttribute("aria-label") || "").toLocaleLowerCase().includes("native-acceptance")))) {
    throw new Error("The removed PDF returned to the shelf after restarting the desktop app.");
  }
  await access(pdfFixture);
  log("checking OPDS credentials survive process restart and migrate legacy URLs");
  await shelfPage.getByRole("button", { name: "在线目录" }).click();
  await shelfPage.getByRole("button", { name: "已验证目录", exact: true }).click();
  await shelfPage.getByRole("heading", { name: "已验证目录" }).waitFor({ state: "visible", timeout: 10_000 });
  await shelfPage.getByRole("button", { name: "移除目录 已验证目录" }).click();
  const anonymousError = await shelfPage.evaluate(async url => {
    try { await window.__TAURI_INTERNALS__.invoke("fetch_opds_feed", { url }); return ""; } catch (error) { return String(error); }
  }, acceptanceCredentialUrl);
  if (!anonymousError.includes("401")) throw new Error(`The removed catalog should reject anonymous requests with HTTP 401: ${anonymousError}`);
  await shelfPage.evaluate(async url => {
    const invoke = (command, args) => window.__TAURI_INTERNALS__.invoke(command, args);
    const rid = await invoke("plugin:store|load", { path: "hyes_catalogs.json" });
    const legacy = new URL(url); legacy.username = "reader"; legacy.password = "secret";
    await invoke("plugin:store|set", { rid, key: "sources", value: [{ url: legacy.href, title: "旧版登录目录" }] });
    await invoke("plugin:store|save", { rid });
  }, acceptanceCredentialUrl);
  await shelfPage.reload();
  await shelfPage.getByRole("button", { name: "在线目录" }).click();
  await shelfPage.getByRole("button", { name: "旧版登录目录", exact: true }).click();
  await shelfPage.getByRole("heading", { name: "已验证目录" }).waitFor({ state: "visible", timeout: 10_000 });
  const migratedCatalogJson = await readFile(join(storageDirectory, "hyes_catalogs.json"), "utf8");
  if (migratedCatalogJson.includes("secret") || migratedCatalogJson.includes("reader:")) throw new Error("Legacy OPDS credential migration left plaintext passwords in JSON");
  await shelfPage.getByRole("button", { name: "移除目录 旧版登录目录" }).click();
  acceptanceCredentialUrl = undefined;
  await new Promise(resolvePromise => catalogServer.close(resolvePromise));
  catalogServer = undefined;
  await shelfPage.getByRole("button", { name: "书架", exact: true }).click();
  secondLaunch = spawn(executable, [pdfFixture], { cwd: projectRoot, stdio: "ignore", env: appEnvironment });
  const reopenExitCode = await Promise.race([
    new Promise(resolvePromise => secondLaunch.once("exit", resolvePromise)),
    delay(15_000).then(() => null),
  ]);
  if (reopenExitCode === null) {
    stopProcess(secondLaunch);
    throw new Error("Opening the removed PDF again did not return control to the running desktop app.");
  }
  await shelfPage.waitForURL(url => url.href.includes("/reader?path=") && url.href.includes("acceptance.pdf"), { timeout: 30_000 });
  let restoredPdfFrame;
  const restoredPdfDeadline = Date.now() + 30_000;
  while (Date.now() < restoredPdfDeadline) {
    restoredPdfFrame = browser.contexts().flatMap(context => context.pages()).flatMap(candidate => candidate.frames())
      .find(frame => frame.url().includes("/assets/web_reader/foliate-js/reader.html") && frame.url().includes("url="));
    if (restoredPdfFrame) break;
    await delay(100);
  }
  if (!restoredPdfFrame) throw new Error("The reopened PDF did not load its bundled reader.");
  await restoredPdfFrame.locator("foliate-view").waitFor({ state: "visible", timeout: 30_000 });
  const restoredPdfHighlightDeadline = Date.now() + 10_000;
  let restoredPdfHighlight = { annotations: 0, stored: 0, rendered: 0 };
  while (Date.now() < restoredPdfHighlightDeadline && (restoredPdfHighlight.annotations !== 1 || restoredPdfHighlight.rendered !== 1)) {
    restoredPdfHighlight = await shelfPage.evaluate(() => {
      const readerFrame = document.querySelector("#foliate-reader");
      const readerWindow = readerFrame?.contentWindow;
      const activePath = decodeURIComponent(new URL(location.href).searchParams.get("path") || "");
      const stored = JSON.parse(localStorage.getItem(`hyes-highlights:${activePath}`) || "[]");
      const pdfPage = readerWindow?.reader?.view?.renderer?.getContents?.().find(item => item.index === 0);
      return {
        annotations: readerWindow?.reader?.annotationsByValue?.size || 0,
        stored: stored.length,
        rendered: pdfPage?.overlayer?.element.childElementCount || 0,
      };
    });
    if (restoredPdfHighlight.annotations !== 1 || restoredPdfHighlight.rendered !== 1) await delay(100);
  }
  if (restoredPdfHighlight.annotations !== 1 || restoredPdfHighlight.stored !== 1 || restoredPdfHighlight.rendered !== 1) {
    throw new Error(`WebView2 did not restore the PDF highlight after reopening: ${JSON.stringify(restoredPdfHighlight)}`);
  }
  await shelfPage.getByRole("button", { name: "← 返回书库" }).click();
  await shelfPage.getByRole("button", { name: "打开《hyesread-native-acceptance》" }).waitFor({ state: "visible", timeout: 10_000 });

  log("checking browser-book backup restore and reading in the desktop app");
  const portableEpubPath = "browser-book:native-portable-epub";
  const portableTextPath = "browser-book:native-portable-text";
  const textBytes = Buffer.from("桌面端恢复的浏览器书籍可以继续阅读。", "utf8");
  const portableBackup = {
    format: "hyesread-backup",
    version: 1,
    exportedAt: new Date().toISOString(),
    master: { libraryPath: "", discreteFiles: [portableEpubPath, portableTextPath], excludedFiles: [], lastOpenedBook: "", bookAddedAt: {} },
    sessions: [],
    catalogs: [],
    readerData: {},
    browserBooks: [
      { id: portableEpubPath, name: "native-portable-epub.epub", type: "application/epub+zip", data: epubBytes.toString("base64"), sha256: createHash("sha256").update(epubBytes).digest("hex") },
      { id: portableTextPath, name: "native-portable-text.txt", type: "text/plain", data: textBytes.toString("base64"), sha256: createHash("sha256").update(textBytes).digest("hex") },
    ],
  };
  await shelfPage.getByRole("button", { name: "设置" }).click();
  const backupChooserPromise = shelfPage.waitForEvent("filechooser");
  await shelfPage.getByRole("button", { name: "导入并合并" }).click();
  const backupChooser = await backupChooserPromise;
  const backupFileInput = shelfPage.locator('input[aria-label="选择 HyesRead 备份文件"]');
  await backupFileInput.evaluate(input => {
    input.dataset.nativeAcceptanceChangeSeen = "false";
    input.addEventListener("change", () => { input.dataset.nativeAcceptanceChangeSeen = "true"; }, { once: true });
  });
  await backupChooser.setFiles({
    name: "hyesread-native-portable-backup.json",
    mimeType: "application/json",
    buffer: Buffer.from(JSON.stringify(portableBackup)),
  });
  let backupInputState = await backupFileInput.evaluate(input => ({
    files: Array.from(input.files || [], file => ({ name: file.name, size: file.size })),
    changeSeen: input.dataset.nativeAcceptanceChangeSeen === "true",
  }));
  if (backupInputState.files.length !== 1) {
    throw new Error(`WebView2 did not accept the browser-book backup file: ${JSON.stringify(backupInputState)}`);
  }
  if (!backupInputState.changeSeen) {
    log("dispatching the file input change event in WebView2");
    await backupFileInput.dispatchEvent("change");
    backupInputState = { ...backupInputState, changeSeen: true };
  }
  log("waiting for the browser-book backup import to finish");
  const restoreSuccess = shelfPage.getByRole("status").filter({ hasText: "恢复 2 本浏览器书籍" });
  const restoreDeadline = Date.now() + 90_000;
  let restoreError = "";
  while (Date.now() < restoreDeadline) {
    if (await restoreSuccess.isVisible().catch(() => false)) break;
    restoreError = await shelfPage.getByRole("alert").innerText().catch(() => "");
    if (restoreError) break;
    await delay(250);
  }
  if (!(await restoreSuccess.isVisible().catch(() => false))) {
    const restoreDiagnostics = await shelfPage.evaluate(() => ({
      url: location.href,
      status: Array.from(document.querySelectorAll('[role="status"]'), element => element.textContent?.trim()).filter(Boolean),
      alerts: Array.from(document.querySelectorAll('[role="alert"]'), element => element.textContent?.trim()).filter(Boolean),
      bodyText: document.body.innerText.slice(-1200),
    }));
    throw new Error(`Desktop browser-book backup import did not finish successfully. ${JSON.stringify({ backupInputState, restoreError, restoreDiagnostics, runtimeErrors: failures })}`);
  }
  log("confirming both restored books appear on the shelf");
  await shelfPage.getByRole("button", { name: "书架" }).click();
  await shelfPage.getByRole("button", { name: "打开《native-portable-epub》" }).waitFor({ state: "visible", timeout: 30_000 });
  await shelfPage.getByRole("button", { name: "打开《native-portable-epub》" }).click();
  await shelfPage.waitForURL(url => url.href.includes(encodeURIComponent(portableEpubPath)), { timeout: 30_000 });
  log("waiting for the restored EPUB reader to initialize");
  const portableReader = shelfPage.frameLocator("#foliate-reader");
  await portableReader.locator("foliate-view").waitFor({ state: "visible", timeout: 30_000 });
  let portableChapterText = "";
  const portableChapterDeadline = Date.now() + 30_000;
  while (Date.now() < portableChapterDeadline && !portableChapterText.includes("离线 EPUB 阅读路径")) {
    const chapterFrame = shelfPage.frames().find(frame => frame.url().startsWith("blob:"));
    if (chapterFrame) portableChapterText = await chapterFrame.locator("body").innerText().catch(() => "");
    if (!portableChapterText.includes("离线 EPUB 阅读路径")) await delay(100);
  }
  if (!portableChapterText.includes("离线 EPUB 阅读路径")) {
    throw new Error(`The restored browser EPUB did not render in the Windows desktop reader: ${JSON.stringify({ text: portableChapterText, frames: shelfPage.frames().map(frame => frame.url()), errors: await shelfPage.locator('[role="alert"].mb-5').allTextContents() })}`);
  }
  log("confirming the restored EPUB chapter and opening the restored TXT book");
  await shelfPage.getByRole("button", { name: "← 返回书库" }).click();
  await shelfPage.getByRole("button", { name: "打开《native-portable-text》" }).waitFor({ state: "visible", timeout: 30_000 });
  await shelfPage.getByRole("button", { name: "打开《native-portable-text》" }).click();
  await shelfPage.waitForURL(url => url.href.includes(encodeURIComponent(portableTextPath)), { timeout: 30_000 });
  await shelfPage.frameLocator("#foliate-reader").locator("article").getByText("桌面端恢复的浏览器书籍可以继续阅读。", { exact: true }).waitFor({ state: "visible", timeout: 30_000 });
  await shelfPage.getByRole("button", { name: "← 返回书库" }).click();
  await shelfPage.getByRole("button", { name: "打开《native-portable-epub》" }).waitFor({ state: "visible", timeout: 10_000 });

  log("checking the scan cancellation control preserves the current shelf");
  const beforeScanUi = await shelfPage.evaluate(async root => {
    const invoke = (command, args) => window.__TAURI_INTERNALS__.invoke(command, args);
    const rid = await invoke("plugin:store|load", { path: "hyes_master.json" });
    const [libraryPath] = await invoke("plugin:store|get", { rid, key: "library_path" });
    const [addedAt] = await invoke("plugin:store|get", { rid, key: "book_added_at" });
    const [discrete] = await invoke("plugin:store|get", { rid, key: "discrete_files" });
    await invoke("plugin:store|set", { rid, key: "library_path", value: root });
    await invoke("plugin:store|save", { rid });
    return { rid, libraryPath: libraryPath || "", addedAt: JSON.stringify(addedAt), discrete: JSON.stringify(discrete) };
  }, scanFixture);
  try {
    await shelfPage.reload();
    const cancelButton = shelfPage.getByRole("button", { name: "取消扫描" });
    await cancelButton.waitFor({ state: "visible", timeout: 10_000 });
    await cancelButton.click();
    await cancelButton.waitFor({ state: "hidden", timeout: 10_000 });
    await shelfPage.getByRole("button", { name: "打开《native-portable-epub》" }).waitFor({ state: "visible", timeout: 10_000 });
    const afterScanUi = await shelfPage.evaluate(async () => {
      const invoke = (command, args) => window.__TAURI_INTERNALS__.invoke(command, args);
      const rid = await invoke("plugin:store|load", { path: "hyes_master.json" });
      const [addedAt] = await invoke("plugin:store|get", { rid, key: "book_added_at" });
      const [discrete] = await invoke("plugin:store|get", { rid, key: "discrete_files" });
      return { addedAt: JSON.stringify(addedAt), discrete: JSON.stringify(discrete) };
    });
    if (beforeScanUi.addedAt !== afterScanUi.addedAt || beforeScanUi.discrete !== afterScanUi.discrete) {
      throw new Error("Cancelling the scan changed existing library metadata");
    }
  } finally {
    await shelfPage.evaluate(async original => {
      const invoke = (command, args) => window.__TAURI_INTERNALS__.invoke(command, args);
      const rid = await invoke("plugin:store|load", { path: "hyes_master.json" });
      await invoke("plugin:store|set", { rid, key: "library_path", value: original.libraryPath });
      await invoke("plugin:store|save", { rid });
    }, beforeScanUi);
  }

  if (failures.length) throw new Error(`Native WebView2 runtime errors: ${failures.join("\n")}`);

  log(JSON.stringify({ result: "passed", desktop: "Windows WebView2", epubChapterRendered: true, epubSearch: true, epubHighlight: true, readerSettings: true, bookmarks: true, opdsNavigation: true, opdsPagination: true, opdsBasicAuthentication: true, pdfPageRendered: true, pdfSearch: true, pdfHighlight: true, pdfHighlightRestore: true, portableEpubRestore: true, portableTextRestore: true, shelfRemovalPersists: true, sourceFilePreserved: true, secondLaunchForwarded: true }));
} finally {
  if (browser && acceptanceCredentialUrl) {
    const cleanupPage = browser.contexts().flatMap(context => context.pages()).find(candidate => candidate.url().startsWith("http://tauri.localhost"));
    if (cleanupPage) await cleanupPage.evaluate(url => window.__TAURI_INTERNALS__.invoke("delete_opds_credentials", { url }), acceptanceCredentialUrl).catch(error => console.warn("Acceptance credential cleanup failed:", error.message));
  }
  if (catalogServer) await new Promise(resolvePromise => catalogServer.close(resolvePromise));
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
