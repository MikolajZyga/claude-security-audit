# Detection Patterns Reference

This is documentation for what `audit.sh` looks for. Useful when triaging a finding ("why did this match?") or considering a false positive.

## Severity meaning

- **CRITICAL** — almost certainly a real, exploitable secret. Block commits, fix immediately.
- **HIGH** — strongly secret-shaped. Likely real, occasionally a placeholder.
- **MEDIUM** — risky pattern but ambiguous. Worth fixing but not a hard block.
- **LOW** — informational, often style/hygiene.

## Provider-specific rules (CRITICAL)

These match the actual issued-key shape published by each provider, so false-positive rate is very low. A match is almost always the real thing.

| rule_id | Provider | Shape |
|---|---|---|
| `anthropic_api_key` | Anthropic | `sk-ant-api03-…` |
| `openai_api_key` | OpenAI | `sk-…` (32+ chars) |
| `openai_project_key` | OpenAI | `sk-proj-…` |
| `stripe_live_secret` | Stripe | `sk_live_…` |
| `stripe_restricted_live` | Stripe | `rk_live_…` |
| `aws_access_key_id` | AWS | `AKIA[A-Z0-9]{16}` |
| `aws_session_key_id` | AWS | `ASIA[A-Z0-9]{16}` (temporary) |
| `github_pat_classic` | GitHub | `ghp_…` |
| `github_pat_fine` | GitHub | `github_pat_…` |
| `github_app_token` | GitHub Apps | `ghs_…` |
| `slack_token` | Slack | `xoxb-`, `xoxp-`, `xoxa-`, `xoxr-`, `xoxs-` |
| `google_api_key` | Google | `AIza…` (35 chars) — **see Firebase note in `frameworks.md`** |
| `sendgrid_key` | SendGrid | `SG.<22>.<43>` |
| `twilio_account_sid` | Twilio | `AC<32 hex>` |
| `private_key_block` | Any PKI | `-----BEGIN … PRIVATE KEY-----` |

## Shape-based rules (HIGH)

These look at how the code is written, not at the value's provider format.

| rule_id | What triggers |
|---|---|
| `assigned_secret_literal` | A variable named `apiKey`, `secret`, `token`, `password`, etc. is being assigned a quoted literal of 12+ chars. Filtered against common placeholder words (`your-key`, `placeholder`, `xxx`, `changeme`, `dummy`, `test-key`). |
| `process_env_literal_assign` | Code is doing `process.env.X = "actual-string"`. This pattern usually means "I couldn't get dotenv working so I just hardcoded it", which is exactly the leak we're catching. |
| `public_prefix_on_secret_name` | An env var with a public prefix (`NEXT_PUBLIC_`, `VITE_`, etc.) **and** a secret-suggesting name component (`SECRET`, `PRIVATE`, `SERVICE_ACCOUNT`, `SERVICE_ROLE`, `ADMIN`, `SERVER_KEY`, `PASSWORD`, `PRIVATE_KEY`, `DATABASE_URL`, `DB_URL`, `WEBHOOK_SECRET`, `JWT_SECRET`, `ENCRYPTION_KEY`, `SIGNING_KEY`, `MASTER_KEY`, `REFRESH_TOKEN`). Tuned to skip legitimately-public vars like `NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN` or `NEXT_PUBLIC_POSTHOG_KEY`. |
| `db_url_with_creds` | A URL like `postgres://user:pass@host` (or mysql, mongodb, redis, amqp) appears in code. |
| `tracked_env_file` | A file named `.env`, `.env.local`, `.env.production`, etc. is tracked by git. |
| `tracked_service_account` | A file matching `*service-account*.json`, `*firebase-adminsdk*.json`, `*-credentials.json` is tracked by git. |

## Soft rules (MEDIUM)

| rule_id | What triggers |
|---|---|
| `logging_secret_like_var` | A `console.log`, `console.debug`, `print`, `println!`, etc. has `token`, `secret`, `password`, `api_key`, `auth` somewhere in the call's args. |
| `hardcoded_jwt` | A JWT-shaped string (`eyJ…eyJ….…`) appears in code. |
| `gitignore_missing_env` | `.gitignore` has no entry covering `.env*`. |

## False-positive zones

If you see a finding here, double-check before fixing:

- **Firebase web config** (`google_api_key` inside `initializeApp({...})`) — public by design, see `frameworks.md`.
- **Stripe publishable keys** (`pk_live_*`, `pk_test_*`) — these are **not** flagged by the audit, but if you see one in code, that's correct, they're meant to be public.
- **Test fixtures** (`*.test.*`, `*.spec.*`, `__tests__/`, `fixtures/`) — sometimes contain intentionally-fake-but-real-shaped values for unit tests. The audit doesn't auto-skip these; confirm with the user.
- **Documentation** (`README.md`, `docs/`) — placeholder examples are common. Audit may flag them; don't auto-rewrite docs.
- **Migration/seed files** with hashed/example values — confirm before touching.

## Custom rules

To add your own pattern, edit `scripts/audit.sh`, find `scan_secret_patterns`, and add an `awk` `match()` line following the existing shape. New rule_ids will flow through the playbook lookup automatically (you'll need to add a section in `fix-playbook.md` too).
