# NLEx Router

A multi-tenant Natural Language Execution Router: an AI-assisted workflow runner to execute Elixir modules with OTP execution guarantees.

Uses **Reactor** for workflow orchestration, **Oban** for durable job processing.
**Phoenix** is used as the HTTP/webhook gateway, and Telegram for mobile devices.


## Design philosophy

Small cloud LLMs, structured outputs, no generated SQL: the LLM picks from a known action set — it never writes free-form code or queries.

- **Constrained classification** — a lightweight model routes user input to predefined workflows and actions. Hallucinations are structurally impossible: the LLM can only select from the registry, not invent capabilities.
- **Two-pass hierarchical routing** — Pass 1 identifies the workflow (cheap, small prompt), Pass 2 extracts the action and parameters (scoped prompt, fewer tokens). Each pass uses the smallest model that gets the job done.
- **Self-improving cosine pre-filtering** — user input is embedded and compared against a bank of example phrases. The top cosine matches hint the LLM as a soft signal. When the cosine hint and the LLM disagree, a stronger model reviews the mismatch and, if confirmed, adds the input to the example bank — making future routing more accurate without manual curation.

```mermaid
flowchart LR
    I[User input] --> CS
    EX[(Example bank)] --> CS[Cosine hints]
    CS --> P1[Pass 1: workflow]
    P1 --> P2[Pass 2: action + params]
    P2 --> RS[(Routing signals)]
    RS -->|"daily: mismatches"| LJ[LLM-judge review]
    LJ -->|"confirmed → embed"| EX
```

## Architecture

#### Ingestion pipeline

```mermaid
graph TB
    A[HTTP POST /api/crm] -->|sync| R[Reactor MasterIngest]
    LV[LiveView Chat] -->|sync| R
    T[Telegram Webhook] -->|async| O[Oban IngestWorker]
    O -->|3 retries| R

    R --> RT[ResolveTenant]
    R --> TR[Transcribe]
    R --> LE[LogExecution]
    RT --> CI[ClassifyIntent]
    TR --> CI
    CI --> DM[DispatchModule]
    LE --> DM
    DM --> FR[FinalizeReply]
```

#### Workflow modules

```mermaid
graph TB
    DM[DispatchModule] -->|contacts| C[Contacts Router]
    DM -->|todos| TD[Todos Router]
    DM -->|data| DE[DataExport]
    DM -->|help| H[Help Module]
    DM -->|none/unknown| FB[Fallback Message]

    C -->|mutation| M[2-step Confirm/Reject]
    TD -->|mutation| M
    DE -->|admin_email set| EM[DataExportEmail via Swoosh]

    FR -->|webhook_url set| WH[WebhookWorker]
    WH -->|HMAC-signed POST| EXT[External System]
```

#### Background workers

```mermaid
graph TB
    PT[PendingTimeoutWorker] -->|auto-reject expired| M[Mutations]
    RW[RetentionWorker] -->|"daily 3AM: anonymize logs >180d"| DB[(Postgres)]
    FCW[FileCleanupWorker] -->|"daily 3:30AM: delete expired files"| DB
    RSW[RoutingSignalWorker] -->|fire-and-forget analytics| DB
    TCW[ThresholdCalibrationWorker] -->|"weekly Sun 4AM: recalibrate"| DB
    ERW[ExampleReviewWorker] -->|"daily 5:30AM: LLM-judge + embed"| DB
```

### MasterIngest Reactor DAG

Auto-generated via `Reactor.Mermaid.to_mermaid/1` -- shows the actual step dependency graph with data flow edges.

Regenerate with:

```bash
mix run -e '{:ok, d} = Reactor.Mermaid.to_mermaid(CrmReactor.Reactors.MasterIngest, direction: :top_to_bottom, output: :binary); IO.puts(d)'
```

```mermaid
flowchart TB
    start{"Start"}
    start==>reactor_MasterIngest
    subgraph reactor_MasterIngest["MasterIngest"]
        direction TB
        input_user_id>"Input user_id"]
        input_raw_input>"Input raw_input"]
        input_is_audio>"Input is_audio"]
        input_channel>"Input channel"]
        input_job_id>"Input job_id"]
        input_user_id -->|user_id|step_tenant
        step_tenant["tenant(ResolveTenant)"]
        input_raw_input -->|raw_input|step_text
        input_is_audio -->|is_audio|step_text
        step_text["text(Transcribe)"]
        step_tenant -->|tenant|step_log
        input_raw_input -->|raw_input|step_log
        input_channel -->|channel|step_log
        input_user_id -->|user_id|step_log
        input_job_id -->|job_id|step_log
        step_log["log(LogExecution)"]
        step_text -->|text|step_classify
        step_tenant -->|tenant|step_classify
        step_classify["classification(ClassifyIntent)"]
        step_classify -->|classification|step_result
        step_tenant -->|tenant|step_result
        input_channel -->|channel|step_result
        input_user_id -->|user_id|step_result
        step_log -->|log|step_result
        step_text -->|text|step_result
        step_result["result(DispatchModule)"]
        step_result -->|result|step_finalize
        step_log -->|log|step_finalize
        step_tenant -->|tenant|step_finalize
        step_classify -->|classification|step_finalize
        step_finalize["finalize(FinalizeReply)"]
        return_MasterIngest{"Return"}
        step_finalize==>return_MasterIngest
    end
```


### Tiered query system

```mermaid
graph TB
    Q[User Query] --> CL[Classifier: intent + routing_path]
    CL -->|"routing_path: deterministic"| DET[Hardcoded Ecto Query]
    CL -->|"routing_path: nl2sql"| NL[NL2SQL Filter Generator]
    NL -->|"{'field','op','value'}"| VAL{Validate filters}
    VAL -->|valid columns + ops| ECT[Parameterized Ecto Query]
    VAL -->|rejected| DET
    NL -->|LLM failure| DET
    DET --> DB[(Postgres)]
    ECT --> DB
```

| Tier | When | How | Safety |
|------|------|-----|--------|
| **Deterministic** | Simple name lookup, basic CRUD | Hardcoded Ecto queries from extracted params | No LLM-generated code |
| **NL2SQL** | Complex filters, date ranges, compound conditions | LLM generates structured filter descriptors `{"field", "op", "value"}` | Parameterized Ecto -- LLM never writes SQL. Schema fields derived from Ecto schemas (no drift). Data never sent to LLM. |

The classifier sets `routing_path: "deterministic" | "nl2sql"`. Module routers try deterministic first, escalate to NL2SQL for reads when needed, and always fall back to deterministic on NL2SQL failure.

### Two-pass intent classification

Text-only requests go through a two-pass pipeline before reaching the action classifier. This keeps the expensive Pass 2 prompt focused on a single workflow's actions rather than the full registry.

```mermaid
graph TB
    Q[User Query] --> E[Embedder: mxbai-embed-large]
    E --> CS[Cosine similarity vs registry_examples]
    CS --> H["top-2 cosine hints: [(workflow, score)]"]
    H --> P1["Pass 1 — mistral-small T=0<br/>{workflow, confidence}"]
    P1 -->|"confidence ≥ threshold"| SC[Scoped registry: workflow only]
    P1 -->|"confidence < threshold"| FR[Full registry]
    SC --> P2["Pass 2 — mistral-small<br/>{action, params, routing_path}"]
    FR --> P2
    P2 --> RS[RoutingSignalWorker: async analytics]
    RS --> DB[(routing_signals)]
    DB --> TC[ThresholdCalibrationWorker: weekly]
    TC --> RT[routing_thresholds]
```

**Graceful degradation chain:**

| Failure | Behaviour |
|---------|-----------|
| Ollama unavailable | Embedder returns `{:error, _}` → cosine hints = `[]` → Pass 1 runs without hints |
| ExamplesCache empty | No examples to compare → cosine hints = `[]` |
| Pass 1 fails | Falls through to single-pass `classify/3` with top cosine hint as routing hint |
| Pass 2 fails | Retried with full registry |

**Confidence thresholds** are stored in `global_registry.routing_thresholds` (default 0.70) and cached in `ThresholdCache` (ETS, direct reads). The `ThresholdCalibrationWorker` recalibrates them weekly from confirmed routing signals using: `new_threshold = avg(pass1_confidence | llm_confirmed, 30d) × 0.85`.

**Populate example phrases** after adding new workflows (or on first deploy):

```bash
mix crm.embed_examples           # seed corpus + embed NULL rows
mix crm.embed_examples --force   # re-embed all rows
```

### LLM classification escalation

Pass 2 (action + params) uses the existing Mistral cascade:

```mermaid
graph LR
    U[Pass 2 input] --> S[Mistral Small]
    S -->|workflow != none| R[Result ✓]
    S -->|workflow == none| L[Mistral Large]
    S -->|API error| O[Ollama qwen2.5:7b]
    L -->|any result| R
    L -->|API error| O
    O -->|success| R
    O -->|failure| E[Error — Oban retries]
```

Pass 1 (workflow selection) uses `mistral-small-latest` at temperature 0 — accurate on the small Pass 1 prompt, negligible cost increase over ministral-3b. No fallback chain. If it fails, the system skips directly to single-pass classification.

Two distinct fallback reasons for Pass 2, handled separately:

| Trigger | Fallback | Reason |
|---------|----------|--------|
| Mistral Small returns `workflow: "none"` | Mistral Large | **Quality escalation** — Small couldn't classify the intent |
| Mistral Small (or Large) API error | Ollama | **Reliability fallback** — API unreachable, use local model |

Ollama runs on the Mac host (Metal GPU) in development, accessed via `127.0.0.1:11435`. On the prod VPS it runs in a container without GPU.

### Semantic routing hints (registry-level)

In addition to the example-bank cosine hints used in Pass 1, each `module_registry` action row carries a `hint_embedding` vector used to compute a workflow hint for the single-pass fallback path:

```bash
mix crm.embed_registry           # embed rows where hint_embedding IS NULL
mix crm.embed_registry --force   # re-embed all active rows
```

**CPU-only:** cosine similarity is computed in-process via Nx + EXLA configured with `platform: :host`. No GPU required.

### Multi-tenancy

```mermaid
graph TB
    subgraph global_registry
        T[tenants] --- UM[user_mappings]
        T --- MR[module_registry]
        T --- TWO[tenant_workflow_overrides]
        T --- RE[registry_examples]
        T --- RT[routing_thresholds]
        T --- RS[routing_signals]
    end
    subgraph customer_acme
        C1[contacts] --- E1[execution_logs]
        T1[todos] --- E1
        E1 --- EA1[execution_attachments]
    end
    subgraph customer_bigcorp
        C2[contacts] --- E2[execution_logs]
        T2[todos] --- E2
        E2 --- EA2[execution_attachments]
    end
    UM -->|user_id maps to| T
    T -->|schema_name| customer_acme
    T -->|schema_name| customer_bigcorp
```

Each tenant gets an isolated Postgres schema (`customer_<tenant_id>`) with its own `contacts`, `todos`, and `execution_logs` tables. The `global_registry` schema holds shared data: `tenants`, `user_mappings`, `module_registry`, `tenant_workflow_overrides`, `registry_examples`, `routing_thresholds`, and `routing_signals`.

`tenants` stores an optional `admin_email` for business-data export notifications, plus optional `webhook_url` and `webhook_secret` for outbound integrations. `user_mappings` stores an optional `user_email` for GDPR personal-data export delivery.

### Per-tenant workflow access control

By default every workflow is available to every tenant. `tenant_workflow_overrides` gates access at the `workflow_name` level (`"contacts"`, `"todos"`, `"data"`).

**How gating works (two layers):**

1. **Prompt layer** — `ClassifyIntent` calls `RegistryCache.for_tenant(tenant_id)` instead of `RegistryCache.all()`. Disabled workflows are invisible to the LLM — it cannot propose an action it has never seen.
2. **Dispatch layer** — `DispatchModule` checks `SubscriptionCache` before routing. Any step whose workflow is disabled returns `action: "unauthorized"` regardless of what the LLM said.

The `SubscriptionCache` GenServer loads all overrides from `global_registry.tenant_workflow_overrides` at boot into an ETS table (direct reads, no GenServer roundtrip). Updates via the admin API write to both Postgres and ETS atomically — effective immediately across all active connections, no reconnect needed.

**Manage via the admin API:**

```bash
# Disable a workflow for a tenant
curl -X PUT http://localhost:4000/api/admin/subscriptions \
  -H "Authorization: bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme","workflow_name":"data","enabled":false}'

# Re-enable
curl -X PUT http://localhost:4000/api/admin/subscriptions \
  -H "Authorization: bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme","workflow_name":"data","enabled":true}'
```

The endpoint is the natural hook for a Stripe entitlement webhook: receive the event, call `PUT /api/admin/subscriptions` with the relevant `tenant_id` and `workflow_name`.

### 2-step mutation confirmation

```mermaid
sequenceDiagram
    participant U as User
    participant A as API/Telegram
    participant R as Reactor
    participant DB as Postgres

    U->>A: "supprime Marie Dupont"
    A->>R: MasterIngest pipeline
    R->>DB: Find matching contact
    R->>DB: Store pending_id + proposed_params
    R-->>A: {action: "pending", pending_id: "uuid"}
    A-->>U: "Confirmez-vous la suppression?" [Confirm] [Reject]

    U->>A: Confirm (pending_id, "confirm")
    A->>DB: Execute mutation
    A->>DB: Update log: status=completed
    A-->>U: "Contact supprime."
```

Mutations (update, delete) return a `pending_id`. The user must confirm or reject via:

- **HTTP**: `POST /api/crm/confirm` with `pending_id` and `decision`
- **Telegram**: inline keyboard buttons (Confirm / Reject)

Unconfirmed mutations can be auto-rejected by the `PendingTimeoutWorker`.

### Webhook output

After every completed workflow (action not in `pending`, `clarify`, `unauthorized`), the system can optionally POST the result to the tenant's configured webhook URL. This turns the runner into an integration layer between natural language and enterprise systems (ERP, CRM, HRIS).

```bash
# Configure a webhook for a tenant
curl -X PUT http://localhost:4000/api/admin/webhook \
  -H "Authorization: bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme","webhook_url":"https://your-system.com/webhook"}'

# Retrieve the HMAC secret (generated on first webhook setup)
curl http://localhost:4000/api/admin/webhook_secret?tenant_id=acme \
  -H "Authorization: bearer $ADMIN_TOKEN"
```

Payloads are signed with HMAC-SHA256 (`x-crm-signature: sha256=...`). The `WebhookWorker` retries up to 5 times with Oban exponential backoff.

### Conversation context

Text-only requests inject the last 3 exchanges (5-minute TTL) into the Pass 2 prompt for pronoun and reference resolution. For example, after "cherche Marie Dupont", a follow-up "supprime-la" correctly resolves "la" to Marie Dupont.

The `ConversationCache` is an ETS table (no GenServer) keyed by `user_id`. Entries are pruned on read/write by TTL and max pair count. File uploads are self-contained and bypass conversation context.

### Automated example growth

The `ExampleReviewWorker` runs daily (5:30 AM) and uses `mistral-large-latest` as an LLM judge to review routing mismatches from the last 24 hours. When Pass 1 and Pass 2 disagree on the workflow, the judge evaluates whether the signal represents a valid new example. Confirmed examples are embedded via Ollama and inserted into `registry_examples`, growing the cosine-routing bank automatically. Capped at 20 new examples per run.

### File cleanup

The `FileCleanupWorker` runs daily (3:30 AM, after `RetentionWorker`) and deletes stored files linked to `execution_logs` older than 180 days. It removes both the physical files from storage and the `execution_attachment` DB records.

## Running

### Prerequisites

- Docker and Docker Compose
- Elixir 1.20+ / OTP 29 (for local development and tests)
- A Mistral API key
- (Optional) Ollama running on the host with `qwen2.5:7b` (LLM fallback) and `mxbai-embed-large` (embeddings)

### Start the stack

```bash
cp .env.example .env   # edit with your API keys
docker compose up -d
docker compose run --rm app /app/bin/migrate
docker compose run --rm app /app/bin/embed_examples   # seed routing examples (requires Ollama)
```

Services:

| Service | Port | Purpose |
|---------|------|---------|
| **app** | `localhost:4000` | Phoenix API + metrics |
| **postgres** | `localhost:5432` | Multi-tenant database (pgvector/pg18) |
| **whisper** | `localhost:8000` | Speech-to-text (faster-whisper) |
| **prometheus** | `localhost:9090` | Metrics scraper |
| **grafana** | `localhost:3000` | Dashboards (admin/admin) |

### Provision a tenant and add users

A **tenant** is a company. Each tenant gets an isolated database schema. **Users** are mapped to a tenant by their identifier (Telegram chat ID or an arbitrary string for HTTP).

```bash
# Create a tenant with its first user
curl -X POST http://localhost:4000/api/admin/provision \
  -H "Authorization: bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme","company_name":"Acme Corp","telegram_chat_id":"7363939976"}'
```

The `telegram_chat_id` becomes the user identifier. Find yours by messaging [@userinfobot](https://t.me/userinfobot) on Telegram.

To add more users to the same tenant, insert into `global_registry.user_mappings`:

```bash
docker compose exec postgres psql -U postgres_admin -d crm_reactor_prod -c \
  "INSERT INTO global_registry.user_mappings (user_identifier, tenant_id) VALUES ('ANOTHER_CHAT_ID', 'acme');"
```

For HTTP-only users (no Telegram), use any stable identifier as `user_id`:

```bash
docker compose exec postgres psql -U postgres_admin -d crm_reactor_prod -c \
  "INSERT INTO global_registry.user_mappings (user_identifier, tenant_id) VALUES ('api-user-1', 'acme');"
```

Multiple users can belong to the same tenant -- they all share the same contacts, todos, and execution logs.

### Deactivate / reactivate a tenant

```bash
# Deactivate (all users locked out)
curl -X POST http://localhost:4000/api/admin/toggle \
  -H "Authorization: bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme","active":false}'

# Reactivate
curl -X POST http://localhost:4000/api/admin/toggle \
  -H "Authorization: bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme","active":true}'
```

### Use the CRM

```bash
# Search contacts
curl -X POST http://localhost:4000/api/crm \
  -H "Content-Type: application/json" \
  -d '{"user_id":"YOUR_CHAT_ID","text":"cherche Marie Dupont"}'

# Confirm a mutation
curl -X POST http://localhost:4000/api/crm/confirm \
  -H "Content-Type: application/json" \
  -d '{"pending_id":"<uuid>","decision":"confirm"}'
```

## Tests

Three test tiers:

```bash
# Fast mocked tests (no API calls, ~3s)
mix test

# Full suite including real Mistral API
MISTRAL_API_KEY=... mix test --include external

# Only external tests
MISTRAL_API_KEY=... mix test --only external

# Only NL2SQL tests (multi-result, date-relative queries)
MISTRAL_API_KEY=... mix test --only external test/crm_reactor/nl2sql_test.exs
```

### Test structure

| File | What it tests | API calls? |
|------|---------------|------------|
| `test/crm_reactor/reactors/master_ingest_test.exs` | Full Reactor pipeline with mock classifier | No |
| `test/crm_reactor_web/controllers/crm_controller_test.exs` | HTTP API, 2-step mutations, auth | No |
| `test/crm_reactor_web/controllers/admin_controller_test.exs` | Admin provisioning, tenant toggle | No |
| `test/crm_reactor/tenants/provisioner_test.exs` | Schema creation, cleanup | No |
| `test/crm_reactor/error_recovery_test.exs` | Stuck logs, idempotent retries, error marking | No |
| `test/crm_reactor/gdpr_test.exs` | Data export, erasure, contact deletion, encryption | No |
| `test/crm_reactor/workers/ingest_worker_test.exs` | Oban job execution, Telegram delivery, failure logging | No |
| `test/crm_reactor/workers/pending_timeout_worker_test.exs` | Auto-rejection of expired mutations | No |
| `test/crm_reactor/workers/retention_worker_test.exs` | Log anonymization cron job | No |
| `test/crm_reactor/workers/routing_signal_worker_test.exs` | Routing analytics persistence | No |
| `test/crm_reactor/workers/threshold_calibration_worker_test.exs` | Threshold recalibration formula and cache reload | No |
| `test/crm_reactor/emails/data_export_email_test.exs` | Usage report email delivery, inline fallback | No |
| `test/crm_reactor/emails/gdpr_export_email_test.exs` | GDPR personal data email with JSON attachment | No |
| `test/crm_reactor/ai/examples_cache_test.exs` | ETS cache load/reload for routing examples | No |
| `test/crm_reactor/ai/threshold_cache_test.exs` | ETS cache load/reload for confidence thresholds | No |
| `test/crm_reactor/ai/similarity_test.exs` | Cosine similarity: top_workflow and top_n_workflows | No |
| `test/crm_reactor/workers/file_cleanup_worker_test.exs` | File retention: delete expired, preserve recent | No |
| `test/crm_reactor/workers/example_review_worker_test.exs` | LLM-judge review: approve/reject, HTTP errors, malformed JSON | No |
| `test/crm_reactor/reactors/modules/mutations_isolation_test.exs` | Cross-tenant mutation isolation | No |
| `test/mix/tasks/crm_embed_examples_test.exs` | Example seeding idempotency and --force flag | No |
| `test/crm_reactor/ai/classifier_test.exs` | Real Mistral classification accuracy + classify_workflow/3 | Yes |
| `test/crm_reactor/e2e_test.exs` | Full pipeline with real Mistral (mirrors bash smoke tests) | Yes |
| `test/crm_reactor/nl2sql_test.exs` | NL2SQL: multi-result, company filter, date-relative | Yes |

### Static analysis

```bash
mix credo --strict
mix dialyzer          # first run builds PLT (~2 min)
```

## Failure behavior

### LLM failures

| Failure | Behavior |
|---------|----------|
| Pass 1 (mistral-small) fails / times out | Falls back to single-pass with top cosine hint. Logged as warning. |
| Embedder unavailable | Cosine hints = `[]`. Pass 1 runs without hints. |
| Mistral Small returns `workflow: "none"` | Escalates to Mistral Large. If Large also fails, falls back to Ollama. |
| Mistral API down / 5xx / timeout | Auto-fallback to Ollama (host GPU). Logged as warning. |
| Ollama also down | Reactor step returns `{:error, ...}`. HTTP gets 500. Telegram user gets no reply. Oban retries up to 3 times. |
| Mistral returns unparseable JSON | `Jason.decode/1` returns `{:error, ...}`, propagated as step error. No exception raised. |
| NL2SQL filter validation fails | Falls back to deterministic query with warning log. User still gets a result. |
| NL2SQL returns unknown column | Column silently skipped (logged as warning), query runs without that filter. |

### Infrastructure failures

| Failure | Behavior |
|---------|----------|
| Postgres down | App healthcheck fails. Oban jobs queue in memory briefly, crash after timeout. Docker restarts app. |
| Whisper down | Voice transcription fails. Reactor step errors. Text messages unaffected. |
| App crash | OTP supervisor restarts. Oban jobs survive in Postgres -- replayed on restart. |
| Oban job fails | Retried up to 3 times (`max_attempts: 3`) with exponential backoff. After 3 failures, job moves to `discarded`. |
| ExamplesCache/ThresholdCache DB error on reload | Stale ETS data retained. Debug log emitted. Cache continues serving previous values. |

### Request-level errors

| Error | HTTP response | Telegram response |
|-------|---------------|-------------------|
| Unknown user | 403 `{"error": "Unknown user"}` | No reply (user not in system) |
| Deactivated tenant | 403 `{"error": "Unknown user"}` | No reply |
| Pending mutation not found | 404 `{"error": "Pending action not found"}` | "Action expiree ou introuvable." |
| Invalid admin token | 401 `{"error": "Unauthorized"}` | N/A |
| Workflow not in tenant's subscription | 200 `{"action": "unauthorized", "output": "..."}` | Reply in chat |
| Invalid confirm decision | 400 `{"error": "Invalid decision"}` | N/A |
| Internal error | 500 `{"error": "..."}` | No reply (Oban may retry) |

## Telegram setup

### 1. Create a bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot`, follow the prompts
3. Copy the bot token

### 2. Configure environment

Add to your `.env`:

```env
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
TELEGRAM_SECRET_TOKEN=a-random-secret-you-choose
```

### 3. Expose your webhook

The app needs to be reachable from Telegram's servers. For local development, use a tunnel:

```bash
# Using localtunnel
npx localtunnel --port 4000 --subdomain your-subdomain

# Or ngrok
ngrok http 4000
```

### 4. Register the webhook

```bash
WEBHOOK_URL="https://your-subdomain.loca.lt"  # or your ngrok URL
BOT_TOKEN="your-bot-token"
SECRET="your-secret-token"

curl -X POST "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" \
  -d "url=${WEBHOOK_URL}/webhook/telegram" \
  -d "secret_token=${SECRET}" \
  -d 'allowed_updates=["message","callback_query"]'
```

### 5. Map your Telegram user to a tenant

Your chat ID is the `telegram_chat_id` you used when provisioning. Find your chat ID by messaging [@userinfobot](https://t.me/userinfobot).

```bash
curl -X POST http://localhost:4000/api/admin/provision \
  -H "Authorization: bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"mycompany","company_name":"My Company","telegram_chat_id":"YOUR_CHAT_ID"}'
```

### 6. Test

Send a message to your bot: "cherche Marie" -- you should get a response.

For voice messages, ensure the Whisper container is running (`docker compose up -d whisper`).

## Observability

### Prometheus metrics

Exposed at `GET /metrics` -- scraped by Prometheus every 10s.

Includes: BEAM (memory, schedulers, processes), Phoenix (request duration, status codes), Ecto (query times, pool), Oban (job throughput, queue depth, failures).

### Grafana dashboards

Pre-provisioned at `localhost:3000` (admin/admin):

- **AI** -- classification latency (p50/p95/p99), model distribution, Mistral-Ollama fallback rate, NL2SQL latency, NL2SQL-deterministic fallback rate, prompt injection attempts
- **Application** -- uptime, running apps
- **BEAM** -- memory, schedulers, GC, ETS, processes
- **Phoenix** -- request duration, response size, status codes
- **Ecto** -- query times, pool checkout, queue times
- **Oban** -- job throughput, queue depth, execution time, failures

## Project structure

```
lib/
  crm_reactor/
    ai/
      classifier.ex          # Mistral intent classification: Pass 1 (mistral-small) + Pass 2 (mistral-small→large→Ollama)
      classifier_behaviour.ex # Behaviour: classify/2, classify/3, classify/4, classify_with_file/4, classify_workflow/3
      conversation_cache.ex  # ETS table: last 3 exchanges per user (5-min TTL, pronoun resolution)
      embedder.ex            # Text → 1024-dim vector via Ollama mxbai-embed-large
      embedder_behaviour.ex  # Behaviour for test mocking
      example_seeder.ex      # Upserts seed corpus from priv/ai/seed_corpus.json + embeds via Ollama
      examples_cache.ex      # ETS cache for registry_examples (Pass 1 cosine hints)
      input_guard.ex         # Prompt injection detection
      model_pricing.ex       # Compile-time pricing config from priv/ai/model_pricing.json
      prompts.ex             # Prompt builder: master prompt, vision prompt, pass1 prompt (with context injection)
      query_builder.ex       # NL2SQL: structured filters -> Ecto queries
      registry_cache.ex      # ETS cache for global module registry
      routing_signal.ex      # Schema: per-request routing analytics (+ reviewed field)
      routing_threshold.ex   # Schema: per-workflow confidence thresholds
      similarity.ex          # Nx cosine similarity: top_workflow/2 and top_n_workflows/3
      subscription_cache.ex  # ETS cache for per-tenant workflow overrides
      telemetry.ex           # AI-specific telemetry events
      threshold_cache.ex     # ETS cache for routing_thresholds (default 0.70)
      whisper.ex             # Voice transcription via Whisper API
    emails/
      data_export_email.ex   # 30-day usage report email builder
      gdpr_export_email.ex   # GDPR personal data export email builder (Art. 20)
    gdpr/
      data_subject.ex        # Right to erasure + data export (+ email delivery)
    mailer.ex                # Swoosh mailer (SMTP / API delivery)
    crm/
      contact.ex             # Ecto schema (per-tenant)
      todo.ex                # Ecto schema (per-tenant)
      execution_log.ex       # Audit trail (per-tenant)
      execution_attachment.ex # File attachment records (per-tenant, FK → execution_logs)
    reactors/
      master_ingest.ex       # Main Reactor pipeline (DAG)
      steps/                 # Reactor step implementations
      modules/
        contacts.ex          # Contacts CRUD + NL2SQL search
        todos.ex             # Todos CRUD + NL2SQL list
        data_export.ex       # Usage/cost report (email delivery when admin_email set)
        help.ex              # Dynamic help from registry
        mutations.ex         # 2-step confirm/reject
    tenants/
      provisioner.ex              # Schema creation, teardown, set_webhook/2
      tenant.ex                   # Global registry schema (+ webhook_url, webhook_secret)
      tenant_cache.ex             # ETS cache for tenant webhook config
      user_mapping.ex             # User -> tenant mapping
      module_registry.ex          # Available workflow modules (+ hint_embedding)
      registry_example.ex         # Workflow example phrases for Pass 1 cosine routing
      tenant_workflow_override.ex # Per-tenant workflow access overrides
    telegram.ex              # Send messages + inline keyboards
    telegram/handler.ex      # Telegex webhook handler
    storage.ex               # Storage behaviour (5MB guard)
    storage/
      local.ex               # Filesystem impl: priv/uploads/{tenant}/{uuid}-{filename}
    workers/
      example_review_worker.ex        # Oban cron (daily 5:30AM): LLM-judge review of routing mismatches
      file_cleanup_worker.ex          # Oban cron (daily 3:30AM): delete expired stored files
      ingest_worker.ex                # Oban: async Reactor execution
      pending_timeout_worker.ex       # Oban: auto-reject expired mutations
      retention_worker.ex             # Oban cron (daily 3AM): anonymize old logs (GDPR)
      routing_signal_worker.ex        # Oban: persist routing analytics (fire-and-forget)
      threshold_calibration_worker.ex # Oban cron (weekly Sun 4AM): recalibrate confidence thresholds
      webhook_worker.ex               # Oban: POST result to tenant webhook (HMAC-signed, 5 retries)
    encrypted.ex             # Cloak encrypted + HMAC types
    vault.ex                 # Cloak AES-GCM vault
    prom_ex.ex               # PromEx metrics configuration
  mix/tasks/
    crm.embed_examples.ex  # Seed from priv/ai/seed_corpus.json + embed via Ollama
    crm.embed_registry.ex  # Populate hint_embedding in module_registry via Ollama
    prom_ex/ai_plugin.ex     # Custom AI metrics plugin
  release.ex               # Release tasks: migrate, embed_examples
  crm_reactor_web/
    router.ex                # API routes + /metrics
    controllers/
      crm_controller.ex      # POST /api/crm, /api/crm/confirm
      admin_controller.ex    # POST /api/admin/provision, /toggle; PUT /api/admin/subscriptions, /webhook
      webhook_controller.ex  # POST /webhook/telegram
      health_controller.ex   # GET /api/health
      metrics_controller.ex  # GET /metrics
    live/
      chat_live.ex           # LiveView chat UI with file upload support
priv/
  ai/
    model_pricing.json       # Per-model pricing and role config (compile-time)
    seed_corpus.json         # 43 French example phrases across 4 workflows
```

## Adding a new workflow

The system is designed so that adding a new domain (e.g. `appointments`, `invoices`) requires minimal code changes. Most of the system is driven by the `global_registry.module_registry` table.

### What is fully dynamic (DB-driven, zero code changes)

- **System prompt** — `Repo.all(ModuleRegistry)` runs on every request. Adding rows to the table is immediately reflected in what the LLM is told it can do.
- **Param extraction** — `params_schema` per action (required/optional fields) is rendered into the prompt. The LLM learns what to extract from the schema alone.
- **Date resolution, routing_path** — driven by the global prompt instructions, not per-workflow code.
- **Help response** — `Modules.Help` reads the registry at runtime; new workflows appear automatically.

### What requires code changes

**1. A new module file**

Create `lib/crm_reactor/reactors/modules/appointments.ex` implementing `execute/1` pattern-matched on each action:

```elixir
defmodule CrmReactor.Reactors.Modules.Appointments do
  def execute(%{action: "create", params: params, tenant_schema: schema}) do
    # ...
  end

  def execute(%{action: "list", params: params, tenant_schema: schema}) do
    # ...
  end

  def execute(%{action: action}) do
    {:ok, %{output: "Action non supportée : #{action}", action: action}}
  end
end
```

**2. One line in `@module_map`** — `lib/crm_reactor/reactors/steps/dispatch_module.ex`:

```elixir
@module_map %{
  "contacts"     => Modules.Contacts,
  "todos"        => Modules.Todos,
  "data"         => Modules.DataExport,
  "help"         => Modules.Help,
  "appointments" => Modules.Appointments   # ← add this
}
```

This is the **only hardcoded piece** — intentionally so. It maps workflow names to Elixir modules at compile time, giving full pattern-match safety.

**3. DB rows in `global_registry.module_registry`**

```sql
INSERT INTO global_registry.module_registry
  (workflow_name, action, params_schema, prompt_hint)
VALUES
  ('appointments', 'create',
   '{"required":["subject","date"],"optional":["contact_name","duration_min"]}',
   'crée, planifie un rendez-vous'),
  ('appointments', 'list',
   '{"optional":["due_before","contact_name"]}',
   'liste, affiche les rendez-vous'),
  ('appointments', 'delete',
   '{"required":["subject"],"optional":["date"]}',
   'supprime, annule un rendez-vous');
```

**4. Add example phrases to `registry_examples`**

Add French-language example phrases for Pass 1 cosine routing to `priv/ai/seed_corpus.json`:

```json
{"workflow": "appointments", "text": "Planifie un rendez-vous avec Marie vendredi"},
{"workflow": "appointments", "text": "Ajoute un meeting avec Jean-Pierre la semaine prochaine"},
{"workflow": "appointments", "text": "Annule mon rendez-vous de lundi"}
```

Then run:

```bash
mix crm.embed_examples
```

**5. Populate registry-level embeddings**

```bash
mix crm.embed_registry
```

This reads each row's `prompt_hint` text and writes its 1024-dim vector to `hint_embedding`. Run once after inserting rows; re-run with `--force` after editing `prompt_hint`. Requires Ollama running with `mxbai-embed-large`.

**6. A migration for the tenant schema** (if you need new tables)

Add an Ecto migration that creates the new tables inside each tenant schema (using `prefix: schema_name` in Repo calls, same pattern as `contacts` and `todos`).

### Summary

| Step | Location | Required? |
|------|----------|-----------|
| New module file with `execute/1` clauses | `lib/crm_reactor/reactors/modules/` | Yes |
| One line in `@module_map` | `dispatch_module.ex` | Yes |
| DB rows in `module_registry` | SQL / migration | Yes |
| Example phrases in `priv/ai/seed_corpus.json` + `mix crm.embed_examples` | JSON + Mix task | Yes (for Pass 1 routing) |
| Registry embeddings: `mix crm.embed_registry` | Mix task | Yes (for fallback routing hint) |
| Schema migration for new tables | `priv/repo/migrations/` | If new tables needed |
| Gate per tenant via `PUT /api/admin/subscriptions` | Admin API | If subscription-gated |

New workflows are enabled for all tenants by default. No `tenant_workflow_overrides` row is needed unless you want to restrict access.

## GDPR and ISO 42001 compliance

### Personal data inventory

| Data | Location | Category |
|------|----------|----------|
| `first_name`, `last_name` | `contacts` (per-tenant) | Personal data |
| `email`, `phone` | `contacts` (per-tenant) | Personal data, **encrypted at rest** (Cloak AES-GCM) |
| `user_identifier` (Telegram chat ID) | `global_registry.user_mappings` | Pseudonymous identifier |
| `raw_input` (user message) | `execution_logs` (per-tenant) | May contain personal data |
| `output` (CRM response) | `execution_logs` (per-tenant) | Contains personal data |
| `raw_input` (routing analytics) | `global_registry.routing_signals` | May contain personal data |
| Voice messages | Transient (Whisper) | Biometric data (Art. 9) |

### GDPR controls implemented

| Art. | Requirement | Implementation | Status |
|------|-------------|----------------|--------|
| 15, 20 | Right of access / data portability | `GET /api/admin/subjects/:id/export` -- returns all data as JSON | Done |
| 20 | Data portability via email | `POST /api/admin/subjects/:id/email-export` -- sends personal data as JSON email attachment | Done |
| 17 | Right to erasure | `DELETE /api/admin/subjects/:id` -- redacts logs, removes mapping | Done |
| 17 | Contact erasure | `DELETE /api/admin/contacts/:schema/:id` -- deletes contact, redacts matching logs | Done |
| 25 | Data minimization | `RetentionWorker` anonymizes execution_logs older than 180 days (Oban cron, 3am daily). `FileCleanupWorker` deletes stored files older than 180 days (3:30am daily). | Done |
| 32 | Encryption at rest | `email` and `phone` encrypted via Cloak AES-GCM, searchable via HMAC hashes | Done |
| 32 | Rate limiting | Hammer, 30 req/min per user on CRM and webhook endpoints | Done |

### GDPR items remaining (administrative, not code)

| Art. | Requirement | Status |
|------|-------------|--------|
| 6 | Document lawful basis for processing | Needed |
| 28 | Data Processing Agreement with Mistral AI | Needed |
| 30 | Record of Processing Activities (ROPA) | Needed |
| 33, 34 | Breach notification procedure | Needed |
| 9 | Explicit consent for voice messages (biometric) | Needed |

Note: `routing_signals.raw_input` stores user messages. If you implement a right-to-erasure flow, include this table alongside `execution_logs`.

### ISO 42001 controls implemented

| Clause | Requirement | Implementation | Status |
|--------|-------------|----------------|--------|
| A.4.5 | AI transparency | API responses include `ai_assisted: true` and `model` field | Done |
| A.6.2 | Prompt injection protection | `InputGuard` blocks 14 attack patterns before LLM call, logs attempts | Done |
| A.8.2 | AI decision logging | `execution_logs` records routing_path, token usage, action per request | Done |
| A.8.2 | AI routing analytics | `routing_signals` records cosine hint, Pass 1 result, Pass 2 result, and agreement per request | Done |
| 9.1 | AI monitoring | Custom PromEx plugin: classification latency, fallback rate, NL2SQL rejection rate, injection attempts | Done |
| A.4.6 | Human oversight | 2-step confirmation for all mutations (AI proposes, human decides) | Done |

### ISO 42001 items remaining (administrative, not code)

| Clause | Requirement | Status |
|--------|-------------|--------|
| 6.1 | AI risk assessment document | Needed |
| A.4.4 | AI model card / system description | Needed |
| A.7.3 | Verify Mistral data processing terms (training opt-out) | Needed |
| 7.2 | AI competence requirements for operators | Needed |

### Remaining code-level hardening

| # | Item | Priority |
|---|------|----------|
| 10 | Voice consent flow -- bot asks before transcribing | Medium |
| 12 | CRM endpoint authentication -- currently relies on user_id lookup only | Medium |

### Model pricing

LLM cost tracking is driven by `priv/ai/model_pricing.json` (loaded at compile time via `CrmReactor.AI.ModelPricing`). Each model entry specifies pricing per million tokens and a role (`primary`, `escalation`, `pass1`, `vision`, `review`, `fallback`). The `DataExport` module uses this config to estimate monthly costs in usage reports.

## Compared to the n8n version

| | n8n | CRM Reactor |
|---|---|---|
| Runtime | n8n + Redis + 7 containers | Single BEAM app + Postgres |
| Memory | ~1.8 GB | ~1.0 GB |
| Workflow engine | n8n visual workflows | Reactor (parallel step DAG) |
| Job queue | Redis | Oban (Postgres-backed) |
| Tests | Bash curl script (22 tests) | ExUnit (341+ tests: mocked + external) |
| Observability | Prometheus + custom Grafana | PromEx (auto-generated dashboards) |
| Fault tolerance | Docker restart | OTP supervision + Oban retries |
