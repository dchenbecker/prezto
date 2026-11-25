#!/usr/bin/env zsh
#
# Update the LSP/toolchain dependencies installed for Emacs's eglot/xref
# setup: asdf-managed runtimes, `go install` binaries, global npm packages,
# pip packages, rustup toolchains/components, cargo-installed binaries, and
# Homebrew packages, then records a manifest of what is installed.
# Each category is a plain array below -- add a line to extend it.
#
# Usage: update-tools.sh [--asdf [PLUGIN[=VERSION]]] [--skip-asdf PLUGIN]
#                         [--node [VERSION]]
#                         [--go] [--npm] [--pip]
#                         [--rustup] [--cargo] [--brew] [--manifest]
#                         [--dry-run] [--list] [-h]
#   With no category flags, all configured categories run. Node.js is opt-in
#   because changing the user-wide version can affect other tools.
#
# On completion this always prints a summary of what changed, what was
# already up to date, and -- for anything that failed -- the exact command
# that was attempted, so a failure can be rerun directly for triage.

setopt NO_UNSET PIPE_FAIL

# ---------------------------------------------------------------------------
# What to update
# ---------------------------------------------------------------------------

# Every installed asdf plugin is kept at "latest" by default (plugin update,
# install latest, set -u, reshim). List plugins here to opt them out of that
# default run; install, set -u and reshim are skipped for a plugin that is
# already current. nodejs is skipped because changing the user-wide Node version
# can affect other tools; use --node for it. python and ruby are skipped for
# the same reason (other tooling, including --pip, depends on the current
# interpreter). An explicit `--asdf PLUGIN`
# still updates a skipped plugin, and --skip-asdf PLUGIN adds to this list
# for a single run.
ASDF_SKIP_PLUGINS=(nodejs python ruby)

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

# If UPDATE_TOOLS_TMPDIR is set in the environment (e.g. from a
# runcoms/byhost file), the whole script runs with TMPDIR pointed there so
# asdf installs, cargo builds, etc. don't fill a small default temp
# filesystem.
UPDATE_TOOLS_TMPDIR=${UPDATE_TOOLS_TMPDIR:-}

# Directory for the manifest of what is installed (asdf plugins/versions,
# Brewfile, cargo/rustup/npm lists). The installs themselves live outside
# the backed-up home directory tree and can be rebuilt from these small
# text files, so back this directory up rather than the installs.
TOOL_MANIFEST_DIR=${TOOL_MANIFEST_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tool-manifest}

# ---------------------------------------------------------------------------
# Plumbing
# ---------------------------------------------------------------------------

DRY_RUN=0
LIST_ONLY=0
RUN_ASDF=0
RUN_ASDF_DEFAULT=0
ASDF_PLUGIN_REQUESTS=()
RUN_NODE=0
NODE_VERSION=latest
RUN_GO=0
RUN_NPM=0
RUN_PIP=0
RUN_RUSTUP=0
RUN_CARGO=0
RUN_BREW=0
RUN_MANIFEST=0
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
  --asdf        Update every installed asdf plugin except those opted out
                (ASDF_SKIP_PLUGINS in this script, or --skip-asdf)
  --skip-asdf PLUGIN
                Exclude PLUGIN from the default asdf update (repeatable)
  --asdf PLUGIN
                Update that plugin to its latest version and set it as the
                user-wide default (java defaults to plain Corretto, not musl)
  --asdf PLUGIN=VERSION
                Update to the latest plugin version matching VERSION, then
                set it as the user-wide default (for example java=openjdk-25)
  --node [VERSION]
                Install Node.js via asdf (latest by default), select it as
                the user-wide version, and copy global npm packages it
                lacks (or has at another version) from installed Node.js
                versions; an already-current Node.js is not reselected
  --go          Update only `go install` tools
  --npm         Update only global npm tools
  --pip         Update only pip tools
  --rustup      Update only rustup (toolchains + components)
  --cargo       Update only cargo-installed binaries (cargo install-update)
  --brew        Update only Homebrew/Linuxbrew packages (brew upgrade);
                skipped if brew isn't installed
  --manifest    Only write the installed-tools manifest (see
                TOOL_MANIFEST_DIR); it also runs last in a default run
  -n, --dry-run Print what would run without changing anything
  --list        Print the configured tools and exit
  -h, --help    Show this help

Environment:
  UPDATE_TOOLS_TMPDIR  Run everything with TMPDIR set to this directory
  TOOL_MANIFEST_DIR    Where --manifest writes (default ~/.config/tool-manifest)

With no category flag, all configured categories run. Always prints a closing
summary of what changed, what was already current, and the exact command
to rerun for anything that failed.
EOF
}

while (( $# )); do
  case "$1" in
    --asdf)
      RUN_ASDF=1; ANY_CATEGORY_FLAG=1
      if (( $# > 1 )) && [[ "$2" != -* ]]; then
        ASDF_PLUGIN_REQUESTS+=("$2")
        shift
      else
        RUN_ASDF_DEFAULT=1
      fi
      ;;
    --asdf=*)
      RUN_ASDF=1; ANY_CATEGORY_FLAG=1
      ASDF_PLUGIN_REQUESTS+=("${1#--asdf=}")
      ;;
    --skip-asdf)
      if (( $# < 2 )) || [[ "$2" == -* ]]; then
        print -u2 "--skip-asdf requires a plugin name"; usage; exit 1
      fi
      ASDF_SKIP_PLUGINS+=("$2")
      shift
      ;;
    --skip-asdf=*) ASDF_SKIP_PLUGINS+=("${1#--skip-asdf=}") ;;
    --node)
      RUN_NODE=1; ANY_CATEGORY_FLAG=1
      if (( $# > 1 )) && [[ "$2" != -* ]]; then
        NODE_VERSION=$2
        shift
      fi
      ;;
    --node=*) RUN_NODE=1; NODE_VERSION=${1#--node=}; ANY_CATEGORY_FLAG=1 ;;
    --go) RUN_GO=1; ANY_CATEGORY_FLAG=1 ;;
    --npm) RUN_NPM=1; ANY_CATEGORY_FLAG=1 ;;
    --pip) RUN_PIP=1; ANY_CATEGORY_FLAG=1 ;;
    --rustup) RUN_RUSTUP=1; ANY_CATEGORY_FLAG=1 ;;
    --cargo) RUN_CARGO=1; ANY_CATEGORY_FLAG=1 ;;
    --brew) RUN_BREW=1; ANY_CATEGORY_FLAG=1 ;;
    --manifest) RUN_MANIFEST=1; ANY_CATEGORY_FLAG=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --list) LIST_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

if (( RUN_NODE )) && [[ -z "$NODE_VERSION" ]]; then
  print -u2 "Node.js version cannot be empty"
  usage
  exit 1
fi

for asdf_request in "${ASDF_PLUGIN_REQUESTS[@]}"; do
  if [[ -z "$asdf_request" || ( "$asdf_request" == *=* && ( "${asdf_request%%=*}" == "" || "${asdf_request#*=}" == "" ) ) ]]; then
    print -u2 "asdf plugin requests must use PLUGIN or PLUGIN=VERSION"
    usage
    exit 1
  fi
done

if (( ! ANY_CATEGORY_FLAG )); then
  RUN_ASDF=1; RUN_ASDF_DEFAULT=1; RUN_GO=1; RUN_NPM=1; RUN_PIP=1; RUN_RUSTUP=1; RUN_CARGO=1; RUN_BREW=1; RUN_MANIFEST=1
fi

if (( LIST_ONLY )); then
  print "asdf plugins (kept at latest): all installed, except: ${ASDF_SKIP_PLUGINS[*]:-none}"
  print "asdf custom plugin update:      --asdf PLUGIN[=VERSION]"
  print "asdf Node.js:                 opt-in via --node [VERSION] (latest by default)"
  print "go install packages:           ${GO_INSTALL_PACKAGES[*]:-none}"
  print "npm global packages:           ${NPM_GLOBAL_PACKAGES[*]:-none}"
  print "pip packages:                  ${PIP_PACKAGES[*]:-none}"
  print "rustup:                        toolchain update (rustup update)"
  print "cargo:                         all installed binaries (cargo install-update -a)"
  print "brew:                          brew upgrade (if brew is installed)"
  print "manifest directory:            $TOOL_MANIFEST_DIR"
  print "temp directory:                ${UPDATE_TOOLS_TMPDIR:-default (\$TMPDIR or /tmp)}"
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

# Fallback for plugins whose `asdf latest PLUGIN` comes back empty. asdf 0.20
# ends `asdf list all` output with a blank line, which plugins' latest-stable
# scripts (e.g. gradle's `tail -1`) pick as the "latest" version. Take the
# last non-blank, non-prerelease entry ourselves instead.
asdf_latest_fallback() {
  asdf list all "$1" 2>/dev/null \
    | sed 's/^[[:space:]]*//' \
    | grep -ivE '^$|-src|-dev|-latest|-stm|[-.]rc|-milestone|-alpha|-beta|[-.]pre|-next|snapshot|master' \
    | tail -n1
}

# Print the user-wide version of PLUGIN, i.e. what `asdf set -u` last wrote.
# A project's .tool-versions or an ASDF_<PLUGIN>_VERSION override must not
# stand in for it, or the default could be left stale.
asdf_user_version() {
  local plugin=$1
  (
    cd -q "$HOME" || return 1
    unset "ASDF_${${(U)plugin}//-/_}_VERSION"
    asdf current "$plugin" 2>/dev/null | awk -v p="$plugin" '$1 == p { print $2; exit }'
  )
}

update_asdf() {
  require_cmd asdf || {
    FAILURES+=("asdf: command not found")
    FAILURE_CMDS+=("(command not found: asdf)")
    return 1
  }

  local plugin request selector latest current latest_cmd java_versions java_major
  local -a requests installed_plugins
  local explicit explicit_match
  if (( RUN_ASDF_DEFAULT )); then
    installed_plugins=("${(@f)$(asdf plugin list 2>/dev/null)}")
    for plugin in "${installed_plugins[@]}"; do
      [[ -n "$plugin" ]] || continue
      (( ${ASDF_SKIP_PLUGINS[(Ie)$plugin]} )) && continue
      # An explicit request for the same plugin (possibly with a version
      # selector) takes precedence over the default "latest" update.
      explicit_match=0
      for explicit in "${ASDF_PLUGIN_REQUESTS[@]}"; do
        [[ "${explicit%%=*}" == "$plugin" ]] && explicit_match=1
      done
      (( explicit_match )) || requests+=("$plugin")
    done
  fi
  requests+=("${ASDF_PLUGIN_REQUESTS[@]}")
  (( ${#requests[@]} )) || { skip "no asdf plugins configured"; return 0 }

  for request in "${requests[@]}"; do
    selector=""
    if [[ "$request" == *=* ]]; then
      plugin=${request%%=*}
      selector=${request#*=}
    else
      plugin=$request
      [[ "$plugin" == java ]] && selector=corretto
    fi

    if [[ "$plugin" == java && "$selector" == corretto ]]; then
      latest_cmd="asdf list all java | select highest plain Corretto release, excluding corretto-musl-*"
    elif [[ -n "$selector" ]]; then
      latest_cmd="asdf latest $plugin $selector"
    else
      latest_cmd="asdf latest $plugin"
    fi

    if (( DRY_RUN )); then
      if [[ "$plugin" == java && "$selector" == corretto ]]; then
        log "[dry-run] asdf plugin update java && $latest_cmd && asdf install java <resolved-version> && asdf set -u java <resolved-version>"
      else
        log "[dry-run] asdf plugin update $plugin && $latest_cmd && asdf install $plugin <resolved-version> && asdf set -u $plugin <resolved-version>"
      fi
      continue
    fi

    if ! asdf plugin update "$plugin" >/dev/null 2>&1; then
      fail "asdf plugin update $plugin failed"
      FAILURES+=("asdf $plugin: plugin update")
      FAILURE_CMDS+=("asdf plugin update $plugin")
      continue
    fi

    if [[ "$plugin" == java && "$selector" == corretto ]]; then
      java_versions=$(asdf list all java 2>/dev/null) || java_versions=""
      java_major=$(print -r -- "$java_versions" | tr ' ' '\n' | awk -F '[-.]' '$1 == "corretto" && $2 ~ /^[0-9]+$/ && $2 + 0 > max { max = $2 + 0 } END { if (max) print max }')
      if [[ -z "$java_major" ]]; then
        fail "could not find a plain Corretto Java version"
        FAILURES+=("asdf java: plain Corretto version lookup")
        FAILURE_CMDS+=("asdf list all java")
        continue
      fi
      selector="corretto-$java_major"
      latest_cmd="asdf latest java $selector"
    fi

    if [[ -n "$selector" ]]; then
      latest=$(asdf latest "$plugin" "$selector" 2>/dev/null) || latest=""
    else
      latest=$(asdf latest "$plugin" 2>/dev/null) || latest=""
      [[ -n "$latest" ]] || latest=$(asdf_latest_fallback "$plugin")
    fi
    [[ -n "$latest" ]] || {
      fail "$latest_cmd failed"
      FAILURES+=("asdf $plugin: latest lookup")
      FAILURE_CMDS+=("$latest_cmd")
      continue
    }
    current=$(asdf_user_version "$plugin")

    # A selected version can still be missing on disk (e.g. a restored
    # .tool-versions), so both must hold before there's nothing to do.
    if [[ "$current" == "$latest" ]] && asdf where "$plugin" "$latest" >/dev/null 2>&1; then
      ok "$plugin already $latest"
      UNCHANGED+=("asdf $plugin: already $latest")
      continue
    fi

    log "$plugin: ${current:-(none selected)} -> $latest (user-wide default)"
    if ! asdf install "$plugin" "$latest"; then
      fail "asdf install $plugin $latest failed"
      FAILURES+=("asdf $plugin: install $latest")
      FAILURE_CMDS+=("asdf install $plugin $latest")
      continue
    fi
    if ! asdf set -u "$plugin" "$latest"; then
      fail "asdf set -u $plugin $latest failed"
      FAILURES+=("asdf $plugin: set default $latest")
      FAILURE_CMDS+=("asdf set -u $plugin $latest")
      continue
    fi
    asdf reshim "$plugin" 2>/dev/null || true
    ok "$plugin -> $latest (user-wide default)"
    CHANGED+=("asdf $plugin: user-wide default set to $latest")
  done
}

# ---------------------------------------------------------------------------
# Node.js via asdf
# ---------------------------------------------------------------------------

update_node() {
  require_cmd asdf || {
    FAILURES+=("nodejs: asdf command not found")
    FAILURE_CMDS+=("(command not found: asdf)")
    return 1
  }

  local target_version current_version listed_versions source_version install_dir
  local package_json package_lines package_line package_name package_version package_spec target_dir target_npm
  local cmd select_needed=1
  local -a source_versions ordered_versions packages_to_copy
  local -A package_versions target_packages

  target_version=$NODE_VERSION
  if [[ "$target_version" == latest ]]; then
    target_version=$(asdf latest nodejs 2>/dev/null) || {
      fail "asdf latest nodejs failed"
      FAILURES+=("nodejs: latest lookup")
      FAILURE_CMDS+=("asdf latest nodejs")
      return 1
    }
  fi

  current_version=$(asdf_user_version nodejs)
  listed_versions=$(asdf list nodejs 2>/dev/null || true)
  source_versions=()
  local version_line
  for version_line in "${(@f)listed_versions}"; do
    version_line=$(print -r -- "$version_line" | awk '{ for (i = 1; i <= NF; i++) { v = $i; sub(/^[*]/, "", v); if (v ~ /^[0-9]/) { print v; exit } } }')
    [[ "$version_line" == [0-9]* ]] && source_versions+=("$version_line")
  done

  ordered_versions=()
  if [[ -n "$current_version" && "$current_version" != system ]]; then
    for source_version in "${source_versions[@]}"; do
      [[ "$source_version" == "$current_version" ]] && ordered_versions+=("$source_version")
    done
  fi
  for source_version in "${source_versions[@]}"; do
    [[ "$source_version" == "$current_version" ]] || ordered_versions+=("$source_version")
  done

  # The first version seen supplies each package, current version first, so
  # its choice wins even over a newer one already in the target.
  package_versions=()
  target_packages=()
  for source_version in "${ordered_versions[@]}"; do
    install_dir=$(asdf where nodejs "$source_version" 2>/dev/null) || {
      fail "could not locate Node.js $source_version"
      FAILURES+=("nodejs: locate source version $source_version")
      FAILURE_CMDS+=("asdf where nodejs $source_version")
      return 1
    }
    if [[ ! -x "$install_dir/bin/node" || ! -x "$install_dir/bin/npm" ]]; then
      fail "Node.js $source_version has no usable node/npm binaries"
      FAILURES+=("nodejs: inspect source version $source_version")
      FAILURE_CMDS+=("asdf where nodejs $source_version")
      return 1
    fi
    package_json=$("$install_dir/bin/npm" ls --global --depth=0 --json 2>/dev/null) || {
      fail "could not read global npm packages from Node.js $source_version"
      FAILURES+=("nodejs: read global npm packages for $source_version")
      FAILURE_CMDS+=("$install_dir/bin/npm ls --global --depth=0 --json")
      return 1
    }
    package_lines=$("$install_dir/bin/node" -e '
      const { readFileSync } = require("node:fs");
      const tree = JSON.parse(readFileSync(0, "utf8"));
      for (const [name, info] of Object.entries(tree.dependencies || {})) {
        if (name !== "npm" && info.version) console.log(`${name}\t${info.version}`);
      }
    ' <<< "$package_json") || {
      fail "could not read global npm packages from Node.js $source_version"
      FAILURES+=("nodejs: read global npm packages for $source_version")
      FAILURE_CMDS+=("$install_dir/bin/npm ls --global --depth=0 --json")
      return 1
    }
    for package_line in "${(@f)package_lines}"; do
      [[ -n "$package_line" ]] || continue
      package_name=${package_line%%$'\t'*}
      package_version=${package_line#*$'\t'}
      [[ "$source_version" == "$target_version" ]] && target_packages[$package_name]=$package_version
      [[ -n "${package_versions[$package_name]-}" ]] && continue
      package_versions[$package_name]=$package_version
    done
  done

  # Reinstalling what the target already has would be reported as a change.
  packages_to_copy=()
  for package_name in "${(@k)package_versions}"; do
    [[ "${target_packages[$package_name]-}" == "${package_versions[$package_name]}" ]] \
      || packages_to_copy+=("$package_name")
  done

  if [[ "$current_version" == "$target_version" ]] \
    && asdf where nodejs "$target_version" >/dev/null 2>&1; then
    select_needed=0
  fi

  cmd="asdf install nodejs $target_version && asdf set -u nodejs $target_version"
  if (( DRY_RUN )); then
    if (( select_needed )); then
      log "[dry-run] $cmd"
    else
      log "[dry-run] nodejs already $target_version"
    fi
    log "[dry-run] copy ${#packages_to_copy} global npm package(s) from installed Node.js versions"
    return 0
  fi

  if (( select_needed )); then
    log "nodejs: ${current_version:-(none selected)} -> $target_version"
    if ! asdf install nodejs "$target_version"; then
      fail "asdf install nodejs $target_version failed"
      FAILURES+=("nodejs: install $target_version")
      FAILURE_CMDS+=("asdf install nodejs $target_version")
      return 1
    fi
    if ! asdf set -u nodejs "$target_version"; then
      fail "asdf set -u nodejs $target_version failed"
      FAILURES+=("nodejs: select $target_version")
      FAILURE_CMDS+=("asdf set -u nodejs $target_version")
      return 1
    fi
    if [[ "$current_version" == "$target_version" ]]; then
      CHANGED+=("asdf nodejs: reinstalled $target_version")
    else
      CHANGED+=("asdf nodejs: ${current_version:-(none)} -> $target_version")
    fi
  else
    ok "nodejs already $target_version"
    UNCHANGED+=("asdf nodejs: already $target_version")
  fi

  target_dir=$(asdf where nodejs "$target_version" 2>/dev/null) || {
    fail "could not locate installed Node.js $target_version"
    FAILURES+=("nodejs: locate target version $target_version")
    FAILURE_CMDS+=("asdf where nodejs $target_version")
    return 1
  }
  target_npm="$target_dir/bin/npm"
  if [[ ! -x "$target_npm" ]]; then
    fail "Node.js $target_version has no usable npm binary"
    FAILURES+=("nodejs: npm unavailable for $target_version")
    FAILURE_CMDS+=("asdf where nodejs $target_version")
    return 1
  fi

  for package_name in "${packages_to_copy[@]}"; do
    package_spec="$package_name@${package_versions[$package_name]}"
    if "$target_npm" install --global "$package_spec" >/dev/null; then
      ok "copied $package_spec to Node.js $target_version"
      CHANGED+=("node global npm package: $package_spec -> $target_version")
    else
      fail "npm install --global $package_spec failed for Node.js $target_version"
      FAILURES+=("nodejs: copy $package_spec")
      FAILURE_CMDS+=("$target_npm install --global $package_spec")
    fi
  done

  asdf reshim nodejs 2>/dev/null || true
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

  local env_prefix=${UPDATE_TOOLS_TMPDIR:+TMPDIR=$UPDATE_TOOLS_TMPDIR }
  local cmd="${env_prefix}cargo install-update -a"
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
      FAILURE_CMDS+=("${env_prefix}cargo install-update $n")
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
# Homebrew / Linuxbrew
# ---------------------------------------------------------------------------

update_brew() {
  command -v brew >/dev/null 2>&1 || { skip "brew not installed"; return 0 }

  local cmd="brew upgrade"
  if (( DRY_RUN )); then
    log "[dry-run] $cmd"
    return 0
  fi
  log "$cmd"

  # `brew upgrade` has no machine-readable summary, so diff the installed
  # versions before and after to report what actually changed.
  local before after rc line name new changed=0
  local -A old_versions
  before=$(brew list --versions 2>/dev/null)
  brew upgrade
  rc=$?
  after=$(brew list --versions 2>/dev/null)

  for line in "${(@f)before}"; do
    [[ -n "$line" ]] && old_versions[${line%% *}]=${line#* }
  done
  for line in "${(@f)after}"; do
    [[ -n "$line" ]] || continue
    name=${line%% *}
    new=${line#* }
    if [[ -z "${old_versions[$name]-}" ]]; then
      CHANGED+=("brew $name: installed $new"); changed=1
    elif [[ "${old_versions[$name]}" != "$new" ]]; then
      CHANGED+=("brew $name: ${old_versions[$name]} -> $new"); changed=1
    fi
  done

  if (( rc == 0 )); then
    (( changed )) || UNCHANGED+=("brew: all packages already up to date")
    ok "$cmd"
  else
    fail "$cmd failed"
    FAILURES+=("brew: upgrade")
    FAILURE_CMDS+=("$cmd")
  fi
}

# ---------------------------------------------------------------------------
# Manifest of installed tools
# ---------------------------------------------------------------------------

# write_manifest NAME CMD...: run CMD and store its stdout as
# $TOOL_MANIFEST_DIR/NAME. Written via a temp file so a failing command never
# clobbers the previous good manifest.
write_manifest() {
  local name=$1; shift
  local out="$TOOL_MANIFEST_DIR/$name" tmp
  tmp=$(mktemp "$out.XXXXXX") || {
    fail "cannot write $out"
    FAILURES+=("manifest: $name")
    FAILURE_CMDS+=("mkdir -p $TOOL_MANIFEST_DIR")
    return 1
  }
  if "$@" >"$tmp" 2>/dev/null; then
    chmod 644 "$tmp"
    if [[ -f "$out" ]] && cmp -s "$tmp" "$out"; then
      rm -f "$tmp"
      UNCHANGED+=("manifest $name: unchanged")
    else
      mv -f "$tmp" "$out"
      CHANGED+=("manifest $name: written")
    fi
  else
    rm -f "$tmp"
    fail "${(j: :)@} failed"
    FAILURES+=("manifest: $name")
    FAILURE_CMDS+=("${(j: :)@}")
  fi
}

update_manifest() {
  if (( DRY_RUN )); then
    log "[dry-run] write manifest files to $TOOL_MANIFEST_DIR"
    return 0
  fi
  mkdir -p "$TOOL_MANIFEST_DIR" || {
    fail "cannot create $TOOL_MANIFEST_DIR"
    FAILURES+=("manifest: create directory")
    FAILURE_CMDS+=("mkdir -p $TOOL_MANIFEST_DIR")
    return 1
  }
  log "manifest -> $TOOL_MANIFEST_DIR"

  # asdf's .tool-versions records versions but not which plugin repos they
  # came from, so the plugin URLs are needed to rebuild.
  if command -v asdf >/dev/null 2>&1; then
    write_manifest asdf-plugins.txt asdf plugin list --urls
    write_manifest asdf-installed.txt asdf list
  fi
  # Only formulae/casks/taps: the go/cargo/npm sections `brew bundle dump`
  # can add are covered by their own manifests below.
  if command -v brew >/dev/null 2>&1; then
    write_manifest Brewfile brew bundle dump --formula --cask --tap --file=-
  fi
  if command -v cargo >/dev/null 2>&1; then
    write_manifest cargo-installed.txt cargo install --list
  fi
  if command -v rustup >/dev/null 2>&1; then
    write_manifest rustup-toolchains.txt rustup toolchain list
    write_manifest rustup-components.txt rustup component list --installed
    write_manifest rustup-targets.txt rustup target list --installed
  fi
  if command -v npm >/dev/null 2>&1; then
    write_manifest npm-global.txt npm ls -g --depth=0
  fi
  ok "manifest"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [[ -n "$UPDATE_TOOLS_TMPDIR" ]]; then
  (( DRY_RUN )) || mkdir -p "$UPDATE_TOOLS_TMPDIR" || {
    print -u2 "cannot create UPDATE_TOOLS_TMPDIR: $UPDATE_TOOLS_TMPDIR"
    exit 1
  }
  export TMPDIR=$UPDATE_TOOLS_TMPDIR
fi

(( RUN_ASDF ))   && { log "asdf"; update_asdf }
(( RUN_NODE ))   && { log "asdf Node.js"; update_node }
(( RUN_GO ))     && { log "go install"; update_go }
(( RUN_NPM ))    && { log "npm -g"; update_npm }
(( RUN_PIP ))    && { log "pip"; update_pip }
(( RUN_RUSTUP )) && { log "rustup"; update_rustup }
(( RUN_CARGO ))  && { log "cargo install-update"; update_cargo }
(( RUN_BREW ))   && { log "brew"; update_brew }
# Last, so the manifest reflects the post-update state.
(( RUN_MANIFEST )) && update_manifest

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
  [[ -n "$UPDATE_TOOLS_TMPDIR" ]] && print "  (run them with TMPDIR=$UPDATE_TOOLS_TMPDIR to keep temp files off /tmp)"
  local i
  for (( i = 1; i <= ${#FAILURES[@]}; i++ )); do
    print "  - ${FAILURES[$i]}"
    print "      \$ ${FAILURE_CMDS[$i]}"
  done
  exit 1
fi

print
ok "All done."
