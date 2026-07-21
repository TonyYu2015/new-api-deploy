import { defineConfig, devices } from "@playwright/test";
import path from "node:path";

for (const key of [
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "ALL_PROXY",
  "http_proxy",
  "https_proxy",
  "all_proxy"
]) {
  delete process.env[key];
}

const baseURL = process.env.E2E_BASE_URL || "https://test.ccaiservice.com";
const launchArgs = ["--no-proxy-server"];
if (process.env.E2E_DIRECT_ORIGIN === "true") {
  launchArgs.push(
    "--host-resolver-rules=MAP test.ccaiservice.com 127.0.0.1"
  );
}
const storageState =
  process.env.E2E_STORAGE_STATE ||
  path.join(__dirname, ".auth", "user.json");

export default defineConfig({
  testDir: "./tests",
  globalSetup: require.resolve("./tests/global.setup"),
  fullyParallel: false,
  forbidOnly: true,
  retries: 1,
  reporter: [["list"], ["html", { open: "never" }]],
  outputDir: "test-results",
  timeout: 90_000,
  expect: {
    timeout: 10_000,
    toHaveScreenshot: {
      animations: "disabled",
      maxDiffPixelRatio: 0.01
    }
  },
  use: {
    baseURL,
    storageState,
    launchOptions: {
      args: launchArgs
    },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure"
  },
  projects: [
    {
      name: "desktop",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1440, height: 1000 }
      }
    },
    {
      name: "mobile",
      use: {
        ...devices["Pixel 7"]
      }
    }
  ]
});
