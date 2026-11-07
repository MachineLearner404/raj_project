create table public.jewellery_items (
  id uuid primary key default gen_random_uuid(),
  -- Denormalized from transactions.shop_id (copied by the trigger below,
  -- never set by the client). This is deliberate: it lets every RLS
  -- policy in this project compare shop_id directly on the row being
  -- checked, with no join/subquery to transactions — simpler and faster
  -- than policy-time joins, and it cannot drift because it's trigger-set.
  shop_id uuid not null references public.shops (id) on delete restrict,
  transaction_id uuid not null references public.transactions (id) on delete cascade,

  category text not null
    check (category in ('NECKLACE', 'RING', 'BANGLE', 'COIN', 'CHAIN', 'EARRINGS', 'OTHER')),
  description text not null check (char_length(trim(description)) > 0),
  gross_weight_grams numeric(8, 3) not null check (gross_weight_grams > 0),
  net_weight_grams numeric(8, 3) not null check (net_weight_grams > 0),
  stone_weight_grams numeric(8, 3) not null default 0 check (stone_weight_grams >= 0),
  purity_karat smallint not null check (purity_karat between 1 and 24),
  -- Frozen at appraisal time — never re-read live from a rates table
  -- later. See docs/02-database-schema-erd.md's valuation design note.
  gold_rate_used_per_gram numeric(10, 2) not null check (gold_rate_used_per_gram > 0),
  estimated_value numeric(14, 2) not null check (estimated_value > 0),
  condition_notes text,
  created_at timestamptz not null default now(),

  constraint jewellery_items_net_le_gross check (net_weight_grams <= gross_weight_grams)
);

create index jewellery_items_transaction_id_idx on public.jewellery_items (transaction_id);
create index jewellery_items_shop_id_idx on public.jewellery_items (shop_id);

comment on table public.jewellery_items is
  'One or more pledged items per transaction. shop_id is denormalized from the parent transaction — see column comment.';

create or replace function public.jewellery_items_set_shop_id()
returns trigger
language plpgsql
as $$
begin
  select t.shop_id into new.shop_id
    from public.transactions t
    where t.id = new.transaction_id;

  if new.shop_id is null then
    raise exception
      'jewellery_items_set_shop_id: transaction % does not exist', new.transaction_id;
  end if;

  return new;
end;
$$;

create trigger jewellery_items_set_shop_id_trigger
  before insert on public.jewellery_items
  for each row execute function public.jewellery_items_set_shop_id();
