import { test, expect } from "@playwright/test";

test.describe("Desktop navigation", () => {
  test("loads the Dashboard at the root route", async ({ page }) => {
    await page.goto("/");
    await expect(
      page.getByRole("heading", { name: "Dashboard", level: 2 }),
    ).toBeVisible();
    await expect(page.getByText(/Demo mode — sample data only/)).toBeVisible();
  });

  test("sidebar links navigate to each of the 9 pages", async ({ page }) => {
    await page.goto("/");
    const nav = page.locator("aside nav");

    const routes: Array<[label: string, heading: string]> = [
      ["Add Customer", "Add Customer"],
      ["New Jewellery Loan", "New Jewellery Loan"],
      ["Receive Payment", "Receive Payment"],
      ["Customer Records", "Customer Records"],
      ["Active Transactions", "Active Transactions"],
      ["Completed Transactions", "Completed Transactions"],
      ["Reports", "Reports"],
      ["Settings & Backup", "Settings & Backup"],
      ["Dashboard", "Dashboard"],
    ];

    for (const [label, heading] of routes) {
      await nav.getByRole("link", { name: label }).click();
      await expect(
        page.getByRole("heading", { name: heading, level: 2 }),
      ).toBeVisible();
    }
  });

  test("shows a 404 page for an unknown route", async ({ page }) => {
    await page.goto("/this-route-does-not-exist");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
    await page.getByRole("link", { name: "Back to Dashboard" }).click();
    await expect(page).toHaveURL("/");
  });
});

test.describe("Mobile navigation", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("opens the drawer and navigates", async ({ page }) => {
    await page.goto("/");
    const dialog = page.getByRole("dialog");
    await page.getByRole("button", { name: "Open navigation menu" }).click();
    await expect(dialog).toBeVisible();
    await dialog.getByRole("link", { name: "Customer Records" }).click();
    await expect(
      page.getByRole("heading", { name: "Customer Records", level: 2 }),
    ).toBeVisible();
    // drawer should close after navigating
    await expect(dialog).not.toBeVisible();
  });
});

test.describe("Customer Records interactions", () => {
  test("search filters the table, and clearing restores it", async ({ page }) => {
    await page.goto("/customers");
    const table = page.getByRole("table");
    await expect(table.getByText("Ramesh Kulkarni")).toBeVisible();
    await expect(table.getByText("Sunita Deshmukh")).toBeVisible();

    await page.getByPlaceholder("Search by name or phone…").fill("ramesh");
    await expect(table.getByText("Ramesh Kulkarni")).toBeVisible();
    await expect(table.getByText("Sunita Deshmukh")).not.toBeVisible();

    await page.getByLabel("Clear search").click();
    await expect(table.getByText("Sunita Deshmukh")).toBeVisible();
  });

  test("disabled View action shows an explanation on focus", async ({ page }) => {
    await page.goto("/customers");
    // The disabled button sits inside a focusable wrapper span (see
    // DisabledAction) so the tooltip is reachable via keyboard, not just hover.
    await page.locator("table tbody tr").first().locator("span[tabindex]").focus();
    await expect(
      page.getByText("Customer detail view ships in Phase 2"),
    ).toBeVisible();
  });
});

test.describe("Add Customer form", () => {
  test("validates required fields and succeeds with valid data", async ({
    page,
  }) => {
    await page.goto("/customers/new");
    await page.getByRole("button", { name: "Add Customer" }).click();
    await expect(page.getByText("Enter the customer's full name")).toBeVisible();

    await page.getByLabel("Full name").fill("Test Customer");
    await page.getByLabel("Phone", { exact: true }).fill("9876543210");
    await page.getByLabel("Address").fill("123 Test Street, Pune");
    await page.getByLabel("ID proof number").fill("123456789012");
    await page.getByRole("button", { name: "Add Customer" }).click();

    await expect(page.getByText("Customer added (demo)")).toBeVisible();
  });
});

test.describe("Receive Payment", () => {
  test("pre-selects the loan when navigated from Active Transactions", async ({
    page,
  }) => {
    await page.goto("/loans/active");
    await page
      .getByRole("row", { name: /Ramesh Kulkarni/ })
      .getByRole("link", { name: "Receive Payment" })
      .click();
    await expect(
      page.getByRole("heading", { name: "Receive Payment", level: 2 }),
    ).toBeVisible();
    await expect(page.getByText("Outstanding principal")).toBeVisible();
  });
});
