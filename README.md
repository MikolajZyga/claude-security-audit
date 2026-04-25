# claude-security-audit

A reusable [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) that scans your codebase for leaked secrets, fixes them safely, and installs persistent security rules so every Claude session enforces them.

Built specifically against the kinds of mistakes AI assistants make while coding: hardcoded API keys, secrets behind public env prefixes, `process.env.X = "literal"` shortcuts, debug `console.log`s of tokens, committed `.env` files.

---

## What it does

- **Audit** — scans your repo for leaked secrets and AI-coding security issues. Provider-specific patterns for OpenAI, Anthropic, Stripe, AWS, GitHub, Google, Slack, SendGrid, Twilio, and more.
- **Fix** — replaces hardcoded values with proper env var references without touching app logic. Moves real values to `.env.local`, adds placeholders to `.env.example`.
- **Enforce** — installs a short security section into your project's `CLAUDE.md` so every Claude Code session reads the same rules. Adds a pre-commit hook that blocks commits containing detected secrets.

Designed to stay token-light: the always-loaded `CLAUDE.md` snippet is ~120 tokens, the audit script returns one compact line per finding, and detailed playbooks are only loaded when actually fixing something.

---

## Install

### User-level (across all your projects)

```bash
mkdir -p ~/.claude/skills
git clone https://github.com/<your-username>/claude-security-audit.git ~/.claude/skills/security-audit
```

### Project-level (single repo only)

```bash
mkdir -p .claude/skills
git clone https://github.com/<your-username>/claude-security-audit.git .claude/skills/security-audit
```

That's it. Claude Code will pick the skill up automatically. Next time you open a project and ask Claude to audit, scan, or check security, it'll trigger.

---

## Usage

In any Claude Code session, just say what you want:

> "audit this repo for secrets"
> "check security before I push"
> "scan for leaked API keys"
> "set up security rules for this project"

Claude will run the skill. On first use in a project, it installs the rules and pre-commit hook (one prompt). After that, the audit just runs.

You can also run the scripts directly without Claude:

```bash
# scan
bash ~/.claude/skills/security-audit/scripts/audit.sh

# install rules into the current project
bash ~/.claude/skills/security-audit/scripts/install.sh
```

---

## Sample output

The audit script returns a compact list of findings:

```
== Security Audit ==
Root: /Users/me/projects/my-app
Findings: 2 CRITICAL, 1 HIGH, 1 MEDIUM, 0 LOW

== CRITICAL ==
CRITICAL | .env | tracked_env_file | <env file is tracked>
CRITICAL | src/lib/openai.ts:14 | openai_api_key | sk-p****jk

== HIGH ==
HIGH | src/db.ts:8 | db_url_with_creds | <credentialed db url>

== MEDIUM ==
MEDIUM | src/auth.ts:42 | logging_secret_like_var | <log of secret-named var>

Next: open references/fix-playbook.md and fix by rule_id.
```

After Claude applies fixes, it prints a structured **Fixes Report** showing one entry per finding with status (`[✓]` fixed, `[⊘]` confirmed false-positive, `[⚠]` needs user action, `[✗]` skipped), a verification section (re-audit + typecheck), and action items for things only you can do (like rotating leaked keys at the provider).

---

## What gets detected

| Severity | Examples |
|---|---|
| **CRITICAL** | OpenAI / Anthropic / Stripe live / AWS / GitHub PAT / Google / Slack / SendGrid / Twilio keys, `BEGIN PRIVATE KEY` blocks, tracked `.env` files, tracked service-account JSON |
| **HIGH** | `apiKey: "literal"` assignments, `process.env.X = "literal"`, `NEXT_PUBLIC_*_SECRET` shaped names, DB connection strings with embedded credentials |
| **MEDIUM** | `console.log(token)` patterns, hardcoded JWTs, missing `.gitignore` entries for `.env` |

The full list with detection patterns is in [`references/patterns.md`](references/patterns.md).

If `gitleaks` is on your `PATH` it's used as a second pass for higher coverage, but it's not required.

---

## Pre-commit hook

`install.sh` drops a hook at `.git/hooks/pre-commit`. It runs the audit only on staged files (fast) and blocks the commit if anything CRITICAL or HIGH is found. Bypass with `git commit --no-verify` if you need to.

If you already have a pre-commit hook, the installer detects it and skips — you'll see a message about manual merging.

---

## Persistent rules in CLAUDE.md

The installer appends a short, marked section to your project's `CLAUDE.md`:

```markdown
<!-- BEGIN security-audit rules — do not edit between markers -->
## Security rules (enforced every session)

- Never hardcode secrets, API keys, tokens, passwords, or DB URLs with credentials...
- Never put server-only secrets behind a public-prefixed env var...
- Never commit `.env*` files except `.env.example`...
- Never log, `console.log`, `print`, or echo a token, secret, password...
- Never paste a real secret into chat, commit messages, or comments...
- Before suggesting `git commit` or `git push`, ensure the security-audit skill has been run...
- If a secret was already pushed to a remote, the only real fix is to **rotate the key**...
<!-- END security-audit rules -->
```

This is loaded automatically by Claude Code in every session for that project. No new tokens after the first ~120.

---

## Frameworks supported (for the fix step)

The skill knows the env-var conventions for: Next.js (App + Pages router), Vite, Create React App, Expo, plain Node, Express / Fastify / Hono / NestJS, Firebase (web SDK and Admin SDK), Python / FastAPI, Rust, Go, Supabase. See [`references/frameworks.md`](references/frameworks.md).

The Firebase web SDK config (`apiKey`, `projectId`, etc.) is handled correctly — those values are public by design, so the skill flags them but the playbook tells Claude to confirm before "fixing" them.

---

## Compatibility

- **Shell**: portable bash, no GNU-isms. Tested on Linux. Should work on macOS (BSD utils); please open an issue if not.
- **Dependencies**: just `bash`, `awk`, `grep`, `git`. `gitleaks` is used if available, optional.
- **Claude Code**: tested with Claude 4.x. Skills format is stable across versions.

---

## Repo layout

```
claude-security-audit/
├── SKILL.md                          # the skill entry point
├── scripts/
│   ├── audit.sh                      # the scanner
│   ├── install.sh                    # per-project setup
│   └── pre-commit.sh                 # the git hook
├── references/                       # loaded by Claude only when fixing
│   ├── fix-playbook.md
│   ├── frameworks.md
│   └── patterns.md
└── templates/
    ├── CLAUDE-security.md            # the snippet appended to CLAUDE.md
    └── gitignore.additions
```

---

## Customizing

- **Add a detection rule**: edit `scripts/audit.sh`, find `scan_secret_patterns`, add an `awk match()` line. Add the rule_id to `references/fix-playbook.md` so Claude knows how to fix it.
- **Change CLAUDE.md rules**: edit `templates/CLAUDE-security.md`. Re-run `install.sh` in a project to update (the markers make the replacement clean).
- **Tighten or relax severities**: change the severity argument in the relevant `emit_find()` call in `audit.sh`.

---

## License

MIT. Use it, fork it, ship it.

---

## Why this exists

AI coding assistants are great at writing code that works and bad at writing code that's safe. They paste real keys into examples, swap a server secret into `NEXT_PUBLIC_*` to make an error go away, leave debug logs of tokens, and don't know that committing `.env` is forever. This skill closes those gaps with one install per project.
