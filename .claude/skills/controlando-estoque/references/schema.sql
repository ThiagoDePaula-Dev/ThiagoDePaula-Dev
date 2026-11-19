-- Esquema de referência: estoque com ledger, reserva e idempotência (PostgreSQL / Supabase)
create extension if not exists pgcrypto;

create table products (
  id         uuid primary key default gen_random_uuid(),
  sku        text unique not null,
  name       text not null,
  price_cents integer not null check (price_cents >= 0)
);

-- Projeção atualizada na mesma transação dos lançamentos do ledger
create table stock (
  product_id uuid primary key references products(id),
  on_hand    integer not null default 0 check (on_hand >= 0),
  reserved   integer not null default 0 check (reserved >= 0),
  constraint reserved_lte_on_hand check (reserved <= on_hand)
);

-- Ledger: somente inserção. Correções = lançamentos compensatórios.
create table stock_movements (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references products(id),
  qty_delta       integer not null check (qty_delta <> 0),
  reason          text not null check (reason in
                    ('purchase','sale','reservation','release','adjustment','return')),
  ref_id          text,
  idempotency_key text unique not null,
  created_at      timestamptz not null default now()
);

create table reservations (
  id         uuid primary key default gen_random_uuid(),
  cart_id    text unique not null,            -- criação idempotente
  status     text not null default 'held'
             check (status in ('held','confirmed','released','expired')),
  expires_at timestamptz not null
);

create table reservation_items (
  reservation_id uuid not null references reservations(id),
  product_id     uuid not null references products(id),
  qty            integer not null check (qty > 0),
  primary key (reservation_id, product_id)
);

-- Reserva atômica. Trava linhas em ordem de produto (evita deadlock).
create or replace function reserve_stock(p_cart_id text, p_items jsonb, p_ttl interval default '15 minutes')
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_res uuid; r record; v_rows int;
begin
  insert into reservations (cart_id, expires_at) values (p_cart_id, now() + p_ttl)
    on conflict (cart_id) do nothing returning id into v_res;
  if v_res is null then   -- reentrega/repetição: devolve a reserva existente
    select id into v_res from reservations where cart_id = p_cart_id;
    return v_res;
  end if;

  for r in
    select (e->>'product_id')::uuid as product_id, (e->>'qty')::int as qty
    from jsonb_array_elements(p_items) e order by 1
  loop
    update stock set reserved = reserved + r.qty
     where product_id = r.product_id and on_hand - reserved >= r.qty;
    get diagnostics v_rows = row_count;
    if v_rows = 0 then raise exception 'sem_estoque:%', r.product_id; end if;  -- desfaz tudo
    insert into reservation_items values (v_res, r.product_id, r.qty);
    insert into stock_movements (product_id, qty_delta, reason, ref_id, idempotency_key)
      values (r.product_id, 0 + r.qty, 'reservation', p_cart_id, 'res:' || p_cart_id || ':' || r.product_id);
  end loop;
  return v_res;
end $$;

-- Libera reservas vencidas (rodar a cada 5 min; SKIP LOCKED permite varredores paralelos)
create or replace function expire_reservations() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
begin
  for r in select id, cart_id from reservations
           where status = 'held' and expires_at <= now()
           for update skip locked
  loop
    update stock s set reserved = s.reserved - i.qty
      from reservation_items i where i.reservation_id = r.id and s.product_id = i.product_id;
    insert into stock_movements (product_id, qty_delta, reason, ref_id, idempotency_key)
      select product_id, qty, 'release', r.cart_id, 'rel:' || r.cart_id || ':' || product_id
      from reservation_items where reservation_id = r.id;
    update reservations set status = 'expired' where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- RLS: tudo fechado para anon/authenticated; mudanças só via funções no servidor
alter table products          enable row level security;
alter table stock             enable row level security;
alter table stock_movements   enable row level security;
alter table reservations      enable row level security;
alter table reservation_items enable row level security;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke execute on function reserve_stock(text, jsonb, interval) from public, anon, authenticated;
    revoke execute on function expire_reservations() from public, anon, authenticated;
  end if;
end $$;
