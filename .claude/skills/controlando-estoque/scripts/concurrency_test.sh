#!/usr/bin/env bash
# Teste de concorrência: N checkouts paralelos para 1 SKU com estoque < N.
# Uso: DATABASE_URL=postgres://... ./concurrency_test.sh [estoque=5] [checkouts=50]
# Use SEMPRE um banco de desenvolvimento/descartável: o script cria e apaga dados de teste.
set -euo pipefail
: "${DATABASE_URL:?defina DATABASE_URL (banco de DEV)}"
STOCK=${1:-5}; N=${2:-50}
Q() { psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -qtAX -c "$1"; }

PID=$(Q "insert into products (sku,name,price_cents) values ('TEST-'||gen_random_uuid(),'teste',100) returning id")
Q "insert into stock (product_id,on_hand) values ('$PID',$STOCK)"

for i in $(seq 1 "$N"); do
  ( psql "$DATABASE_URL" -qtAX -c "select reserve_stock('cart-$PID-$i','[{\"product_id\":\"$PID\",\"qty\":1}]')" >/dev/null 2>&1 \
      && echo ok || echo fail ) &
done | sort | uniq -c
wait

read -r ON RES <<<"$(Q "select on_hand, reserved from stock where product_id='$PID'" | tr '|' ' ')"
echo "on_hand=$ON reserved=$RES (esperado reserved=$STOCK)"
[ "$RES" -le "$ON" ] && [ "$RES" -eq "$STOCK" ] && echo "PASSOU" || { echo "FALHOU"; exit 1; }

Q "delete from stock_movements where product_id='$PID'; delete from reservation_items where product_id='$PID';
   delete from reservations where cart_id like 'cart-$PID-%'; delete from stock where product_id='$PID'; delete from products where id='$PID'"
