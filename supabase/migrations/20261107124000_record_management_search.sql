-- Trigram indexes support debounced partial-text lookup without opening a
-- cross-shop search surface; RLS still scopes every returned row.
create extension if not exists pg_trgm;
create index customers_shop_name_trgm_idx on public.customers using gin (full_name gin_trgm_ops);
create index customers_shop_mobile_normalized_idx on public.customers (shop_id, mobile_normalized);
create index customers_shop_code_idx on public.customers (shop_id, customer_code);
create index transactions_shop_pledge_code_idx on public.transactions (shop_id, pledge_code);
create index transactions_shop_status_issue_idx on public.transactions (shop_id, status, issue_date desc);
create index jewellery_items_name_trgm_idx on public.jewellery_items using gin (jewellery_name gin_trgm_ops);
create index payments_transaction_date_method_idx on public.payments (transaction_id, payment_date desc, payment_method);
