import { describe, expect, it } from "vitest";
import { BACKUP_SCHEMA_VERSION, verifyBackup } from "./backup";

const good = { schemaVersion: BACKUP_SCHEMA_VERSION, exportedAt: "2026-01-01T00:00:00.000Z", shop: { id: "shop" }, records: { customers: [], transactions: [], jewellery_items: [], payments: [], interest_events: [], app_settings: [], audit_logs: [] }, photoManifest: [], integrity: { algorithm: "SHA-256", digest: "bad", rowCounts: { customers: 0, transactions: 0, jewellery_items: 0, payments: 0, interest_events: 0, app_settings: 0, audit_logs: 0 } } };
describe("backup validation", () => {
  it("rejects a changed or corrupt backup", async () => expect((await verifyBackup(good)).errors).toContain("Integrity check failed. The backup may be corrupt or altered."));
  it("rejects an unsupported schema version", async () => expect((await verifyBackup({ ...good, schemaVersion: 99 })).errors[0]).toContain("Unsupported backup schema version"));
});
