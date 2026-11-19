# Kit enxuto de skills Claude

Comandos `/plugin` e `claude mcp` rodam no seu Claude Code local (não em sessões na nuvem). Revise cada skill/MCP antes de instalar; prefira fontes oficiais.

```bash
# Plugins oficiais
/plugin install frontend-design@claude-plugins-official
/plugin install feature-dev@claude-plugins-official
/plugin install code-review@claude-plugins-official
/plugin install security-guidance@claude-plugins-official
/plugin install typescript-lsp@claude-plugins-official   # requer: npm i -g typescript-language-server typescript
/plugin install skill-creator@claude-plugins-official

# Skills oficiais (webapp-testing etc.)
/plugin marketplace add anthropics/skills
/plugin install example-skills@anthropic-agent-skills

# MCPs do núcleo
claude mcp add playwright npx @playwright/mcp@latest
claude mcp add --scope user --header "CONTEXT7_API_KEY: <sua-chave>" --transport http context7 https://mcp.context7.com/mcp

# Supabase: projeto de DEV, somente leitura (substitua <id-dev>)
claude mcp add --scope project --transport http supabase "https://mcp.supabase.com/mcp?project_ref=<id-dev>&read_only=true&features=database,docs,debugging"
/plugin marketplace add supabase/agent-skills
/plugin install postgres-best-practices@supabase-agent-skills

# Pagamentos e deploy (autentique depois com /mcp; use chaves sandbox/teste)
claude mcp add --transport http mercadopago https://mcp.mercadopago.com/mcp
claude mcp add --transport http stripe https://mcp.stripe.com/
claude mcp add --transport http vercel https://mcp.vercel.com
```

## Cuidados
- **Stripe:** até 30/11/2026 migrar para OAuth ou "agent API key"; depois disso chaves secretas comuns recebem 401 no MCP.
- Nunca conecte MCP de banco/pagamento a produção; mantenha aprovação manual de cada chamada.
- Segredos só em `.env`; revise `git diff --cached` antes de cada push.
- Antes de instalar skill de terceiros: leia `SKILL.md` e scripts; rode `uvx mcp-scan@latest --skills`.
- Não instale Playwright + Chrome DevTools + Puppeteer juntos.

## Skills próprias neste repositório
- `.claude/skills/controlando-estoque/` — estoque com ledger, reserva e idempotência (schema e teste de concorrência validados em Postgres 16 local: 50 checkouts paralelos para estoque 5 → 5 reservas, 45 recusas).
