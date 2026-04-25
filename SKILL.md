---
name: security-audit
description: Audit the codebase for leaked secrets, hardcoded API keys, exposed environment variables, and other AI-coding security issues, then fix them safely without breaking app functionality. Use whenever the user asks to scan, audit, check for secrets, harden a project, prepare to commit, prepare to push, or set up security rules. Use proactively before suggesting `git commit` or `git push` if the project has not been audited in the current session. Installs persistent rules into the project's CLAUDE.md so every future Claude session enforces secure handling of secrets, env vars, and logs.
---

# Security Audit

Three things this skill does:

1. **Audit** — scan codebase for leaked secrets and AI-coding mistakes
2. **Fix** — replace hardcoded secrets with env var references, never breaking functionality
3. **Enforce** — install rules into the project's `CLAUDE.md` so every session follows them

## Workflow

### A. First time in a project

If `.claude/.security-audit-installed` does not exist in the project root, run:

```bash
bash "${SKILL_DIR}/scripts/install.sh"
```

This appends a short security section to the project's `CLAUDE.md` (creating it if absent), updates `.gitignore`, drops a pre-commit hook, and writes the marker file. Tell the user what was added in one sentence.

### B. Run the audit

```bash
bash "${SKILL_DIR}/scripts/audit.sh"
```

Output is structured: `SEVERITY | file:line | rule_id | masked_match`. Exit code: `0` clean, `1` findings, `2` script error.

If `gitleaks` is on PATH the script uses it for higher-quality detection and falls back to built-in patterns otherwise. Don't suggest installing tools — just work with what's there.

### C. Triage and fix

For each finding, look up the rule_id in `references/fix-playbook.md` and apply the listed fix. Do **not** improvise. Default fix shape for hardcoded secrets:

1. Read the literal value from the offending line
2. Append `KEY=value` to `.env.local` (create if missing)
3. Add `KEY=` placeholder to `.env.example`
4. Replace the literal in code with the framework-correct env reference (see `references/frameworks.md`)
5. Move on — do not refactor unrelated code

Re-run audit. Then run the project's typecheck/test command if one exists in `package.json` or equivalent (`npm run typecheck`, `npm test`, `pnpm test`, etc.) to confirm nothing broke. If no test command exists, say so and stop.

### C2. Required output: Fixes Report

After all fixes are applied, **always** print a structured report in this exact shape — one entry per finding, no exceptions. This is how the user verifies what changed:

```
## Security Audit Report

### Initial findings
N CRITICAL, N HIGH, N MEDIUM, N LOW  (from audit.sh)

### Fixes applied
- [✓] <file:line> — <rule_id>
  - <one-line description of what was changed>
  - <any follow-up action listed in the playbook>
- [⊘] <file:line> — <rule_id> (confirmed false positive)
  - <why it was a false positive>
- [⚠] <file:line> — <rule_id> (requires user action — not auto-fixed)
  - <what you the user must do>
- [✗] <file:line> — <rule_id> (skipped at user request)

### Verification
- Re-audit: <N findings remaining / clean>
- Typecheck/tests: <command run, exit code, or "no test script found">

### Action items for you
- <bullets for things only the user can do — rotate keys, force-push history, etc.>
- (omit this section if nothing remains)
```

Status icons:
- `[✓]` — auto-fixed by the skill
- `[⊘]` — confirmed false positive, intentionally left in place (with a code comment if appropriate)
- `[⚠]` — partially handled or needs the user (e.g. `git rm --cached` done locally but secret still needs rotating at the provider)
- `[✗]` — skipped because the user said so, or because it's in vendored code

The report is the deliverable. If you fixed things but didn't print this report, the task is not done.

### D. If a secret was already committed to git history

Do not auto-fix. Tell the user clearly: the value must be **rotated at the provider** (regenerate the key) and optionally scrubbed from history with `git filter-repo` or BFG. Rotation is the real fix; history rewrite alone is not. Include this as an `Action items for you` bullet in the report.

## Hard rules

- **Never print real secret values** in chat output, summaries, commit messages, or any file other than `.env.local`. Refer to findings by `file:line` only.
- **Never delete code** — only replace literal values with env references.
- **Never modify** `.env`, `.env.local`, or any file matching `.env.*` other than creating/appending. Don't reformat them.
- **Never commit** `.env.local` or anything matching `.env*` except `.env.example`.
- If a fix would require changing how the app loads config (e.g. introducing `dotenv` where it's not used), stop and ask the user first.

## Reference files

Read these only when you actually need them — they don't belong in working context by default:

- `references/patterns.md` — every detection rule and what triggers it
- `references/fix-playbook.md` — exact fix steps per `rule_id`
- `references/frameworks.md` — Next.js / Vite / Firebase / Express / Python specifics for env access

## Note on token budget

This skill is designed to stay lightweight: the always-loaded `CLAUDE.md` snippet is ~120 tokens, this SKILL.md is ~500, and the reference files are only pulled in per-finding. The audit script returns compact structured output rather than full file contents.
