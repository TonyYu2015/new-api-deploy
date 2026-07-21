import { expect, test } from "@playwright/test";
import {
  expectNoHorizontalOverflow,
  openAuthenticatedPage
} from "./helpers";

const PANCAKE_QUOTA_BASELINE_STORAGE_KEY =
  "waffo_pancake_quota_before_payment";

function quotaAsDollarBalance(quota: number) {
  return `$${quota / 500_000}`;
}

test.describe("Wallet UI", () => {
  test("matches the custom amount wallet requirements", async ({ page }) => {
    await openAuthenticatedPage(page, "/wallet");

    const customAmountLabel = page.getByText("Custom Amount", { exact: true });
    await expect(customAmountLabel).toBeVisible();

    const customAmountSection = customAmountLabel.locator("xpath=..");
    const presetAmountSection = customAmountSection.locator(
      "xpath=preceding-sibling::*[1]"
    );
    await expect(presetAmountSection).toBeHidden();

    await expect(page.getByText("Have a Code?", { exact: true })).toBeHidden();
    await expect(
      page.getByText("Referral Program", { exact: true })
    ).toBeHidden();

    const amount = page.locator("#topup-amount");
    await expect(amount).toBeVisible();
    await expect(amount).toHaveValue("0");
    await expect(amount).toHaveClass(
      /(?:^|\s)text-muted-foreground(?:\s|$)/
    );
    await expect(amount).not.toHaveClass(
      /(?:^|\s)text-foreground(?:\s|$)/
    );

    await amount.focus();
    await expect(amount).toHaveValue("");
    await amount.clear();
    await expect(amount).toHaveValue("");
    await page.waitForTimeout(300);
    await expect(amount).toHaveValue("");

    const paymentMethod = page
      .getByRole("button", { name: /Waffo Pancake|Credit Card/i })
      .first();
    await expect(paymentMethod).toBeDisabled();

    await amount.fill("25");
    await expect(amount).toHaveValue("25");
    await expect(amount).toHaveClass(/(?:^|\s)text-foreground(?:\s|$)/);
    await expect(amount).not.toHaveClass(
      /(?:^|\s)text-muted-foreground(?:\s|$)/
    );
    await expect(paymentMethod).toBeEnabled();

    await amount.clear();
    await expect(amount).toHaveValue("");
    await expect(paymentMethod).toBeDisabled();
    await amount.blur();
    await expect(amount).toHaveValue("0");
    await expect(amount).toHaveClass(
      /(?:^|\s)text-muted-foreground(?:\s|$)/
    );
    await expect(paymentMethod).toBeDisabled();

    await expectNoHorizontalOverflow(page);
  });

  test("waits for the current Pancake credit before clearing the return marker", async ({
    page
  }) => {
    await openAuthenticatedPage(page, "/wallet");

    const currentUser = await page.evaluate(() =>
      JSON.parse(window.localStorage.getItem("user") || "null")
    );
    expect(currentUser).toBeTruthy();
    expect(Number.isSafeInteger(currentUser.quota)).toBe(true);

    const quotaBeforePayment = currentUser.quota as number;
    const staleCachedQuota = Math.max(0, quotaBeforePayment - 5_000_000);
    const creditedQuota = quotaBeforePayment + 5_000_000;
    let selfRequests = 0;
    let creditAvailable = false;

    await page.route("**/api/user/self", async (route) => {
      selfRequests += 1;
      const quota =
        selfRequests === 1
          ? staleCachedQuota
          : creditAvailable
            ? creditedQuota
            : quotaBeforePayment;

      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          success: true,
          message: "success",
          data: { ...currentUser, quota }
        })
      });
    });

    await page.addInitScript(
      ({ key, quota }) => window.sessionStorage.setItem(key, String(quota)),
      { key: PANCAKE_QUOTA_BASELINE_STORAGE_KEY, quota: quotaBeforePayment }
    );
    await page.goto("/wallet?payment_return=pancake", {
      waitUntil: "domcontentloaded"
    });

    await expect.poll(() => selfRequests).toBeGreaterThanOrEqual(3);
    await expect(page).toHaveURL(/payment_return=pancake/);

    const balanceCard = page
      .getByText("Current Balance", { exact: true })
      .locator("xpath=../..");
    await expect(balanceCard).toContainText(
      quotaAsDollarBalance(quotaBeforePayment)
    );

    creditAvailable = true;

    await expect(balanceCard).toContainText(quotaAsDollarBalance(creditedQuota));
    await expect(page).not.toHaveURL(/payment_return=pancake/);
    await expect
      .poll(() =>
        page.evaluate(
          (key) => window.sessionStorage.getItem(key),
          PANCAKE_QUOTA_BASELINE_STORAGE_KEY
        )
      )
      .toBeNull();
  });

  test("shows the credited balance for a CLI-created Pancake order", async ({
    page
  }) => {
    const quotaBefore = Number(process.env.E2E_PANCAKE_QUOTA_BEFORE);
    const quotaAfter = Number(process.env.E2E_PANCAKE_QUOTA_AFTER);
    const expectedBalance = process.env.E2E_PANCAKE_EXPECTED_BALANCE;
    test.skip(
      !Number.isSafeInteger(quotaBefore) ||
        !Number.isSafeInteger(quotaAfter) ||
        !expectedBalance,
      "Run through the Pancake CLI flow to supply authoritative quota values."
    );

    let observedQuota: number | null = null;
    page.on("response", async (response) => {
      if (new URL(response.url()).pathname !== "/api/user/self") return;
      try {
        const body = await response.json();
        if (Number.isSafeInteger(body?.data?.quota)) {
          observedQuota = body.data.quota;
        }
      } catch {
        // A later successful response can still complete the assertion.
      }
    });

    await page.addInitScript(
      ({ key, quota }) => window.sessionStorage.setItem(key, String(quota)),
      { key: PANCAKE_QUOTA_BASELINE_STORAGE_KEY, quota: quotaBefore }
    );
    await openAuthenticatedPage(page, "/wallet?payment_return=pancake");

    await expect.poll(() => observedQuota).toBe(quotaAfter);
    const balanceCard = page
      .getByText("Current Balance", { exact: true })
      .locator("xpath=../..");
    await expect(balanceCard).toContainText(expectedBalance!);
    await expect(page).not.toHaveURL(/payment_return=pancake/);
  });
});

test.describe("Wallet visual", () => {
  test.skip(process.env.E2E_VISUAL !== "1", "Visual baselines are opt-in.");

  test("matches the reviewed wallet snapshot", async ({ page }) => {
    await openAuthenticatedPage(page, "/wallet");
    await expect(page.locator("#wallet-add-funds")).toHaveScreenshot(
      "wallet-add-funds.png"
    );
  });
});
