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
