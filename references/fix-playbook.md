# Fix Playbook

For each finding from `audit.sh`, look up the `rule_id` here and apply the listed fix. Do not improvise. If the rule is not listed, ask the user before proceeding.

## Universal fix shape (applies to most CRITICAL and HIGH "leaked literal" rules)

1. Read the literal value from the offending `file:line`.
2. Pick a stable env var name. Convention:
   - For framework-prefixed values that are **safe to expose to clients**, keep the prefix (`NEXT_PUBLIC_X`).
   - For everything else, no prefix. Server-only.
3. Append the value to `.env.local` (create if missing). One `KEY=VALUE` per line, no quotes unless the value contains whitespace or `#`.
4. Add a placeholder line `KEY=` (or `KEY=changeme`) to `.env.example`.
5. Replace the literal in the source file with the framework-correct env reference (see `frameworks.md`).
6. **Do not modify** any other line. No formatting passes, no import reordering, no "while we're here" cleanups.
7. Re-run `audit.sh`. If the project has `npm test`, `npm run typecheck`, `pnpm test`, or equivalent, run it once and report the exit code.

If the file was already committed to git history (`git log --all -- <file>` shows commits), tell the user the value must be rotated at the provider. History rewrite alone does not undo the leak.

---

## Per-rule details

### `anthropic_api_key`, `openai_api_key`, `openai_project_key` — CRITICAL
Universal fix shape. Env var names: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`. Never use a public prefix — these must stay server-side.

### `stripe_live_secret`, `stripe_restricted_live` — CRITICAL
Universal fix shape. Env var: `STRIPE_SECRET_KEY` (server-only). Note: `pk_live_*` (publishable) is intentionally public-safe; restricted/secret keys are not.

### `aws_access_key_id`, `aws_session_key_id` — CRITICAL
Do **not** just move to env vars. Tell the user: AWS keys belong in `~/.aws/credentials` (local dev) or IAM roles (deployed). Moving to `.env.local` is acceptable as a stopgap but flag it. Always paired with a secret access key — search the same file for the matching `aws_secret_access_key`.

### `github_pat_classic`, `github_pat_fine`, `github_app_token` — CRITICAL
Universal fix shape. Env var: `GITHUB_TOKEN`. After the fix, remind the user to revoke the leaked token at https://github.com/settings/tokens.

### `google_api_key` — CRITICAL
Universal fix shape. **But** for Firebase web SDK config, the API key is intentionally public — it identifies the project, not the user. If the file is `firebase.ts`, `firebase.js`, `firebaseConfig.*`, or similar, this is a **false positive**. Confirm by checking: is it inside a call to `initializeApp(...)` from `firebase/app`? If yes, leave it but add a code comment: `// Firebase web API key — public by design, not a secret`. See `frameworks.md` for the full Firebase-vs-admin rule.

### `slack_token`, `sendgrid_key`, `twilio_account_sid` — CRITICAL
Universal fix shape. Common env names: `SLACK_BOT_TOKEN`, `SENDGRID_API_KEY`, `TWILIO_ACCOUNT_SID`.

### `private_key_block` — CRITICAL
A `-----BEGIN PRIVATE KEY-----` block in source code is almost never correct. Move the entire block to `.env.local` as a single line with `\n` escaped, or move it to a file outside the repo and load via path env var (`PRIVATE_KEY_PATH=/path/to/key.pem`). Never commit a key file. After fix: revoke and regenerate the key at the provider.

### `tracked_env_file` — CRITICAL
The file is committed. Steps:
1. `git rm --cached <file>` (keeps the local file, removes from git tracking).
2. Confirm `.gitignore` has the right entry (re-run install.sh if not sure).
3. Tell the user: every secret that was ever in that file should be considered leaked and rotated.
4. Optional: scrub from history with `git filter-repo --path <file> --invert-paths` — destructive, requires force-push, only do this on user request.

### `tracked_service_account` — CRITICAL
Same as `tracked_env_file`. Plus: rotate the service account at the cloud provider (delete the JSON key, create a new one). For Firebase admin: Firebase console → Project settings → Service accounts → Generate new private key.

### `assigned_secret_literal` — HIGH
Variable name like `apiKey`, `secret`, `token`, etc. is being assigned a literal string. Universal fix shape. Pick the env var name based on the variable name (e.g. `apiKey = "..."` → `process.env.API_KEY`). If the literal looks like a placeholder (`"your-key-here"`, `"xxx"`, `"changeme"`), it's a false positive — leave it.

### `process_env_literal_assign` — HIGH
Code is doing `process.env.X = "actual-value"` — this is writing a secret into the process env at runtime, usually because the dev didn't know how to load it. Fix: remove that assignment line entirely, ensure `dotenv` (or framework equivalent) loads `.env.local`, and add the value there. For Next.js this is automatic. For plain Node, add `import 'dotenv/config'` at the top of the entry file (only if `dotenv` is already a dependency — if not, ask the user before adding).

### `public_prefix_on_secret_name` — HIGH
An env var with a public prefix has a name like `*_SECRET`, `*_PRIVATE`, `*_ADMIN`. Public-prefixed env vars are **bundled into the client**, which means the value is shipped to every browser. Two possible fixes:
- If the value really is public (rare with these names): rename the var to drop the misleading suffix.
- If the value is actually secret: remove the public prefix everywhere it's referenced (`NEXT_PUBLIC_X` → `X`), and move any usage to server-only code (API routes, server components, server actions). This may require a small refactor — confirm with the user before doing it.

### `logging_secret_like_var` — MEDIUM
A `console.log` / `print` includes a variable named `token`, `secret`, `password`, etc. Replace the call with either a redacted version (`console.log("token:", token ? "[set]" : "[missing]")`) or remove the log entirely. Don't just delete unrelated lines.

### `hardcoded_jwt` — MEDIUM
A JWT literal in source. Usually a copy-pasted test token. Universal fix shape if it's a real token. If the file is a test file (`*.test.*`, `*.spec.*`, `__tests__/`), confirm with the user — test fixtures sometimes intentionally embed expired tokens.

### `db_url_with_creds` — HIGH
A connection string like `postgres://user:pass@host/db` in code. Universal fix shape. Env var: `DATABASE_URL`. If the project uses Prisma, the convention is already `DATABASE_URL` — just point Prisma's `schema.prisma` at it (it usually already does).

### `gitignore_missing_env` — MEDIUM
`.gitignore` doesn't ignore `.env`. Run `install.sh` again, or manually append the lines from `templates/gitignore.additions`. Then verify: `git check-ignore .env` should output `.env`.

### `gitleaks_*` — CRITICAL (when gitleaks is installed)
gitleaks found something its built-in rules flagged. The rule_id after `gitleaks_` matches gitleaks' rule names — google it if you need detail. Apply the universal fix shape.

---

## When you should NOT auto-fix

- The finding is in a third-party library inside `node_modules/` or `vendor/`. Skip silently.
- The finding is in a markdown file inside `docs/`, `examples/`, or `README.md`, AND the literal is clearly a placeholder. Tell the user but don't change docs.
- The finding is in a test fixture and the value is clearly fake (e.g. `sk-test-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`). Confirm before touching.
- The user has previously declined to fix this specific finding in this session.
