import { expect, test } from "@playwright/test";
import {
  expectNoHorizontalOverflow,
  openAuthenticatedPage
} from "./helpers";

const hiddenText = [
  "Current Balance",
  "Total Usage",
  "API Requests",
  "Sidebar Personal Settings",
  "Access Token",
  "Passkey Login",
  "Two-Factor Authentication",
  "Receive Upstream Model Update Notifications",
  "Accept Unpriced Models",
  "Record IP Address"
];

test.describe("Profile UI", () => {
  test.beforeEach(async ({ page }) => {
    await openAuthenticatedPage(page, "/profile");
  });

  test("matches the streamlined profile requirements", async ({ page }) => {
    for (const text of hiddenText) {
      await expect(page.getByText(text, { exact: true }).first()).toBeHidden();
    }

    await expect(
      page.getByRole("button", { name: /Change Password/i })
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: /Delete Account/i })
    ).toBeVisible();
    await expect(page.getByText("Language Preferences", { exact: true })).toBeVisible();

    await page.getByRole("tab", { name: /Settings/ }).click();
    await expect(page.getByText("Email", { exact: true }).first()).toBeVisible();

    for (const text of ["Webhook", "Bark", "Gotify"]) {
      await expect(page.getByText(text, { exact: true }).first()).toBeHidden();
    }

    const rightRail = page.locator(
      'div[class~="xl:sticky"][class~="xl:top-6"]'
    );
    await expect(rightRail).toHaveCount(0);
    await expectNoHorizontalOverflow(page);
  });

});

test.describe("Profile visual", () => {
  test.skip(process.env.E2E_VISUAL !== "1", "Visual baselines are opt-in.");

  test("matches the reviewed profile snapshot", async ({ page }) => {
    await openAuthenticatedPage(page, "/profile");
    await expect(page.locator("main")).toHaveScreenshot("profile.png", {
      mask: [page.locator("h1").first()]
    });
  });
});
