#!/usr/bin/env bash
# Tests for bin/claude-resume-recent and bin/claude-resume-session. tmux,
# Windows Terminal, dialog, and claude are stubbed, so nothing is opened.

set -u

bin="$(cd "$(dirname "$0")/../bin" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

check() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL %s: expected %q in:\n%s\n' "$name" "$needle" "$haystack"
    failures=$((failures + 1))
  fi
}

refute() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'FAIL %s: unexpected %q in:\n%s\n' "$name" "$needle" "$haystack"
    failures=$((failures + 1))
  fi
}

# Usage: session ID CWD AGE TITLE_RECORD...
session() {
  local id="$1" cwd="$2" age="$3"
  local file="$work/config/projects/p/$id.jsonl"
  shift 3
  printf '{"type":"user","cwd":"%s"}\n' "$cwd" > "$file"
  (($# == 0)) || printf '%s\n' "$@" >> "$file"
  touch -d "$age ago" "$file"
}

printf '#!/bin/sh\nfor a; do printf "[%%s]" "$a"; done >> "%s/log"\necho >> "%s/log"\n' \
  "$work" "$work" > "$work/record"
# Selects the first two checklist entries.
printf '#!/bin/sh\nprintf "0\\n1\\n"\n' > "$work/dialog"
chmod +x "$work/record" "$work/dialog"

run() {
  env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_RESUME_EXCLUDE_SESSION \
    -u CLAUDE_RESUME_MODE -u CLAUDE_RESUME_MAX_AGE_HOURS -u WT_PROFILE_ID \
    CLAUDE_CONFIG_DIR="$work/config" TMUX=dummy \
    CLAUDE_RESUME_TMUX="$work/record" CLAUDE_RESUME_WT="$work/record" \
    CLAUDE_RESUME_DIALOG="$work/dialog" CLAUDE_RESUME_CLAUDE=stub-claude \
    CLAUDE_RESUME_WRAPPER=stub-wrapper CLAUDE_RESUME_DISTRO=distro \
    "${extra_env[@]}" "$bin/claude-resume-recent" "$@" 2>&1
}
extra_env=(IGNORED=)

mkdir -p "$work/config/projects/p" "$work/dir"

out="$(run --dry-run)"
check "empty dry run" "$out" "Would restore 0 session(s)"
out="$(run)"
check "empty real run" "$out" "No sessions active"

session new "$work/dir" '1 hour' \
  '{"type":"ai-title","aiTitle":"generated"}' \
  '{"type":"custom-title","customTitle":"fix #1;"}'
session mid "$work/dir" '2 hours' '{"type":"ai-title","aiTitle":"a;b"}'
session old "$work/dir" '100 hours'
session gone "$work/missing" '1 hour'

out="$(run --dry-run)"
check "custom title wins" "$out" "fix #1;"
refute "generated title hidden" "$out" "generated"
check "recent first" "${out%%a;b*}" "fix #1;"
check "age cutoff and missing dir" "$out" "Would restore 2 session(s); skipped 1."
out="$(run --dry-run --max-age-hours 0101)"
check "leading zero is decimal" "$out" "Would restore 3 session(s)"

extra_env=(CLAUDE_CODE_SESSION_ID=new)
out="$(run --dry-run)"
refute "current session excluded" "$out" "fix #1"
extra_env=(IGNORED=)

: > "$work/log"
out="$(run --mode tmux)"
log="$(cat "$work/log")"
check "tmux count" "$out" "Opened 2 session(s)"
check "tmux escaping" "$log" "[-n][fix ##1]"
check "tmux command" "$log" \
  "[env][CLAUDE_CONFIG_DIR=$work/config][stub-wrapper][stub-claude][new]"

: > "$work/log"
out="$(run --mode wt)"
log="$(cat "$work/log")"
check "wt escaping" "$log" '[Claude: a\;b]'
check "wt command" "$log" '[stub-wrapper][stub-claude][mid]'

extra_env=(CLAUDE_RESUME_TMUX=false)
out="$(run --mode tmux)"
check "launch failure continues" "$out" "Failed to open session mid"
check "launch failure summary" "$out" "Opened 0 session(s)"

out="$(SHELL=/bin/true "$bin/claude-resume-session" true abc)"
check "wrapper hint" "$out" "claude --resume abc"

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
echo "All tests passed."
