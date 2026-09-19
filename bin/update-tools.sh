#!/usr/bin/env zsh
#
# Update the LSP/toolchain dependencies installed for Emacs's eglot/xref
# setup: asdf-managed runtimes, `go install` binaries, global npm packages,
# pip packages, rustup toolchains/components, and cargo-installed binaries.
# Each category is a plain array below -- add a line to extend it.
#
# Usage: update-tools.sh [--asdf] [--go] [--npm] [--pip] [--rustup] [--cargo]
#                         [--dry-run] [--list] [-h]
#   With no category flags, all six categories run.
#
# On completion this always prints a summary of what changed, what was
# already up to date, and -- for anything that failed -- the exact command
# that was attempted, so a failure can be rerun directly for triage.

setopt NO_UNSET PIPE_FAIL

# ---------------------------------------------------------------------------
# What to update
# ---------------------------------------------------------------------------

# asdf plugins to keep pinned to "latest" (plugin update, install latest,
# set -u, reshim)
ASDF_LATEST_PLUGINS=(golang coursier)

# `go install` targets, run against the asdf-managed go
GO_INSTALL_PACKAGES=(
  "golang.org/x/tools/gopls@latest"
)

# Global npm packages, run against the asdf-managed node. Entries are
# "npm-package[:binary]" -- see the PIP_PACKAGES note below for why the
# binary sometimes needs to be given explicitly.
NPM_GLOBAL_PACKAGES=(
  pyright
)

# pip packages, run against the asdf-managed python. Empty for now -- nothing
# from the eglot setup needed pip. Entries are "pip-package[:binary]" -- the
# binary defaults to the package name when omitted, but pip package names
# don't always match their installed binary, e.g. python-lsp-server installs
# the binary `pylsp`, so you'd add it as "python-lsp-server:pylsp".
PIP_PACKAGES=()

# cargo install-update has no package list here by design: it discovers
# every `cargo install`-ed binary itself and updates whichever are stale
# (`cargo install-update -a`).

# ---------------------------------------------------------------------------
# Plumbing
# ---------------------------------------------------------------------------

DRY_RUN=0
LIST_ONLY=0
RUN_ASDF=0
RUN_GO=0
RUN_NPM=0
RUN_PIP=0
RUN_RUSTUP=0
RUN_CARGO=0
ANY_CATEGORY_FLAG=0

# Parallel arrays: what happened, for the closing summary. A failure's
# command lives at the same index in FAILURE_CMDS as its description in
# FAILURES, so the two are always appended together.
CHANGED=()
UNCHANGED=()
FAILURES=()
FAILURE_CMDS=()

log()  { print -P "%F{cyan}==>%f $1" }
skip() { print -P "%F{yellow}  --%f $1" }
ok()   { print -P "%F{green}  ok%f $1" }
fail() { print -P "%F{red}  !!%f $1" >&2 }

# Best-effort "what version is this thing now" probe, used to detect real
# changes for go/npm/pip packages (which, unlike asdf/cargo/rustup, don't
# report their own before/after on stdout).
probe_version() {
  local bin=$1
  command -v "$bin" >/dev/null 2>&1 || return 1
  { "$bin" --version || "$bin" version } 2>/dev/null | head -n1
}

# Classify a before/after probe_version() pair into CHANGED or UNCHANGED
# under the given label. Shared by update_go/update_npm/update_pip so the
# classification rule only needs fixing in one place.
record_probe_result() {
  local label=$1 before=$2 after=$3
  if [[ -n "$after" && "$after" != "$before" ]]; then
    CHANGED+=("$label: ${before:-(none)} -> $after")
  elif [[ -n "$after" ]]; then
    UNCHANGED+=("$label: already $after")
  else
    CHANGED+=("$label: ran (version probe unavailable)")
  fi
}

# Split a "pkg[:binary]" entry (used by NPM_GLOBAL_PACKAGES/PIP_PACKAGES) into
# the package name to install and the binary name to probe_version() against.
# Sets the caller's $pkg and $binname.
split_pkg_bin() {
  local entry=$1
  pkg=${entry%%:*}
  binname=${entry#*:}
  [[ "$binname" == "$entry" ]] && binname=$pkg
}

usage() {
  cat <<'EOF'
Usage: update-tools.sh [options]

Options:
  --asdf        Update only the asdf-managed tools
  --go          Update only `go install` tools
  --npm         Update only global npm tools
  --pip         Update only pip tools
  --rustup      Update only rustup (toolchains + components)
  --cargo       Update only cargo-installed binaries (cargo install-update)
  -n, --dry-run Print what would run without changing anything
  --list        Print the configured tools and exit
  -h, --help    Show this help

With no category flag, all six categories run. Always prints a closing
summary of what changed, what was already current, and the exact command
to rerun for anything that failed.
EOF
}

while (( $# )); do
  case "$1" in
    --asdf) RUN_ASDF=1; ANY_CATEGORY_FLAG=1 ;;
    --go) RUN_GO=1; ANY_CATEGORY_FLAG=1 ;;
    --npm) RUN_NPM=1; ANY_CATEGORY_FLAG=1 ;;
    --pip) RUN_PIP=1; ANY_CATEGORY_FLAG=1 ;;
    --rustup) RUN_RUSTUP=1; ANY_CATEGORY_FLAG=1 ;;
    --cargo) RUN_CARGO=1; ANY_CATEGORY_FLAG=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --list) LIST_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

if (( ! ANY_CATEGORY_FLAG )); then
  RUN_ASDF=1; RUN_GO=1; RUN_NPM=1; RUN_PIP=1; RUN_RUSTUP=1; RUN_CARGO=1
fi

if (( LIST_ONLY )); then
  print "asdf plugins (kept at latest): ${ASDF_LATEST_PLUGINS[*]:-none}"
  print "go install packages:           ${GO_INSTALL_PACKAGES[*]:-none}"
  print "npm global packages:           ${NPM_GLOBAL_PACKAGES[*]:-none}"
  print "pip packages:                  ${PIP_PACKAGES[*]:-none}"
  print "rustup:                        toolchain update (rustup update)"
  print "cargo:                         all installed binaries (cargo install-update -a)"
  exit 0
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "'$1' not found on PATH -- skipping this category"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# asdf
# ---------------------------------------------------------------------------

update_asdf() {
  (( ${#ASDF_LATEST_PLUGINS[@]} )) || { skip "no asdf plugins configured"; return 0 }
  require_cmd asdf || {
    FAILURES+=("asdf: command not found")
    FAILURE_CMDS+=("(command not found: asdf)")
    return 1
  }

  local plugin current latest touched=0
  for plugin in "${ASDF_LATEST_PLUGINS[@]}"; do
    if (( DRY_RUN )); then
      log "[dry-run] asdf plugin update $plugin && asdf install $plugin latest && asdf set -u $plugin latest"
      continue
    fi

    if ! asdf plugin update "$plugin" >/dev/null 2>&1; then
      fail "asdf plugin update $plugin failed"
      FAILURES+=("asdf $plugin: plugin update")
      FAILURE_CMDS+=("asdf plugin update $plugin")
      continue
    fi

    latest=$(asdf latest "$plugin" 2>/dev/null) || {
      fail "asdf latest $plugin failed"
      FAILURES+=("asdf $plugin: latest lookup")
      FAILURE_CMDS+=("asdf latest $plugin")
      continue
    }
    current=$(asdf current "$plugin" 2>/dev/null | awk -v p="$plugin" '$1 == p { print $2; exit }')

    if [[ "$current" == "$latest" ]]; then
      skip "$plugin already at latest ($latest)"
      UNCHANGED+=("asdf $plugin: already $latest")
      continue
    fi

    log "$plugin: ${current:-(none installed)} -> $latest"
    if asdf install "$plugin" latest && asdf set -u "$plugin" latest; then
      ok "$plugin -> $latest"
      CHANGED+=("asdf $plugin: ${current:-(none)} -> $latest")
      touched=1
    else
      fail "$plugin update failed"
      FAILURES+=("asdf $plugin: install")
      FAILURE_CMDS+=("asdf install $plugin latest && asdf set -u $plugin latest")
    fi
  done

  (( DRY_RUN || ! touched )) || asdf reshim
}

# ---------------------------------------------------------------------------
# go install
# ---------------------------------------------------------------------------

update_go() {
  (( ${#GO_INSTALL_PACKAGES[@]} )) || { skip "no go install packages configured"; return 0 }
  require_cmd go || {
    FAILURES+=("go: command not found")
    FAILURE_CMDS+=("(command not found: go)")
    return 1
  }

  local pkg binname before after cmd touched=0
  for pkg in "${GO_INSTALL_PACKAGES[@]}"; do
    binname=${${pkg%@*}:t}
    cmd="go install $pkg"

    if (( DRY_RUN )); then
      log "[dry-run] $cmd"
      continue
    fi

    log "$cmd"
    before=$(probe_version "$binname")
    if command go install "$pkg"; then
      after=$(probe_version "$binname")
      record_probe_result "go install $binname" "$before" "$after"
      ok "$binname"
      touched=1
    else
      fail "$cmd failed"
      FAILURES+=("go install: $binname")
      FAILURE_CMDS+=("$cmd")
    fi
  done

  if (( touched )) && command -v asdf >/dev/null 2>&1; then
    asdf reshim golang 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# npm -g
# ---------------------------------------------------------------------------

update_npm() {
  (( ${#NPM_GLOBAL_PACKAGES[@]} )) || { skip "no npm packages configured"; return 0 }
  require_cmd npm || {
    FAILURES+=("npm: command not found")
    FAILURE_CMDS+=("(command not found: npm)")
    return 1
  }

  local entry pkg binname before after cmd touched=0
  for entry in "${NPM_GLOBAL_PACKAGES[@]}"; do
    split_pkg_bin "$entry"
    cmd="npm install -g ${pkg}@latest"

    if (( DRY_RUN )); then
      log "[dry-run] $cmd"
      continue
    fi

    log "$cmd"
    before=$(probe_version "$binname")
    if npm install -g "${pkg}@latest" >/dev/null; then
      after=$(probe_version "$binname")
      record_probe_result "npm $pkg" "$before" "$after"
      ok "$pkg"
      touched=1
    else
      fail "$cmd failed"
      FAILURES+=("npm: $pkg")
      FAILURE_CMDS+=("$cmd")
    fi
  done

  if (( touched )) && command -v asdf >/dev/null 2>&1; then
    asdf reshim nodejs 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# pip
# ---------------------------------------------------------------------------

update_pip() {
  (( ${#PIP_PACKAGES[@]} )) || { skip "no pip packages configured"; return 0 }
  require_cmd pip || {
    FAILURES+=("pip: command not found")
    FAILURE_CMDS+=("(command not found: pip)")
    return 1
  }

  local entry pkg binname before after cmd touched=0
  for entry in "${PIP_PACKAGES[@]}"; do
    split_pkg_bin "$entry"
    cmd="pip install --upgrade $pkg"

    if (( DRY_RUN )); then
      log "[dry-run] $cmd"
      continue
    fi

    log "$cmd"
    before=$(probe_version "$binname")
    if pip install --upgrade "$pkg" >/dev/null; then
      after=$(probe_version "$binname")
      record_probe_result "pip $pkg" "$before" "$after"
      ok "$pkg"
      touched=1
    else
      fail "$cmd failed"
      FAILURES+=("pip: $pkg")
      FAILURE_CMDS+=("$cmd")
    fi
  done

  if (( touched )) && command -v asdf >/dev/null 2>&1; then
    asdf reshim python 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# rustup
# ---------------------------------------------------------------------------

update_rustup() {
  require_cmd rustup || {
    FAILURES+=("rustup: command not found")
    FAILURE_CMDS+=("(command not found: rustup)")
    return 1
  }

  local cmd="rustup update"
  if (( DRY_RUN )); then
    log "[dry-run] $cmd"
    return 0
  fi
  log "$cmd"

  local tmp rc output
  tmp=$(mktemp)
  rustup update 2>&1 | tee "$tmp"
  rc=$pipestatus[1]
  output=$(<"$tmp")
  rm -f "$tmp"

  if (( rc == 0 )); then
    local matches
    matches=$(print -r -- "$output" | grep -E ' updated - ' || true)
    local -a updated_lines
    updated_lines=()
    (( ${#matches} )) && updated_lines=("${(f)matches}")
    if (( ${#updated_lines[@]} )); then
      local l trimmed
      for l in "${updated_lines[@]}"; do
        trimmed=$(print -r -- "$l" | sed 's/^[[:space:]]*//')
        CHANGED+=("rustup: $trimmed")
      done
    else
      UNCHANGED+=("rustup: no toolchain changes")
    fi
    ok "$cmd"
  else
    fail "$cmd failed"
    FAILURES+=("rustup: update")
    FAILURE_CMDS+=("$cmd")
  fi
}

# ---------------------------------------------------------------------------
# cargo install-update
# ---------------------------------------------------------------------------

update_cargo() {
  require_cmd cargo || {
    FAILURES+=("cargo: command not found")
    FAILURE_CMDS+=("(command not found: cargo)")
    return 1
  }
  if ! cargo install-update -h >/dev/null 2>&1; then
    fail "cargo-update not installed -- run: cargo install cargo-update"
    FAILURES+=("cargo: install-update subcommand missing")
    FAILURE_CMDS+=("cargo install cargo-update")
    return 1
  fi

  local cmd="cargo install-update -a"
  if (( DRY_RUN )); then
    log "[dry-run] $cmd"
    return 0
  fi
  log "$cmd"

  local tmp rc output
  tmp=$(mktemp)
  cargo install-update -a 2>&1 | tee "$tmp"
  rc=$pipestatus[1]
  output=$(<"$tmp")
  rm -f "$tmp"

  local updated_line failed_line
  # Only the "N packages: a, b" form (N > 0) carries a package list; the
  # "0 packages." form has no colon and must not be parsed as one.
  updated_line=$(print -r -- "$output" | grep -E '^Overall updated [0-9]+ packages?: ' || true)
  failed_line=$(print -r -- "$output" | grep -E '^Overall failed to update [0-9]+ packages?: ' || true)

  if [[ -n "$updated_line" ]]; then
    local names=${updated_line#*: }
    names=${names%.}
    local -a name_arr
    name_arr=(${(s/, /)names})
    local n
    for n in "${name_arr[@]}"; do
      CHANGED+=("cargo $n: updated")
    done
  fi

  if [[ -n "$failed_line" ]]; then
    local fnames=${failed_line#*: }
    fnames=${fnames%.}
    local -a fname_arr
    fname_arr=(${(s/, /)fnames})
    local n
    for n in "${fname_arr[@]}"; do
      FAILURES+=("cargo: $n")
      FAILURE_CMDS+=("cargo install-update $n")
    done
  fi

  if [[ -z "$updated_line" && -z "$failed_line" ]]; then
    if (( rc == 0 )); then
      UNCHANGED+=("cargo: all installed binaries already up to date")
      ok "$cmd"
    else
      fail "$cmd failed"
      FAILURES+=("cargo: install-update -a")
      FAILURE_CMDS+=("$cmd")
    fi
  elif [[ -z "$failed_line" ]]; then
    if (( rc == 0 )); then
      ok "$cmd"
    else
      fail "$cmd exited non-zero (status $rc) despite reporting updates -- treating as failed"
      FAILURES+=("cargo: install-update -a (exit $rc)")
      FAILURE_CMDS+=("$cmd")
    fi
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

(( RUN_ASDF ))   && { log "asdf"; update_asdf }
(( RUN_GO ))     && { log "go install"; update_go }
(( RUN_NPM ))    && { log "npm -g"; update_npm }
(( RUN_PIP ))    && { log "pip"; update_pip }
(( RUN_RUSTUP )) && { log "rustup"; update_rustup }
(( RUN_CARGO ))  && { log "cargo install-update"; update_cargo }

# ---------------------------------------------------------------------------
# Summary -- always printed, success or failure
# ---------------------------------------------------------------------------

print
print -P "%B=== Summary ===%b"

if (( DRY_RUN )); then
  print "Dry run -- no changes were made."
else
  if (( ${#CHANGED[@]} )); then
    print -P "%F{green}Changed:%f"
    local c
    for c in "${CHANGED[@]}"; do
      print "  - $c"
    done
  else
    print "Changed: (nothing)"
  fi

  if (( ${#UNCHANGED[@]} )); then
    print -P "%F{yellow}Unchanged:%f"
    local u
    for u in "${UNCHANGED[@]}"; do
      print "  - $u"
    done
  fi
fi

if (( ${#FAILURES[@]} )); then
  print -P "%F{red}Failed (rerun the command below to triage):%f"
  local i
  for (( i = 1; i <= ${#FAILURES[@]}; i++ )); do
    print "  - ${FAILURES[$i]}"
    print "      \$ ${FAILURE_CMDS[$i]}"
  done
  exit 1
fi

print
ok "All done."
