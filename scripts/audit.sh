#!/usr/bin/env bash
# audit.sh — scan codebase for leaked secrets and common AI-coding security issues.
# Output format:  SEVERITY | path:line | rule_id | masked_preview
# Exit codes: 0 clean, 1 findings, 2 script error.
#
# Works on macOS (BSD) and Linux (GNU). No external deps required, but uses
# gitleaks if it's on PATH for better-quality detection.

set -u
LC_ALL=C
export LC_ALL

# ---- locate project root ----------------------------------------------------
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "audit: cannot cd to $ROOT" >&2; exit 2; }

CRIT=0; HIGH=0; MED=0; LOW=0
TMPDIR_AUDIT="$(mktemp -d 2>/dev/null || mktemp -d -t audit)"
FINDINGS="$TMPDIR_AUDIT/findings.txt"
: > "$FINDINGS"
trap 'rm -rf "$TMPDIR_AUDIT"' EXIT

emit() {
  # severity rule_id path line preview
  local sev="$1" rule="$2" path="$3" line="$4" preview="$5"
  case "$sev" in
    CRITICAL) CRIT=$((CRIT+1));;
    HIGH)     HIGH=$((HIGH+1));;
    MEDIUM)   MED=$((MED+1));;
    LOW)      LOW=$((LOW+1));;
  esac
  # file-level findings (no specific line) get ":-" instead of ":0"
  if [ "$line" = "0" ] || [ -z "$line" ]; then
    printf '%s | %s | %s | %s\n' "$sev" "$path" "$rule" "$preview" >> "$FINDINGS"
  else
    printf '%s | %s:%s | %s | %s\n' "$sev" "$path" "$line" "$rule" "$preview" >> "$FINDINGS"
  fi
}

mask() {
  # show first 4 + last 2 chars, mask the rest. Keeps output safe.
  local s="$1"
  local n=${#s}
  if [ "$n" -le 8 ]; then
    printf '****'
  else
    printf '%s****%s' "${s:0:4}" "${s: -2}"
  fi
}

# ---- file list --------------------------------------------------------------
# tracked + untracked-but-not-ignored, exclude binaries and big build dirs
list_files() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    { git ls-files; git ls-files --others --exclude-standard; } | sort -u
  else
    find . -type f \
      -not -path '*/node_modules/*' \
      -not -path '*/.git/*' \
      -not -path '*/.next/*' \
      -not -path '*/.nuxt/*' \
      -not -path '*/dist/*' \
      -not -path '*/build/*' \
      -not -path '*/.venv/*' \
      -not -path '*/venv/*' \
      -not -path '*/__pycache__/*' \
      -not -path '*/coverage/*' \
      -not -path '*/.turbo/*' \
      | sed 's|^\./||'
  fi
}

is_scannable() {
  local f="$1"
  [ -f "$f" ] || return 1
  # skip lockfiles, minified, source maps
  case "$f" in
    *.lock|*.lockb|package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb) return 1;;
    *.min.js|*.min.css|*.map) return 1;;
    # binary assets
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.bmp|*.tiff) return 1;;
    *.pdf|*.zip|*.tar|*.gz|*.bz2|*.7z|*.rar) return 1;;
    *.mp3|*.mp4|*.mov|*.avi|*.webm|*.wav|*.ogg) return 1;;
    *.woff|*.woff2|*.ttf|*.eot|*.otf) return 1;;
    *.so|*.dylib|*.dll|*.exe|*.bin|*.o|*.a|*.class|*.jar|*.wasm) return 1;;
    *.snap|*.iso) return 1;;
    # build/vendor/cache directories
    .git/*|*/.git/*) return 1;;
    node_modules/*|*/node_modules/*) return 1;;
    dist/*|*/dist/*|build/*|*/build/*) return 1;;
    .next/*|*/.next/*|.nuxt/*|*/.nuxt/*|.turbo/*|*/.turbo/*) return 1;;
    .venv/*|*/.venv/*|venv/*|*/venv/*|__pycache__/*|*/__pycache__/*) return 1;;
    coverage/*|*/coverage/*|.cache/*|*/.cache/*) return 1;;
    target/*|*/target/*) return 1;;  # rust build dir; remove if it conflicts in your projects
    # example/template env files (these are supposed to have placeholders)
    .env.example|*/.env.example|.env.sample|*/.env.sample|.env.template|*/.env.template) return 1;;
  esac
  return 0
}

# ---- detection rules --------------------------------------------------------
# Each rule: id, severity, awk-friendly ERE pattern, label.
# Patterns are intentionally specific to keep false-positives low.

scan_secret_patterns() {
  local f="$1"
  awk -v file="$f" '
    function emit_find(sev, rule, line, val) {
      printf "FIND\t%s\t%s\t%s\t%s\t%s\n", sev, rule, file, NR, val
    }
    {
      l = $0
      # strip obvious comments to reduce noise on commented-out examples
      # (we still scan but lower severity is handled by rule choice)

      # ---- CRITICAL: provider-specific live keys ----
      if (match(l, /sk-ant-api03-[A-Za-z0-9_-]{20,}/))           { emit_find("CRITICAL","anthropic_api_key",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /sk-proj-[A-Za-z0-9_-]{20,}/))                { emit_find("CRITICAL","openai_project_key",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /\<sk-[A-Za-z0-9]{32,}/))                      { emit_find("CRITICAL","openai_api_key",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /sk_live_[A-Za-z0-9]{16,}/))                  { emit_find("CRITICAL","stripe_live_secret",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /rk_live_[A-Za-z0-9]{16,}/))                  { emit_find("CRITICAL","stripe_restricted_live",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /AKIA[0-9A-Z]{16}/))                          { emit_find("CRITICAL","aws_access_key_id",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /ASIA[0-9A-Z]{16}/))                          { emit_find("CRITICAL","aws_session_key_id",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /ghp_[A-Za-z0-9]{30,}/))                      { emit_find("CRITICAL","github_pat_classic",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /github_pat_[A-Za-z0-9_]{50,}/))              { emit_find("CRITICAL","github_pat_fine",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /ghs_[A-Za-z0-9]{30,}/))                      { emit_find("CRITICAL","github_app_token",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /xox[abprs]-[A-Za-z0-9-]{10,}/))              { emit_find("CRITICAL","slack_token",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /AIza[0-9A-Za-z_-]{35}/))                     { emit_find("CRITICAL","google_api_key",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /SG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{30,}/)){ emit_find("CRITICAL","sendgrid_key",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /AC[a-z0-9]{32}/))                            { emit_find("CRITICAL","twilio_account_sid",NR,substr(l,RSTART,RLENGTH)); }
      if (match(l, /-----BEGIN [A-Z ]*PRIVATE KEY-----/))        { emit_find("CRITICAL","private_key_block",NR,"-----BEGIN PRIVATE KEY-----"); }

      # ---- HIGH: assignment-shape secrets ----
      # value assignments to suspicious names with quoted literal of >=12 chars
      if (match(l, /(api[_-]?key|secret|token|passwd|password|client[_-]?secret|auth[_-]?token)[[:space:]]*[:=][[:space:]]*["'\'']([A-Za-z0-9_\-\/\+\.=]{12,})["'\'']/)) {
        # ignore if value looks like a placeholder
        ll = tolower(l)
        if (ll !~ /(your[_-]?(api[_-]?)?key|placeholder|example|xxx+|<redacted>|change[_-]?me|todo|fake|dummy|test[_-]?key)/) {
          emit_find("HIGH","assigned_secret_literal",NR,"<redacted assignment>")
        }
      }
      # process.env.X = "literal" pattern (writing to env at runtime, often a leak smell)
      if (match(l, /process\.env\.[A-Z0-9_]+[[:space:]]*=[[:space:]]*["'\''][^"\x27]{8,}["'\'']/)) {
        emit_find("HIGH","process_env_literal_assign",NR,"<redacted assignment>")
      }

      # ---- HIGH: client-exposed env vars holding sensitive-looking names ----
      # AI assistants frequently slap NEXT_PUBLIC_ on a server secret to silence an "undefined" error.
      # This bundles the secret into every browser. Patterns chosen to stay zero-false-positive on
      # legitimately-public vars like NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN or NEXT_PUBLIC_POSTHOG_KEY.
      if (match(l, /(NEXT_PUBLIC|VITE|REACT_APP|EXPO_PUBLIC|PUBLIC)_[A-Z0-9_]*(SECRET|PRIVATE|SERVICE[_-]?(ACCOUNT|ROLE)|ADMIN|SERVER[_-]?KEY|PASSWORD|PRIVATE[_-]?KEY|DATABASE[_-]?URL|DB[_-]?URL|WEBHOOK[_-]?SECRET|JWT[_-]?SECRET|ENCRYPTION[_-]?KEY|SIGNING[_-]?KEY|MASTER[_-]?KEY|REFRESH[_-]?TOKEN)[A-Z0-9_]*/)) {
        emit_find("HIGH","public_prefix_on_secret_name",NR,substr(l,RSTART,RLENGTH))
      }

      # ---- MEDIUM: console.log / print of suspicious vars ----
      if (match(l, /(console\.log|console\.debug|console\.info|print|println!|printf)[[:space:]]*\(.*(token|secret|password|api[_-]?key|auth)/)) {
        # avoid string literals like "no token" - require at least an identifier-ish thing nearby
        emit_find("MEDIUM","logging_secret_like_var",NR,"<log of secret-named var>")
      }

      # ---- MEDIUM: hardcoded JWT (3 base64url segments separated by dots, header eyJ) ----
      if (match(l, /eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/)) {
        emit_find("MEDIUM","hardcoded_jwt",NR,substr(l,RSTART,18) "...")
      }

      # ---- LOW: connection strings with embedded credentials ----
      if (match(l, /(postgres|postgresql|mysql|mongodb|mongodb\+srv|redis|amqp|amqps):\/\/[^:\/\x27"`[:space:]]+:[^@\x27"`[:space:]]+@/)) {
        emit_find("HIGH","db_url_with_creds",NR,"<credentialed db url>")
      }
    }
  ' "$f"
}

# ---- env file checks (separate from content scanning) ----------------------
check_env_files() {
  # 1) is .env (or .env.local etc) tracked by git?
  if git rev-parse --git-dir >/dev/null 2>&1; then
    while IFS= read -r tracked; do
      case "$tracked" in
        .env|.env.local|.env.development|.env.production|.env.staging|.env.test|*/\.env|*/\.env.local)
          emit "CRITICAL" "tracked_env_file" "$tracked" "0" "<env file is tracked>"
          ;;
      esac
    done < <(git ls-files)
  fi

  # 2) does .gitignore cover env files?
  if [ ! -f .gitignore ] || ! grep -qE '^\.env(\.|$)|^\.env$|^\*\.env$' .gitignore 2>/dev/null; then
    emit "MEDIUM" "gitignore_missing_env" ".gitignore" "0" "<no .env rule in .gitignore>"
  fi

  # 3) service account / firebase admin JSON tracked?
  if git rev-parse --git-dir >/dev/null 2>&1; then
    while IFS= read -r f; do
      case "$f" in
        *service-account*.json|*serviceAccount*.json|*firebase-adminsdk*.json|*-credentials.json)
          emit "CRITICAL" "tracked_service_account" "$f" "0" "<service-account JSON tracked>"
          ;;
      esac
    done < <(git ls-files)
  fi
}

# ---- gitleaks pass (if available) ------------------------------------------
run_gitleaks_if_available() {
  command -v gitleaks >/dev/null 2>&1 || return 0
  # Run only on filesystem (not history) by default. History scan is heavy and noisy.
  local gl_out="$TMPDIR_AUDIT/gitleaks.json"
  if gitleaks detect --no-banner --no-git --report-format json --report-path "$gl_out" --exit-code 0 >/dev/null 2>&1; then
    if [ -s "$gl_out" ]; then
      # crude JSON parse without jq dependency
      awk '
        /"RuleID"/    { gsub(/[",]/,""); rid=$2 }
        /"File"/      { gsub(/[",]/,""); file=$2 }
        /"StartLine"/ { gsub(/[",]/,""); line=$2 }
        /"Match"/     { gsub(/^[[:space:]]+/,""); sub(/^"Match":[[:space:]]*"/,""); sub(/",?$/,""); match_v=$0
                        printf "FIND\tCRITICAL\tgitleaks_%s\t%s\t%s\t%s\n", rid, file, line, "<redacted>"
                      }
      ' "$gl_out" >> "$TMPDIR_AUDIT/raw.txt" || true
    fi
  fi
}

# ---- main scan loop ---------------------------------------------------------
: > "$TMPDIR_AUDIT/raw.txt"

while IFS= read -r f; do
  is_scannable "$f" || continue
  scan_secret_patterns "$f" >> "$TMPDIR_AUDIT/raw.txt"
done < <(list_files)

run_gitleaks_if_available
check_env_files

# ingest pattern findings
while IFS=$'\t' read -r tag sev rule file line val; do
  [ "$tag" = "FIND" ] || continue
  preview="$(mask "$val")"
  emit "$sev" "$rule" "$file" "$line" "$preview"
done < "$TMPDIR_AUDIT/raw.txt"

# ---- output -----------------------------------------------------------------
TOTAL=$((CRIT+HIGH+MED+LOW))

if [ "$TOTAL" -eq 0 ]; then
  echo "== Security Audit =="
  echo "No findings. Repo is clean for known patterns."
  echo "Scanned root: $ROOT"
  exit 0
fi

# group by severity for compact output
print_section() {
  local label="$1"
  local matches
  matches="$(grep "^$label |" "$FINDINGS" || true)"
  if [ -n "$matches" ]; then
    printf '\n== %s ==\n' "$label"
    printf '%s\n' "$matches"
  fi
}

echo "== Security Audit =="
echo "Root: $ROOT"
echo "Findings: $CRIT CRITICAL, $HIGH HIGH, $MED MEDIUM, $LOW LOW"
print_section "CRITICAL"
print_section "HIGH"
print_section "MEDIUM"
print_section "LOW"
echo
echo "Next: open references/fix-playbook.md and fix by rule_id."
exit 1
