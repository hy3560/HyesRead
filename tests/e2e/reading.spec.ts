import { expect, test } from "@playwright/test";
import { resolve } from "node:path";

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
  await expect(page.getByRole("button", { name: "搜索正文" })).toHaveCount(0);
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
