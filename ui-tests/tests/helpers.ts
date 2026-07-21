import { expect, type Page } from "@playwright/test";

export async function openAuthenticatedPage(page: Page, path: string) {
  const accessToken = process.env.E2E_ACCESS_TOKEN;
  const userId = process.env.E2E_USER_ID;
  if (accessToken && userId) {
    const baseURL =
      process.env.E2E_BASE_URL || "https://test.ccaiservice.com";
    const apiOrigin = new URL(baseURL).origin;
    await page.context().route(`${apiOrigin}/api/**`, (route) =>
      route.continue({
        headers: {
          ...route.request().headers(),
          Authorization: `Bearer ${accessToken}`,
          "New-Api-User": userId
        }
      })
    );
  }
  await page.goto(path, { waitUntil: "domcontentloaded" });
  await expect(page).not.toHaveURL(/\/sign-in/);
  await page.locator("#root > *").first().waitFor({ state: "visible" });
  await expect
    .poll(() => page.locator("body").innerText())
    .not.toBe("");
}

export async function expectNoHorizontalOverflow(page: Page) {
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          document.documentElement.scrollWidth <=
          document.documentElement.clientWidth + 1
      )
    )
    .toBe(true);
}
