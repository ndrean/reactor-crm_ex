# NLEx Router — Pentest Instructions

## What This App Does

NLEx is a multi-tenant CRM workflow runner. Users send natural language (French) via HTTP or Telegram, and an LLM classifies the intent into structured actions (create contact, list todos, etc.) that execute against a PostgreSQL database. Each tenant gets an isolated Postgres schema.

## Tech Stack & Architecture

- **Elixir/Phoenix** JSON API (no HTML views, no CSRF tokens)
- **PostgreSQL** with schema-per-tenant isolation (`customer_<tenant_id>`)
- **Mistral AI** LLM for intent classification (user text → JSON action)
- **Oban** background job queue (Postgres-backed)
- **Cloak AES-GCM** encryption for email/phone fields
- **Hammer** rate limiter (30 req/min per user, ETS-backed)
- **Bearer token** auth on admin endpoints (single static token from env var)
- **No authentication on CRM endpoint** — user_id is trusted from the caller (known gap)

## Common Risks for This Architecture

- **Prompt injection**: the "text" field is passed to an LLM. The app uses a system prompt defense and cosine example bank, but no regex filtering for prompt injection. Try to make the LLM return actions it shouldn't (e.g. data export for unauthorized workflows).
- **Tenant isolation bypass**: user_id → tenant lookup. Can a crafted user_id reach another tenant's schema?
- **SQL injection in admin inputs**: tenant_id is used to construct Postgres schema names (`customer_<tenant_id>`). The app validates format but test edge cases.
- **NL2SQL path**: complex queries go through an LLM that generates filter descriptors (not raw SQL), but the descriptors are applied to Ecto queries. Test if malformed filters can leak data.
- **File uploads**: stored at `priv/uploads/{tenant}/{uuid}-{filename}`. Test path traversal in filenames.
- **Webhook SSRF**: tenants can configure a webhook URL. Test internal network access (169.254.169.254, localhost, etc.).
- **Static admin token**: if discoverable via timing attack or error messages, grants full admin access.

## Target

Phoenix/Elixir JSON API running on http://host.docker.internal:4000

## Endpoints

### Public CRM API (no auth — user_id is self-reported)
- POST /api/crm — `{"user_id": "string", "text": "string"}`
- POST /api/crm/confirm — `{"pending_id": "uuid", "decision": "confirm|reject", "user_id": "string"}`

### Admin API (Authorization: bearer <token>)
- POST /api/admin/provision — `{"tenant_id", "company_name", "telegram_chat_id"}`
- POST /api/admin/toggle — `{"tenant_id", "active": bool}`
- PUT /api/admin/subscriptions — `{"tenant_id", "workflow_name", "enabled": bool}`
- PUT /api/admin/webhook — `{"tenant_id", "webhook_url"}`
- GET /api/admin/webhook_secret?tenant_id=...
- GET /api/admin/subjects/:id/export
- DELETE /api/admin/subjects/:id
- POST /api/admin/subjects/:id/email-export

### Other
- GET /api/health — unauthenticated healthcheck
- POST /webhook/telegram — Telegram webhook (x-telegram-bot-api-secret-token header)

## Priority Attack Vectors

1. **Prompt injection** via "text" field — make the LLM classify into unauthorized workflows or leak system prompt content
2. **Tenant isolation** — access data across tenant schemas by manipulating user_id or tenant_id
3. **Admin auth bypass** — brute force, timing attack, header manipulation on bearer token
4. **SSRF via webhook** — set webhook_url to internal addresses
5. **Path traversal** — file upload/download paths
6. **Rate limit evasion** — header rotation, user_id spoofing
7. **NL2SQL injection** — craft text that produces malicious filter descriptors
