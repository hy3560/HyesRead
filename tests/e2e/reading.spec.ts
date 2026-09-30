import { expect, test } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { mapBookPaths } from "../../src/lib/bookPaths";
import { remapBackupPaths } from "../../src/lib/backupPaths";

function createPdfFixture(pageCount = 1) {
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    `<< /Type /Pages /Kids [${Array.from({ length: pageCount }, (_, index) => `${3 + index * 2} 0 R`).join(" ")}] /Count ${pageCount} >>`,
    ...Array.from({ length: pageCount }, (_, index) => {
      const pageId = 3 + index * 2;
      const contentId = pageId + 1;
      const content = `BT\n/F1 18 Tf\n72 720 Td\n(HyesRead PDF acceptance page ${index + 1}) Tj\nET`;
      return [
        `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 ${3 + pageCount * 2} 0 R >> >> /Contents ${contentId} 0 R >>`,
        `<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`,
      ];
    }).flat(),
    `<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>`,
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

function createZipFixture(files: { name: string; data: Buffer }[]) {
  const crc32 = (data: Buffer) => {
    let crc = 0xffffffff;
    for (const byte of data) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
    return (crc ^ 0xffffffff) >>> 0;
  };
  const local: Buffer[] = [];
  const central: Buffer[] = [];
  let offset = 0;
  for (const file of files) {
    const name = Buffer.from(file.name, "utf8");
    const checksum = crc32(file.data);
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt32LE(checksum, 14);
    header.writeUInt32LE(file.data.length, 18);
    header.writeUInt32LE(file.data.length, 22);
    header.writeUInt16LE(name.length, 26);
    local.push(header, name, file.data);
    const record = Buffer.alloc(46);
    record.writeUInt32LE(0x02014b50, 0);
    record.writeUInt16LE(20, 4);
    record.writeUInt16LE(20, 6);
    record.writeUInt32LE(checksum, 16);
    record.writeUInt32LE(file.data.length, 20);
    record.writeUInt32LE(file.data.length, 24);
    record.writeUInt16LE(name.length, 28);
    record.writeUInt32LE(offset, 42);
    central.push(record, name);
    offset += header.length + name.length + file.data.length;
  }
  const centralSize = central.reduce((size, part) => size + part.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, ...central, end]);
}

test("maps restored library books by relative path and leaves ambiguous matches unmapped", async () => {
  const mappings = mapBookPaths(
    "C:\\OldLibrary",
    "D:\\Books",
    ["C:\\OldLibrary\\Novel.epub", "C:\\OldLibrary\\Series\\One.epub", "C:\\OldLibrary\\Same.epub"],
    ["D:\\Books\\novel.EPUB", "D:\\Books\\Series\\One.epub", "D:\\Books\\A\\Same.epub", "D:\\Books\\B\\Same.epub"],
  );
  expect(mappings).toEqual([
    ["C:\\OldLibrary\\Novel.epub", "D:\\Books\\novel.EPUB"],
    ["C:\\OldLibrary\\Series\\One.epub", "D:\\Books\\Series\\One.epub"],
  ]);
});

test("remaps every per-book backup record when a library moves", async () => {
  const source = "C:\\OldLibrary\\Novel.epub";
  const target = "D:\\Books\\Novel.epub";
  const moved = remapBackupPaths({
    master: { discreteFiles: [source], excludedFiles: [], lastOpenedBook: source, bookAddedAt: { [source]: 123 } },
    sessions: [{ date: "2026-09-30", duration: 25, bookPath: source }],
    readerData: {
      [`hyes-reader-location:${source}`]: JSON.stringify({ fraction: 0.6 }),
      [`hyes-bookmarks:${source}`]: JSON.stringify([{ id: "mark-1", location: { fraction: 0.6 } }]),
      [`hyes-highlights:${source}`]: JSON.stringify([{ id: "highlight-1", value: "passage" }]),
      "hyesread:reader-settings": JSON.stringify({ fontSize: 20 }),
    },
  }, [[source, target]]);
  expect(moved.master).toEqual({ discreteFiles: [target], excludedFiles: [], lastOpenedBook: target, bookAddedAt: { [target]: 123 } });
  expect(moved.sessions[0].bookPath).toBe(target);
  expect(JSON.parse(moved.readerData[`hyes-reader-location:${target}`])).toEqual({ fraction: 0.6 });
  expect(JSON.parse(moved.readerData[`hyes-bookmarks:${target}`])[0].id).toBe("mark-1");
  expect(JSON.parse(moved.readerData[`hyes-highlights:${target}`])[0].id).toBe("highlight-1");
  expect(moved.readerData["hyesread:reader-settings"]).toBe(JSON.stringify({ fontSize: 20 }));
});

test("keeps the empty shelf free of instructional copy", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("button", { name: "添加文件" })).toBeVisible();
  await expect(page.getByText("书架是空的，添加几本书开始阅读。", { exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "首页" }).click();
  await expect(page.getByText("书库还是空的，请先导入书籍", { exact: true })).toHaveCount(0);
});

test("exports a backup and merges imported reading data without replacing current progress", async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem("hyes:hyes_master.json", JSON.stringify({ discrete_files: ["browser-book:existing"] }));
    localStorage.setItem("hyes:hyes_stats.json", JSON.stringify({ sessions: [{ date: "2026-09-30", duration: 20, bookPath: "book.epub" }] }));
    localStorage.setItem("hyes-bookmarks:book.epub", JSON.stringify([{ id: "existing-bookmark", label: "现有书签", location: { fraction: 0.2 }, createdAt: 1 }]));
    localStorage.setItem("hyes-reader-location:book.epub", JSON.stringify({ fraction: 0.25 }));
  });
  await page.goto("/");
  await page.getByRole("button", { name: "设置" }).click();
  const exportButton = page.getByRole("button", { name: "导出备份" });
  await expect(exportButton).toBeVisible();
  const downloadPromise = page.waitForEvent("download");
  await exportButton.click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toMatch(/^hyesread-backup-\d{4}-\d{2}-\d{2}\.json$/);
  const downloadPath = await download.path();
  expect(downloadPath).not.toBeNull();
  const exported = JSON.parse(await readFile(downloadPath!, "utf8"));
  expect(exported.format).toBe("hyesread-backup");
  expect(exported.master.discreteFiles).toEqual(["browser-book:existing"]);
  expect(exported.readerData["hyes-reader-location:book.epub"]).toBe(JSON.stringify({ fraction: 0.25 }));

  const importedBackup = {
    format: "hyesread-backup",
    version: 1,
    exportedAt: "2026-09-29T00:00:00.000Z",
    master: { libraryPath: "", discreteFiles: ["browser-book:imported"], excludedFiles: [], lastOpenedBook: "" },
    sessions: [
      { date: "2026-09-30", duration: 30, bookPath: "book.epub" },
      { date: "2026-09-29", duration: 10, bookPath: "book.epub" },
    ],
    catalogs: [],
    readerData: {
      "hyes-bookmarks:book.epub": JSON.stringify([{ id: "imported-bookmark", label: "导入书签", location: { fraction: 0.8 }, createdAt: 2 }]),
      "hyes-reader-location:book.epub": JSON.stringify({ fraction: 0.8 }),
    },
  };
  await page.getByRole("button", { name: "导入并合并" }).click();
  await page.locator('input[aria-label="选择 HyesRead 备份文件"]').setInputFiles({
    name: "hyesread-backup.json",
    mimeType: "application/json",
    buffer: Buffer.from(JSON.stringify(importedBackup)),
  });
  await expect(page.getByRole("status")).toContainText("备份已恢复");
  const result = await page.evaluate(() => ({
    discrete: JSON.parse(localStorage.getItem("hyes:hyes_master.json") || "{}").discrete_files,
    sessions: JSON.parse(localStorage.getItem("hyes:hyes_stats.json") || "{}").sessions,
    bookmarks: JSON.parse(localStorage.getItem("hyes-bookmarks:book.epub") || "[]"),
    location: JSON.parse(localStorage.getItem("hyes-reader-location:book.epub") || "null"),
  }));
  expect(result.discrete).toEqual(["browser-book:existing", "browser-book:imported"]);
  expect(result.sessions).toHaveLength(2);
  expect(result.sessions.find((session: { date: string }) => session.date === "2026-09-30").duration).toBe(30);
  expect(result.bookmarks.map((bookmark: { id: string }) => bookmark.id)).toEqual(["existing-bookmark", "imported-bookmark"]);
  expect(result.location.fraction).toBe(0.25);
});

test("sorts browser imports by added time and keeps the order after reload", async ({ page }) => {
  await page.goto("/");
  for (const name of ["recent-order-older", "recent-order-newer"]) {
    const chooserPromise = page.waitForEvent("filechooser");
    await page.getByRole("button", { name: "添加文件" }).click();
    const chooser = await chooserPromise;
    await chooser.setFiles({ name: `${name}.txt`, mimeType: "text/plain", buffer: Buffer.from(`${name} content`) });
    await expect(page.getByRole("button", { name: `打开《${name}》` })).toBeVisible();
  }
  const shelfOrder = async () => page.getByRole("button", { name: /^打开《recent-order-/ }).evaluateAll(buttons => buttons.map(button => button.getAttribute("aria-label") || button.textContent));
  await expect.poll(shelfOrder).toEqual(["打开《recent-order-newer》", "打开《recent-order-older》"]);
  await page.reload();
  await expect.poll(shelfOrder).toEqual(["打开《recent-order-newer》", "打开《recent-order-older》"]);
  const storedOrder = await page.evaluate(() => {
    const master = JSON.parse(localStorage.getItem("hyes:hyes_master.json") || "{}");
    return master.discrete_files.map((path: string) => master.book_added_at[path]);
  });
  expect(storedOrder).toHaveLength(2);
  expect(storedOrder[0]).toBeLessThan(storedOrder[1]);
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
  await expect(page.getByRole("button", { name: "搜索正文" })).toBeVisible();
  await page.getByRole("button", { name: "搜索正文" }).click();
  await reader.locator("#search-query").fill("acceptance page 1");
  await reader.getByRole("button", { name: "搜索", exact: true }).click();
  await expect(reader.locator("#search-status")).toHaveText("1 处");
  await expect(reader.locator(".search-result").first()).toContainText("第 1 页");
  await reader.locator(".search-result").first().click();
  await expect.poll(() => reader.locator("#progress-slider").getAttribute("title")).toContain("Loc");
  const selectedPdfPassage = await reader.locator("foliate-view").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { renderer?: { getContents?: () => { doc: Document }[] } } } };
    for (const { doc } of host.reader?.view?.renderer?.getContents?.() ?? []) {
      const walker = doc.createTreeWalker(doc.querySelector(".textLayer") || doc.body, NodeFilter.SHOW_TEXT);
      let node: Node | null;
      while ((node = walker.nextNode())) {
        const start = node.textContent?.indexOf("acceptance page 1") ?? -1;
        if (start < 0) continue;
        const range = doc.createRange();
        range.setStart(node, start);
        range.setEnd(node, start + "acceptance page 1".length);
        doc.getSelection()?.removeAllRanges();
        doc.getSelection()?.addRange(range);
        return true;
      }
    }
    return false;
  });
  expect(selectedPdfPassage).toBe(true);
  const pdfHighlightButton = page.getByRole("button", { name: "高亮所选文字" });
  await expect(pdfHighlightButton).toBeEnabled();
  await pdfHighlightButton.click();
  await expect.poll(() => reader.locator("foliate-view").evaluate(() => {
    const host = window as unknown as { reader?: { annotationsByValue?: Map<string, unknown>; view?: { renderer?: { getContents?: () => { doc: Document; index: number; overlayer?: { element: SVGSVGElement } }[] } } } };
    const pdfPage = host.reader?.view?.renderer?.getContents?.().find(item => item.index === 0);
    return {
      annotations: host.reader?.annotationsByValue?.size ?? 0,
      pdfPage: pdfPage ? { index: pdfPage.index, hasOverlay: Boolean(pdfPage.overlayer), connected: pdfPage.overlayer?.element.isConnected, childCount: pdfPage.overlayer?.element.childElementCount } : null,
    };
  })).toEqual({ annotations: 1, pdfPage: { index: 0, hasOverlay: true, connected: true, childCount: 1 } });
  const savedHighlight = await page.evaluate(() => {
    const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-highlights:"));
    return entry ? JSON.parse(entry[1])[0] as { text?: string; value?: string } : null;
  });
  expect(savedHighlight?.text).toBe("acceptance page 1");
  const highlightErrors: string[] = [];
  page.on("pageerror", error => highlightErrors.push(error.message));
  expect(highlightErrors).toEqual([]);
  await page.getByRole("button", { name: "← 返回书库" }).click();
  await page.getByRole("button", { name: "打开《hyesread-acceptance》" }).click();
  await expect.poll(() => page.frameLocator("#foliate-reader").locator("foliate-view").evaluate(() => {
    const host = window as unknown as { reader?: { annotationsByValue?: Map<string, unknown> } };
    return host.reader?.annotationsByValue?.size ?? 0;
  })).toBe(1);
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
  await expect(page.getByRole("button", { name: "搜索正文" })).toBeVisible();
  await page.getByRole("button", { name: "搜索正文" }).click();
  await reader.getByRole("searchbox", { name: "搜索正文" }).fill("离线 EPUB 阅读路径");
  await reader.getByRole("button", { name: "搜索", exact: true }).click();
  await expect(reader.locator("#search-status")).toHaveText("1 处", { timeout: 10_000 });
  await expect(reader.locator(".search-result")).toContainText("离线 EPUB 阅读路径");
  await reader.locator(".search-result").click();
  await expect.poll(() => reader.locator("#progress-slider").getAttribute("title")).toContain("Loc");
});

test("saves and restores EPUB text highlights without modal prompts", async ({ page }) => {
  let modalDialogs = 0;
  page.on("dialog", async dialog => { modalDialogs++; await dialog.dismiss(); });
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles(resolve("tests/fixtures/hyesread-acceptance.epub"));
  await page.getByRole("button", { name: "打开《hyesread-acceptance》" }).click();

  let reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  await expect.poll(() => reader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { renderer?: { getContents?: () => { doc: Document }[] } } } };
    return host.reader?.view?.renderer?.getContents?.().some(({ doc }) => doc.body.textContent?.includes("离线 EPUB 阅读路径")) || false;
  })).toBe(true);
  const selected = await reader.locator("foliate-view").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { renderer?: { getContents?: () => { doc: Document }[] } } } };
    for (const { doc } of host.reader?.view?.renderer?.getContents?.() ?? []) {
      const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
      let node: Node | null;
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
  expect(selected).toBe(true);
  const highlightButton = page.getByRole("button", { name: "高亮所选文字" });
  await expect(highlightButton).toBeEnabled();
  await highlightButton.click();
  await expect(page.getByRole("button", { name: "打开高亮列表" })).toContainText("1");
  await expect.poll(() => page.evaluate(() => {
    const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-highlights:"));
    return entry ? JSON.parse(entry[1]).length : 0;
  })).toBe(1);

  await page.reload();
  reader = page.frameLocator("#foliate-reader");
  await expect.poll(() => reader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { annotationsByValue?: Map<string, unknown> } };
    return host.reader?.annotationsByValue?.size || 0;
  })).toBe(1);
  await page.getByRole("button", { name: "打开高亮列表" }).click();
  await expect(page.getByRole("region", { name: "高亮列表" })).toContainText("离线 EPUB 阅读路径");
  await page.getByRole("button", { name: "离线 EPUB 阅读路径" }).click();
  await expect.poll(() => reader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { renderer?: { getContents?: () => { overlayer?: { element?: SVGSVGElement } }[] } } } };
    return host.reader?.view?.renderer?.getContents?.().some(item => (item.overlayer?.element?.childElementCount || 0) > 0) || false;
  })).toBe(true);
  expect(modalDialogs).toBe(0);
  await expect(page.getByRole("region", { name: "高亮列表" })).toBeVisible();
  await page.getByRole("button", { name: "删除高亮" }).click();
  await expect(page.getByRole("button", { name: "打开高亮列表" })).toContainText("0");
  await expect.poll(() => reader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { annotationsByValue?: Map<string, unknown> } };
    return host.reader?.annotationsByValue?.size || 0;
  })).toBe(0);
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

test("supports text-book progress and bookmarks across reloads", async ({ page }) => {
  const text = Array.from({ length: 180 }, (_, index) => `第${index + 1}段：用于验证纯文本长文阅读位置和书签恢复。`).join("\n\n");
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({ name: "长文进度验收.txt", mimeType: "text/plain", buffer: Buffer.from(text, "utf8") });
  await page.getByRole("button", { name: "打开《长文进度验收》" }).click();

  const frame = page.frameLocator("#foliate-reader");
  await expect(frame.locator("article")).toContainText("第180段");
  await expect(page.getByRole("button", { name: "添加或移除当前书签" })).toBeEnabled();
  await page.getByRole("button", { name: "阅读设置" }).click();
  await expect(page.getByRole("region", { name: "阅读设置" })).toBeVisible();
  await page.getByLabel("字号").fill("24");
  await page.getByLabel("背景").selectOption("sepia");
  await expect(frame.locator("body")).toHaveCSS("background-color", "rgb(244, 236, 216)");
  await page.getByRole("button", { name: "阅读设置" }).click();
  await frame.locator("html").evaluate(element => element.scrollTo(0, element.scrollHeight));
  await expect.poll(() => page.evaluate(() => {
    const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-reader-location:"));
    return entry ? JSON.parse(entry[1]).fraction : 0;
  })).toBeGreaterThan(0.5);
  await page.getByRole("button", { name: "添加或移除当前书签" }).click();
  await expect(page.getByRole("button", { name: "添加或移除当前书签" })).toHaveText("已标记");

  await page.reload();
  await expect(frame.locator("article")).toContainText("第180段");
  await page.getByRole("button", { name: "阅读设置" }).click();
  await expect(page.getByLabel("字号")).toHaveValue("24");
  await expect(page.getByLabel("背景")).toHaveValue("sepia");
  await page.getByRole("button", { name: "阅读设置" }).click();
  await expect.poll(() => frame.locator("html").evaluate(element => element.scrollTop / Math.max(1, element.scrollHeight - element.clientHeight))).toBeGreaterThan(0.5);
  await expect(page.getByRole("button", { name: "添加或移除当前书签" })).toHaveText("已标记");
  await frame.locator("html").evaluate(element => element.scrollTo(0, 0));
  await page.getByRole("button", { name: "打开书签列表" }).click();
  await page.getByRole("region", { name: "书签列表" }).locator("button:not([aria-label])").click();
  await expect.poll(() => frame.locator("html").evaluate(element => element.scrollTop / Math.max(1, element.scrollHeight - element.clientHeight))).toBeGreaterThan(0.5);
});

test("records short reading sessions and splits them at local midnight", async ({ page }) => {
  await page.clock.install({ time: new Date("2026-09-30T23:59:50") });
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({ name: "short-session.txt", mimeType: "text/plain", buffer: Buffer.from("阅读计时验收正文") });
  await page.getByRole("button", { name: "打开《short-session》" }).click();
  await expect(page.frameLocator("#foliate-reader").locator("article")).toContainText("阅读计时验收正文");

  await page.clock.fastForward(16_000);
  await page.goto("/");
  const sessions = await page.evaluate(() => {
    const stats = JSON.parse(localStorage.getItem("hyes:hyes_stats.json") || "{}");
    return stats.sessions as { date: string; duration: number }[];
  });
  expect(sessions.map(session => session.date).sort()).toEqual(["2026-09-30", "2026-10-01"]);
  const totalMinutes = sessions.reduce((total, session) => total + session.duration, 0);
  expect(totalMinutes).toBeGreaterThan(0.25);
  expect(totalMinutes).toBeLessThan(0.28);
});

test("opens a multi-page PDF and restores the selected page", async ({ page }) => {
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({ name: "两页PDF验收.pdf", mimeType: "application/pdf", buffer: createPdfFixture(2) });
  await page.getByRole("button", { name: "打开《两页PDF验收》" }).click();

  const reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  await expect(page.getByRole("button", { name: "搜索正文" })).toHaveCount(0);
  await expect.poll(() => reader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { book?: { sections?: unknown[] } } } };
    return host.reader?.view?.book?.sections?.length;
  })).toBe(2);
  await reader.locator("foliate-view").evaluate(element => {
    const view = element as HTMLElement & { goTo: (index: number) => Promise<void> };
    return view.goTo(1);
  });
  await expect.poll(() => page.evaluate(() => {
    const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-reader-location:"));
    return entry ? JSON.parse(entry[1]).fraction : 0;
  })).toBeGreaterThan(0.5);
  await page.getByRole("button", { name: "阅读设置" }).click();
  await expect(reader.getByRole("region", { name: "阅读设置" })).toBeVisible();
  await reader.locator("#reading-theme").selectOption("sepia");
  await page.getByRole("button", { name: "添加或移除当前书签" }).click();
  await page.reload();
  await expect(reader.locator("foliate-view")).toBeVisible();
  await expect(reader.locator("#reading-theme")).toHaveValue("sepia");
  await expect(page.getByRole("button", { name: "添加或移除当前书签" })).toHaveText("已标记");
});

test("opens a multi-page CBZ and moves between comic pages", async ({ page }) => {
  const pixel = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p4sAAAAASUVORK5CYII=", "base64");
  await page.goto("/");
  const chooserPromise = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "添加文件" }).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({ name: "两页漫画验收.cbz", mimeType: "application/vnd.comicbook+zip", buffer: createZipFixture([{ name: "001.png", data: pixel }, { name: "002.png", data: pixel }]) });
  await page.getByRole("button", { name: "打开《两页漫画验收》" }).click();

  const reader = page.frameLocator("#foliate-reader");
  await expect(reader.locator("foliate-view")).toBeVisible();
  await expect(page.getByRole("button", { name: "搜索正文" })).toHaveCount(0);
  await expect.poll(() => reader.locator("body").evaluate(() => {
    const host = window as unknown as { reader?: { view?: { book?: { sections?: unknown[] } } } };
    return host.reader?.view?.book?.sections?.length;
  })).toBe(2);
  await reader.locator("foliate-view").evaluate(element => {
    const view = element as HTMLElement & { goTo: (index: number) => Promise<void> };
    return view.goTo(1);
  });
  await expect.poll(() => page.evaluate(() => {
    const entry = Object.entries(localStorage).find(([key]) => key.startsWith("hyes-reader-location:"));
    return entry ? JSON.parse(entry[1]).fraction : 0;
  })).toBeGreaterThan(0.5);
  await page.getByRole("button", { name: "添加或移除当前书签" }).click();
  await page.reload();
  await expect(reader.locator("foliate-view")).toBeVisible();
  await expect(page.getByRole("button", { name: "添加或移除当前书签" })).toHaveText("已标记");
});

test("removes a browser book only after its shelf entry is saved", async ({ page }) => {
  const dialogs: string[] = [];
  page.on("dialog", dialog => {
    dialogs.push(dialog.message());
    void dialog.dismiss();
  });
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
  expect(dialogs).toEqual([]);
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
