import { chromium, type FullConfig } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";

export default async function globalSetup(config: FullConfig) {
  const baseURL = config.projects[0].use.baseURL as string;
  const launchOptions = config.projects[0].use.launchOptions;
  const target = new URL(baseURL);
  if (
    target.hostname !== "test.ccaiservice.com" &&
    process.env.E2E_ALLOW_PRODUCTION !== "true"
  ) {
    throw new Error(
      `Refusing to run UI tests against ${target.hostname}. ` +
        "Use test.ccaiservice.com or explicitly set E2E_ALLOW_PRODUCTION=true."
    );
  }

  const suppliedState = process.env.E2E_STORAGE_STATE;
  if (suppliedState) {
    if (!fs.existsSync(suppliedState)) {
      throw new Error(`E2E_STORAGE_STATE does not exist: ${suppliedState}`);
    }
    return;
  }

  const accessToken = process.env.E2E_ACCESS_TOKEN;
  const userId = process.env.E2E_USER_ID;
  if (accessToken && userId) {
    const browser = await chromium.launch(launchOptions);
    const context = await browser.newContext({
      baseURL,
      extraHTTPHeaders: {
        Authorization: `Bearer ${accessToken}`,
        "New-Api-User": userId
      }
    });
    const page = await context.newPage();
    const response = await page.goto("/api/user/self", {
      waitUntil: "domcontentloaded"
    });
    if (!response) {
      throw new Error("Token authentication returned no response.");
    }
    if (!response.ok()) {
      throw new Error(
        `Token authentication failed with HTTP ${response.status()}.`
      );
    }
    const payload = await response.json();
    if (!payload.success || !payload.data) {
      throw new Error(payload.message || "Token authentication failed.");
    }

    await page.evaluate((user) => {
      window.localStorage.setItem("user", JSON.stringify(user));
    }, payload.data);

    const authFile = path.join(__dirname, "..", ".auth", "user.json");
    fs.mkdirSync(path.dirname(authFile), { recursive: true });
    await context.storageState({ path: authFile });
    await browser.close();
    return;
  }

  const username = process.env.E2E_USERNAME;
  const password = process.env.E2E_PASSWORD;
  if (!username || !password) {
    throw new Error(
      "Provide E2E_ACCESS_TOKEN with E2E_USER_ID, or E2E_USERNAME with " +
        "E2E_PASSWORD, for the staging test account."
    );
  }

  const authFile = path.join(__dirname, "..", ".auth", "user.json");
  fs.mkdirSync(path.dirname(authFile), { recursive: true });

  const browser = await chromium.launch(launchOptions);
  const page = await browser.newPage({ baseURL });
  await page.goto("/sign-in", { waitUntil: "domcontentloaded" });

  const usernameInput = page
    .locator(
      'input[name="username"], input[autocomplete="username"], input[type="email"]'
    )
    .first();
  await usernameInput.fill(username);
  await page.locator('input[type="password"]').first().fill(password);
  await page.locator('button[type="submit"]').click();

  await page.waitForURL(
    (url) => !url.pathname.includes("sign-in"),
    { timeout: 20_000 }
  );
  await page.context().storageState({ path: authFile });
  await browser.close();
}
