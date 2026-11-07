import ExcelJS from "exceljs";
import { supabase } from "@/lib/supabase/client";

export const BACKUP_SCHEMA_VERSION = 1;
export const BACKUP_TABLES = ["customers", "transactions", "jewellery_items", "payments", "interest_events", "app_settings", "audit_logs"] as const;
export type BackupTable = (typeof BACKUP_TABLES)[number];
export type ShopBackup = {
  schemaVersion: number;
  exportedAt: string;
  shop: Record<string, unknown>;
  records: Record<BackupTable, Record<string, unknown>[]>;
  photoManifest: { customerId: string; storagePath: string }[];
  integrity: { algorithm: "SHA-256"; digest: string; rowCounts: Record<BackupTable, number> };
};

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value as Record<string, unknown>).sort().map(key => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(",")}}`;
  return JSON.stringify(value);
}

async function sha256(value: unknown) {
  const bytes = new TextEncoder().encode(canonical(value));
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

function save(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob); const link = document.createElement("a");
  link.href = url; link.download = name; link.click(); URL.revokeObjectURL(url);
}

async function allRows(table: BackupTable) {
  const result: Record<string, unknown>[] = []; const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await supabase.from(table).select("*").range(from, from + pageSize - 1);
    if (error) throw error;
    result.push(...(data as Record<string, unknown>[]));
    if ((data?.length ?? 0) < pageSize) return result;
  }
}

export async function createShopBackup(shop: Record<string, unknown>): Promise<ShopBackup> {
  const rows = await Promise.all(BACKUP_TABLES.map(table => allRows(table)));
  const records = Object.fromEntries(BACKUP_TABLES.map((table, index) => [table, rows[index]])) as ShopBackup["records"];
  const photoManifest = records.customers.flatMap(customer => typeof customer.photo_path === "string" ? [{ customerId: String(customer.id), storagePath: customer.photo_path }] : []);
  const payload = { schemaVersion: BACKUP_SCHEMA_VERSION, exportedAt: new Date().toISOString(), shop, records, photoManifest };
  const rowCounts = Object.fromEntries(BACKUP_TABLES.map(table => [table, records[table].length])) as Record<BackupTable, number>;
  return { ...payload, integrity: { algorithm: "SHA-256", digest: await sha256(payload), rowCounts } };
}

export async function verifyBackup(input: unknown): Promise<{ backup?: ShopBackup; errors: string[] }> {
  const errors: string[] = [];
  if (!input || typeof input !== "object") return { errors: ["The file is not a backup object."] };
  const backup = input as Partial<ShopBackup>;
  if (backup.schemaVersion !== BACKUP_SCHEMA_VERSION) errors.push(`Unsupported backup schema version. Expected ${BACKUP_SCHEMA_VERSION}.`);
  if (!backup.shop || !backup.records || !backup.integrity || !Array.isArray(backup.photoManifest)) errors.push("Required backup sections are missing.");
  for (const table of BACKUP_TABLES) if (!Array.isArray(backup.records?.[table])) errors.push(`Missing records.${table}.`);
  if (errors.length) return { errors };
  const payload = { schemaVersion: backup.schemaVersion, exportedAt: backup.exportedAt, shop: backup.shop, records: backup.records, photoManifest: backup.photoManifest };
  if (await sha256(payload) !== backup.integrity!.digest) errors.push("Integrity check failed. The backup may be corrupt or altered.");
  for (const table of BACKUP_TABLES) if (backup.integrity!.rowCounts?.[table] !== backup.records![table].length) errors.push(`Row-count mismatch for ${table}.`);
  const seen = new Set<string>();
  for (const table of BACKUP_TABLES) for (const row of backup.records![table]) {
    if (typeof row.id !== "string") { errors.push(`${table} has a row without a stable id.`); continue; }
    const key = `${table}:${row.id}`; if (seen.has(key)) errors.push(`Duplicate ${table} id ${row.id}.`); seen.add(key);
  }
  const customers = new Set(backup.records!.customers.map(row => String(row.id)));
  const transactions = new Set(backup.records!.transactions.map(row => String(row.id)));
  const payments = new Set(backup.records!.payments.map(row => String(row.id)));
  for (const row of backup.records!.transactions) if (!customers.has(String(row.customer_id))) errors.push("A transaction references a missing customer.");
  for (const table of ["jewellery_items", "payments", "interest_events"] as const) for (const row of backup.records![table]) if (!transactions.has(String(row.transaction_id))) errors.push(`${table} references a missing transaction.`);
  for (const row of backup.records!.interest_events) if (row.related_payment_id && !payments.has(String(row.related_payment_id))) errors.push("An interest event references a missing payment.");
  for (const photo of backup.photoManifest!) if (!customers.has(photo.customerId) || !photo.storagePath) errors.push("Photo manifest has an invalid customer reference.");
  return errors.length ? { errors } : { backup: backup as ShopBackup, errors };
}

export function downloadJsonBackup(backup: ShopBackup) { save(new Blob([JSON.stringify(backup, null, 2)], { type: "application/json" }), `shop-backup-${backup.exportedAt.slice(0, 10)}.json`); }

export async function downloadWorkbook(backup: ShopBackup) {
  const workbook = new ExcelJS.Workbook();
  for (const [name, rows] of Object.entries({ Shop: [backup.shop], ...backup.records, PhotoManifest: backup.photoManifest })) {
    const typedRows = rows as Record<string, unknown>[];
    const sheet = workbook.addWorksheet(name.slice(0, 31)); const keys = [...new Set(typedRows.flatMap(row => Object.keys(row)))];
    sheet.addRow(keys); for (const row of typedRows) sheet.addRow(keys.map(key => typeof row[key] === "object" && row[key] !== null ? JSON.stringify(row[key]) : row[key] ?? ""));
    sheet.getRow(1).font = { bold: true }; sheet.columns.forEach(column => { column.width = 22; });
  }
  const bytes = await workbook.xlsx.writeBuffer(); save(new Blob([bytes], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), `shop-export-${backup.exportedAt.slice(0, 10)}.xlsx`);
}

export function downloadCsv(backup: ShopBackup, table: BackupTable) {
  const rows = backup.records[table]; const keys = [...new Set(rows.flatMap(row => Object.keys(row)))];
  const quote = (value: unknown) => `"${String(typeof value === "object" && value !== null ? JSON.stringify(value) : value ?? "").replaceAll('"', '""')}"`;
  save(new Blob([[keys.join(","), ...rows.map(row => keys.map(key => quote(row[key])).join(","))].join("\r\n")], { type: "text/csv;charset=utf-8" }), `${table}.csv`);
}
