import { defineConfig, devices } from "@playwright/test";
import { tmpdir } from "node:os";
import { join } from "node:path";

const port = Number(process.env.HYESREAD_E2E_PORT ?? 3187);
const baseURL = `http://127.0.0.1:${port}`;
const localBrowser = process.env.HYESREAD_E2E_CHROME_PATH
  ? { launchOptions: { executablePath: process.env.HYESREAD_E2E_CHROME_PATH } }
  : {};

export default defineConfig({
  testDir: "./tests/e2e",
  workers: 2,
  outputDir: join(tmpdir(), `hyesread-playwright-${process.pid}`),
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "desktop-chromium", use: { ...devices["Desktop Chrome"], ...localBrowser } },
    { name: "mobile-chromium", use: { ...devices["Pixel 7"], ...localBrowser } },
  ],
  webServer: {
    command: `pnpm dev --hostname 127.0.0.1 --port ${port}`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
