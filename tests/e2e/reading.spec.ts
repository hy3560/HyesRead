import { expect, test } from "@playwright/test";
import { resolve } from "node:path";

function createPdfFixture() {
  const content = "BT\n/F1 18 Tf\n72 720 Td\n(HyesRead PDF acceptance) Tj\nET";
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

test("keeps the empty shelf free of instructional copy", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("button", { name: "添加文件" })).toBeVisible();
  await expect(page.getByText("书架是空的，添加几本书开始阅读。", { exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "首页" }).click();
  await expect(page.getByText("书库还是空的，请先导入书籍", { exact: true })).toHaveCount(0);
});

test("opens an uploaded PDF in the bundled reader", async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on("pageerror", error => runtimeErrors.push(error.message));
  page.on("console", message => { if (message.type() === "error") runtimeErrors.push(message.text()); });

  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({
    name: "hyesread-acceptance.pdf",
    mimeType: "application/pdf",
    buffer: createPdfFixture(),
  });

  const openBook = page.getByRole("button", { name: "打开《hyesread-acceptance》" });
  await expect(openBook).toBeVisible();
  await openBook.click();
  await expect(page).toHaveURL(/\/reader\?path=/);

  const reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  await expect.poll(() => reader.locator("#progress-slider").getAttribute("title")).toContain("Loc");
  const pdfState = await reader.locator("body").evaluate(() => {
    const host = window as unknown as {
      reader?: { view?: { book?: { rendition?: { layout?: string }; sections?: unknown[] } } };
    };
    const book = host.reader?.view?.book;
    return { layout: book?.rendition?.layout, pageCount: book?.sections?.length };
  });
  expect(pdfState).toEqual({ layout: "pre-paginated", pageCount: 1 });
  expect(runtimeErrors).toEqual([]);
});

test("adds, opens, and restores a local EPUB", async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on("pageerror", error => runtimeErrors.push(error.message));
  page.on("console", message => { if (message.type() === "error") runtimeErrors.push(message.text()); });
  page.on("dialog", dialog => {
    runtimeErrors.push(`Unexpected dialog: ${dialog.message}`);
    void dialog.dismiss();
  });

  await page.goto("/");
  await expect(page).toHaveTitle("HyesRead");
  await expect(page.getByRole("heading", { name: "Hyes Read" })).toBeVisible();

  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles(resolve("tests/fixtures/hyesread-acceptance.epub"));

  const openBook = page.getByRole("button", { name: "打开《hyesread-acceptance》" });
  await expect(openBook).toBeVisible();
  await openBook.click();
  if (runtimeErrors.length) throw new Error(runtimeErrors.join("\n"));
  await expect(page).toHaveURL(/\/reader\?path=/);

  const reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  await expect.poll(() => reader.locator("#progress-slider").getAttribute("title")).toContain("Loc");
  await expect.poll(async () => {
    const chapter = page.frames().find(frame => frame.url().startsWith("blob:"));
    if (!chapter) return "";
    try { return await chapter.locator("body").innerText(); } catch { return ""; }
  }).toContain("这是用于检查离线 EPUB 阅读路径的测试内容。");
  await expect(page.getByText("hyesread-acceptance.epub", { exact: true })).toBeVisible();
  expect(runtimeErrors).toEqual([]);
});

test("saves EPUB reading layout and appearance settings", async ({ page }) => {
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles(resolve("tests/fixtures/hyesread-acceptance.epub"));
  await page.getByRole("button", { name: "打开《hyesread-acceptance》" }).click();

  const reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  await page.getByRole("button", { name: "阅读设置" }).click();
  await expect(reader.getByRole("region", { name: "阅读设置" })).toBeVisible();
  await reader.locator("#reading-theme").selectOption("sepia");
  await reader.locator("#reading-flow").selectOption("scrolled");
  await reader.locator("#font-size").evaluate(element => {
    const input = element as HTMLInputElement;
    input.value = "24";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });

  const saved = await reader.locator("body").evaluate(() => {
    const frame = Array.from(document.querySelectorAll("iframe")).find(item => item.contentDocument?.body);
    const settings = JSON.parse(localStorage.getItem("hyesread:reader-settings") || "{}");
    return {
      theme: settings.style?.theme,
      fontSize: settings.style?.fontSize,
      chapterColor: frame?.contentDocument?.body ? getComputedStyle(frame.contentDocument.body).color : "",
    };
  });
  expect(saved).toMatchObject({ theme: "sepia", fontSize: 24 });
  await expect.poll(() => reader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { renderer?: Element } } };
    return host.reader?.view?.renderer?.getAttribute("flow");
  })).toBe("scrolled");
  await expect.poll(() => reader.locator("body").evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(244, 236, 216)");
  await page.reload();
  const restoredReader = page.frameLocator("#foliate-reader");
  await expect(restoredReader.locator("foliate-view")).toBeVisible();
  await expect(restoredReader.locator("#font-size")).toHaveValue("24");
  await expect(restoredReader.locator("#reading-theme")).toHaveValue("sepia");
  await expect.poll(() => restoredReader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { renderer?: Element } } };
    return host.reader?.view?.renderer?.getAttribute("flow");
  })).toBe("scrolled");
});

test("searches EPUB body text and opens a matching passage", async ({ page }) => {
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles(resolve("tests/fixtures/hyesread-acceptance.epub"));
  await page.getByRole("button", { name: "打开《hyesread-acceptance》" }).click();

  const reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  await page.getByRole("button", { name: "搜索正文" }).click();
  await reader.getByRole("searchbox", { name: "搜索正文" }).fill("离线 EPUB 阅读路径");
  await reader.getByRole("button", { name: "搜索", exact: true }).click();
  await expect(reader.locator("#search-status")).toHaveText("1 处", { timeout: 10_000 });
  await expect(reader.locator(".search-result")).toContainText("离线 EPUB 阅读路径");
  await reader.locator(".search-result").click();
  await expect.poll(() => reader.locator("#progress-slider").getAttribute("title")).toContain("Loc");
});

test("saves, restores, and removes EPUB bookmarks", async ({ page }) => {
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles(resolve("tests/fixtures/hyesread-acceptance.epub"));
  await page.getByRole("button", { name: "打开《hyesread-acceptance》" }).click();

  const reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  const addBookmark = page.getByRole("button", { name: "添加或移除当前书签" });
  await expect(addBookmark).toBeEnabled();
  await addBookmark.click();
  await expect(addBookmark).toHaveText("已标记");
  const bookmarkData = await page.evaluate(() => {
    const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-bookmarks:"));
    return entry ? JSON.parse(entry[1]) as { id: string }[] : [];
  });
  expect(bookmarkData).toHaveLength(1);

  await page.reload();
  const restoredReader = page.frameLocator("#foliate-reader");
  await expect(restoredReader.locator("foliate-view")).toBeVisible();
  await expect(page.getByRole("button", { name: "添加或移除当前书签" })).toHaveText("已标记");
  await page.getByRole("button", { name: "打开书签列表" }).click();
  await expect(page.getByRole("region", { name: "书签列表" })).toContainText("%");
  await page.getByRole("button", { name: /删除书签/ }).click();
  await expect(page.getByRole("button", { name: "打开书签列表" })).toHaveText("0");
  await expect(addBookmark).not.toHaveText("已标记");
});

test("keeps uploaded text on the shelf after reload and reads Chinese text", async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on("pageerror", error => runtimeErrors.push(error.message));
  page.on("console", message => { if (message.type() === "error") runtimeErrors.push(message.text()); });

  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({
    name: "中文阅读验收.txt",
    mimeType: "text/plain",
    buffer: Buffer.from("第一段：本机阅读与进度恢复。\n第二段：中文内容能够正确显示。", "utf8"),
  });

  const openBook = page.getByRole("button", { name: "打开《中文阅读验收》" });
  await expect(openBook).toBeVisible();
  await page.reload();
  await expect(openBook).toBeVisible();
  await openBook.click();

  const textFrame = page.frameLocator("#foliate-reader");
  await expect(textFrame.locator("article")).toContainText("中文内容能够正确显示。");
  await expect(textFrame.locator("article")).toContainText("本机阅读与进度恢复。");
  expect(runtimeErrors).toEqual([]);
});

test("removes a browser book only after its shelf entry is saved", async ({ page }) => {
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({
    name: "待移除书籍.txt",
    mimeType: "text/plain",
    buffer: Buffer.from("移除后不再出现在书架。", "utf8"),
  });

  const book = page.getByRole("button", { name: "打开《待移除书籍》" });
  await expect(book).toBeVisible();
  await page.getByRole("button", { name: "从书架移除《待移除书籍》" }).click();
  await expect(book).toHaveCount(0);
  await page.reload();
  await expect(page.getByRole("button", { name: "打开《待移除书籍》" })).toHaveCount(0);
});

test("shows a storage error instead of claiming a book was added", async ({ page }) => {
  await page.addInitScript(() => {
    const setItem = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) {
      if (key === "hyes:hyes_master.json") throw new DOMException("Storage is full", "QuotaExceededError");
      return setItem.call(this, key, value);
    };
  });

  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({
    name: "无法保存.txt",
    mimeType: "text/plain",
    buffer: Buffer.from("storage failure", "utf8"),
  });

  await expect(page.locator('div[role="alert"]').filter({ hasText: "文件添加失败" })).toBeVisible();
  await expect(page.getByRole("button", { name: "打开《无法保存》" })).toHaveCount(0);
});

test("reports an unreadable book in the app instead of hiding the reader error", async ({ page }) => {
  const diagnostics: string[] = [];
  page.on("console", message => diagnostics.push(`console:${message.type()}:${message.text()}`));
  page.on("pageerror", error => diagnostics.push(`pageerror:${error.message}`));
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({
    name: "损坏的书籍.epub",
    mimeType: "application/epub+zip",
    buffer: Buffer.from("not an epub archive", "utf8"),
  });

  await page.getByRole("button", { name: "打开《损坏的书籍》" }).click();
  await expect(page.locator('span[role="alert"]')).toContainText("无法打开这本书", { timeout: 10_000 }).catch(async error => {
    const frames = await Promise.all(page.frames().map(async frame => ({ url: frame.url(), text: (await frame.locator("body").innerText().catch(() => "")).slice(0, 300) })));
    throw new Error(`${error.message}\nDiagnostics: ${diagnostics.join("\n")}\nFrames: ${JSON.stringify(frames)}`);
  });
});
