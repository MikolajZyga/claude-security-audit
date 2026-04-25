#!/usr/bin/env bash
# security-audit pre-commit hook
# Blocks commits that introduce hardcoded secrets or .env files.
# Bypass with: git commit --no-verify   (use only when you know what you're doing)

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SKILL_MARKER="$ROOT/.claude/.security-audit-installed"

# locate skill dir from marker (so the hook keeps working if skill is reinstalled elsewhere)
SKILL_DIR=""
if [ -f "$SKILL_MARKER" ]; then
  SKILL_DIR="$(awk -F': ' '/^skill_dir:/ {print $2}' "$SKILL_MARKER")"
fi

if [ -z "$SKILL_DIR" ] || [ ! -x "$SKILL_DIR/scripts/audit.sh" ]; then
  echo "[security-audit hook] skill not found — skipping. Reinstall with the skill's install.sh."
  exit 0
fi

# Only scan files staged for commit, in a temp checkout, to avoid scanning the whole tree on every commit.
STAGED="$(git diff --cached --name-only --diff-filter=ACMR)"
if [ -z "$STAGED" ]; then
  exit 0
fi

# Quick block: any staged .env file (non-example)?
echo "$STAGED" | while IFS= read -r f; do
  case "$f" in
    .env|.env.local|.env.development|.env.production|.env.staging|.env.test|*/\.env|*/\.env.local)
      echo "[security-audit] BLOCKED: refusing to commit env file: $f"
      echo "  Add to .gitignore and remove with: git rm --cached \"$f\""
      exit 1
      ;;
  esac
done || exit 1

# Run audit only on staged files
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t scaudit)"
trap 'rm -rf "$TMP"' EXIT

# Materialize staged content into TMP and scan that subset
echo "$STAGED" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$TMP/$(dirname "$f")"
  git show ":$f" > "$TMP/$f" 2>/dev/null || true
done

# Run the audit there
( cd "$TMP" && bash "$SKILL_DIR/scripts/audit.sh" ) > "$TMP/.audit.out" 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
  exit 0
fi

# If we got findings, surface CRITICAL/HIGH and block
if grep -qE '^(CRITICAL|HIGH) \|' "$TMP/.audit.out"; then
  echo "[security-audit] BLOCKED — possible secret in staged changes:"
  echo "----"
  grep -E '^(CRITICAL|HIGH) \|' "$TMP/.audit.out" | head -20
  echo "----"
  echo "Bypass once with: git commit --no-verify"
  echo "Recommended: ask Claude to run the security-audit skill to fix these."
  exit 1
fi

# Only MEDIUM/LOW — warn but allow
if grep -qE '^(MEDIUM|LOW) \|' "$TMP/.audit.out"; then
  echo "[security-audit] WARNINGS in staged changes (not blocking):"
  grep -E '^(MEDIUM|LOW) \|' "$TMP/.audit.out" | head -10
fi

exit 0
