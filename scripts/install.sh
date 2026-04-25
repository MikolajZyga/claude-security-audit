#!/usr/bin/env bash
# install.sh — set up a project for the security-audit skill.
# Idempotent: safe to run multiple times.

set -u
LC_ALL=C

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "install: cannot cd to $ROOT" >&2; exit 2; }

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MARKER_DIR="$ROOT/.claude"
MARKER_FILE="$MARKER_DIR/.security-audit-installed"
mkdir -p "$MARKER_DIR"

CHANGES=()

# 1) CLAUDE.md rules ----------------------------------------------------------
SNIPPET_BEGIN="<!-- BEGIN security-audit rules — do not edit between markers -->"
SNIPPET_END="<!-- END security-audit rules -->"
SNIPPET_FILE="$SKILL_DIR/templates/CLAUDE-security.md"

if [ ! -f "$SNIPPET_FILE" ]; then
  echo "install: missing $SNIPPET_FILE" >&2
  exit 2
fi

if [ ! -f CLAUDE.md ]; then
  {
    echo "# Project notes for Claude"
    echo
    cat "$SNIPPET_FILE"
  } > CLAUDE.md
  CHANGES+=("created CLAUDE.md with security rules")
elif ! grep -qF "$SNIPPET_BEGIN" CLAUDE.md; then
  {
    echo
    cat "$SNIPPET_FILE"
  } >> CLAUDE.md
  CHANGES+=("appended security rules to CLAUDE.md")
else
  CHANGES+=("CLAUDE.md already has security rules — left as is")
fi

# 2) .gitignore additions -----------------------------------------------------
GI_TEMPLATE="$SKILL_DIR/templates/gitignore.additions"
if [ -f "$GI_TEMPLATE" ]; then
  touch .gitignore
  added_any=0
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    case "$entry" in \#*) continue;; esac
    if ! grep -qxF "$entry" .gitignore; then
      printf '%s\n' "$entry" >> .gitignore
      added_any=1
    fi
  done < "$GI_TEMPLATE"
  if [ "$added_any" -eq 1 ]; then
    CHANGES+=("appended security entries to .gitignore")
  else
    CHANGES+=(".gitignore already covers security entries")
  fi
fi

# 3) pre-commit hook ----------------------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
  HOOK_DIR="$(git rev-parse --git-path hooks)"
  HOOK_FILE="$HOOK_DIR/pre-commit"
  HOOK_SRC="$SKILL_DIR/scripts/pre-commit.sh"

  if [ -f "$HOOK_SRC" ]; then
    mkdir -p "$HOOK_DIR"
    if [ -f "$HOOK_FILE" ] && ! grep -q 'security-audit pre-commit hook' "$HOOK_FILE" 2>/dev/null; then
      # Existing hook from something else — don't clobber. Tell user.
      CHANGES+=("pre-commit hook exists and is not ours — skipped (manual merge needed: see $HOOK_SRC)")
    else
      cp "$HOOK_SRC" "$HOOK_FILE"
      chmod +x "$HOOK_FILE"
      CHANGES+=("installed pre-commit hook at $HOOK_FILE")
    fi
  fi
else
  CHANGES+=("not a git repo — skipped pre-commit hook")
fi

# 4) marker file --------------------------------------------------------------
{
  echo "installed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "skill_dir: $SKILL_DIR"
} > "$MARKER_FILE"
CHANGES+=("wrote marker $MARKER_FILE")

# Report ---------------------------------------------------------------------
echo "== security-audit install =="
for c in "${CHANGES[@]}"; do
  echo " - $c"
done
echo "Done. Run: bash \"$SKILL_DIR/scripts/audit.sh\""
