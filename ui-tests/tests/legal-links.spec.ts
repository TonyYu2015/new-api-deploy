import { expect, test } from "@playwright/test";

// The CCAI home no longer renders a footer of its own: the public footer lives
// in PublicLayout and must keep the operator-configured footer HTML plus the
// User Agreement / Privacy Policy links on every public page.
test.describe("Public footer legal links", () => {
  for (const path of ["/", "/pricing"]) {
    test(`${path} shows the legal document links in the footer`, async ({
      page
    }) => {
      await page.goto(path, { waitUntil: "domcontentloaded" });

      const footer = page.locator("footer").first();
      await expect(footer).toBeVisible();
      await expect(
        footer.locator('a[href="/user-agreement"]')
      ).toHaveText(/User Agreement/i);
      await expect(
        footer.locator('a[href="/privacy-policy"]')
      ).toHaveText(/Privacy Policy/i);
    });
  }

  test("the user agreement page renders the configured document", async ({
    page
  }) => {
    await page.goto("/user-agreement", { waitUntil: "domcontentloaded" });

    await expect(
      page.locator("footer a[href='/user-agreement']")
    ).toBeVisible();
    await expect(page.locator("body")).toContainText(
      "CCAI Service Terms of Service"
    );
  });

  test("the privacy policy page renders the configured document", async ({
    page
  }) => {
    await page.goto("/privacy-policy", { waitUntil: "domcontentloaded" });

    await expect(
      page.locator("footer a[href='/privacy-policy']")
    ).toBeVisible();
    await expect(page.locator("body")).toContainText(
      "CCAI Service Privacy Policy"
    );
  });
});
