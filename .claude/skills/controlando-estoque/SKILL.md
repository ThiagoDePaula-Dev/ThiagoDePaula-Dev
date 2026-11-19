---
name: controlando-estoque
description: Projeta e implementa controle de estoque com SKU, reserva, baixa, ledger e idempotência em PostgreSQL/Supabase. Use ao trabalhar com estoque, SKU, reserva, baixa, checkout ou webhook Pix/cartão (Mercado Pago, Asaas, Stripe).
---

# Controle de estoque (SKU, reserva, idempotência)

Complementa `postgres-best-practices` (Supabase); não duplica regras genéricas de Postgres/RLS.
Schema pronto: `references/schema.sql`. Teste de concorrência: `scripts/concurrency_test.sh`.

## Regras

1. **Identificadores:** PK `uuid` (`gen_random_uuid()`), mais `sku text unique not null` legível. Nunca IDs sequenciais em URLs públicas. "Hash único" de item físico/QR Code = token aleatório com `UNIQUE`, nunca hash de dados adivinháveis.
2. **Ledger:** `stock_movements` só de inserção (`qty_delta`, `reason`, `ref_id`, `idempotency_key UNIQUE`). `stock` é projeção atualizada na mesma transação. Correção = lançamento compensatório, nunca `UPDATE`/`DELETE`.
3. **Concorrência:** `UPDATE ... WHERE on_hand - reserved >= $qty` + `CHECK (reserved <= on_hand)`. Zero linhas = sem estoque. Nunca ler e depois gravar na aplicação. Carrinho com vários SKUs: travar em ordem de SKU/produto.
4. **Idempotência:** chave única em toda escrita vinda de fora (checkout, `event_id` de webhook, ajuste de admin). Reservas: `cart_id UNIQUE` + `ON CONFLICT DO NOTHING`; transições com `WHERE status='held' AND expires_at > now()`.
5. **Pagamentos:** o webhook é a fonte da verdade do "pago"; verifique a assinatura e trate reentrega como no-op (entrega "pelo menos uma vez"). Preço e quantidade vindos do cliente nunca são confiáveis. O prazo do QR Pix deve bater com `expires_at` (inferência: confirme na documentação do provedor).
6. **Segurança:** RLS em todas as tabelas. Estoque e preço mudam só por funções no servidor (`security definer`, `search_path` fixo), nunca pela chave anon.
7. **Expiração:** varrer reservas vencidas a cada ~5 min com `FOR UPDATE SKIP LOCKED` (`expire_reservations()`).
8. **Teste obrigatório:** N checkouts paralelos para um SKU com estoque < N; confirmar que não vendeu além do estoque e que `reserved <= on_hand`. Rode só em banco de DEV.

## Perguntar ao usuário (não presumir)

- Prazo da reserva (15 min serve p/ cartão; Pix com redirecionamento pode precisar de mais).
- Pagamento que chega após o vencimento: reservar de novo ou estornar?
- SKUs muito disputados: como tratar a fila numa única linha?

## Fontes dos padrões

Shopify Engineering ("scaling inventory reservations": ledger como fonte da verdade, atomicidade no MySQL) e Encore (padrão Postgres de reserva com CHECK, UPDATE condicional e SKIP LOCKED).
