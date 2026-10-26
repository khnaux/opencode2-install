#!/usr/bin/env bash
# install-opencode2.sh - install the latest OpenCode 2.x on Linux, macOS or Termux.
#
# Usage:
#   ./install-opencode2.sh                 # latest 2.x
#   ./install-opencode2.sh --dry-run       # show what would happen
#   ./install-opencode2.sh -v 2.1.4        # pin an exact 2.x version
#
# Upstream installer: https://opencode.ai/v2/install
# Docs:               https://opencode.ai/v2/docs/

# Re-exec under bash if started with `sh script`.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

readonly INSTALL_URL="https://opencode.ai/v2/install"
readonly VERSION_API="https://opencode.ai/update/api/latest/cli/npm"
readonly TERMUX_WRAPPER="@bash0816/opencode-termux"
readonly TERMUX_PREFIX_DEFAULT="/data/data/com.termux/files/usr"

VERSION=""
NPM_PREFIX=""
DRY_RUN=false
INSTALL_DEPS=true
VERIFY=true
TARGET_VERSION=""
PLAN=""

# ---------------------------------------------------------------- output -----

if [ -t 1 ]; then
  C_DIM=$'\033[2m'; C_ACC=$'\033[38;5;214m'; C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
else
  C_DIM=""; C_ACC=""; C_ERR=""; C_OFF=""
fi

log()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
info() { printf '%s%s%s\n' "$C_ACC" "$*" "$C_OFF"; }
err()  { printf '%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Install OpenCode 2.x (Linux, macOS, Termux)

Usage: $0 [options]

Options:
  -v, --version <ver>   Install an exact version, e.g. 2.1.4 (must be 2.x)
      --dry-run         Print the resolved plan, change nothing
      --no-deps         Termux only: do not auto-install glibc-runner/patchelf
      --no-verify       Skip the post-install version check
      --prefix <dir>    npm global prefix (Termux/Android only)
  -h, --help            Show this help

Examples:
  $0
  $0 --dry-run
  $0 -v 2.1.4
  $0 --prefix "\$HOME/.local"
EOF
}

# ------------------------------------------------------------------ args -----

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -v|--version) [ -n "${2:-}" ] || die "--version needs a value"; VERSION="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --no-deps)    INSTALL_DEPS=false; shift ;;
    --no-verify)  VERIFY=false; shift ;;
    --prefix)     [ -n "${2:-}" ] || die "--prefix needs a value"; NPM_PREFIX="$2"; shift 2 ;;
    *)            die "unknown option: $1 (try --help)" ;;
  esac
done

if [ -n "$VERSION" ]; then
  VERSION="${VERSION#v}"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] \
    || die "invalid version '$VERSION' (expected something like 2.1.4)"
  case "$VERSION" in
    2.*) ;;
    *)  die "this script installs OpenCode 2.x only, got $VERSION" ;;
  esac
fi

# -------------------------------------------------------------- platform -----

is_termux() { [ -n "${TERMUX_VERSION:-}" ] || [ -d "$TERMUX_PREFIX_DEFAULT" ]; }
TERMUX=false
is_termux && TERMUX=true

OS_RAW=$(uname -s)
ARCH_RAW=$(uname -m)
case "$OS_RAW" in
  Darwin) OS=darwin ;;
  Linux)  OS=linux ;;
  *)      die "unsupported OS: $OS_RAW (this script covers Linux, macOS and Termux)" ;;
esac
case "$ARCH_RAW" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=x64 ;;
  *)             die "unsupported architecture: $ARCH_RAW (needs arm64 or x64)" ;;
esac

if $TERMUX; then
  case "$ARCH" in
    arm64) ;;
    *) die "OpenCode on Termux currently requires arm64 (found $ARCH_RAW)" ;;
  esac
fi

if ! have curl; then
  die "'curl' is required. Install it with: $(if $TERMUX; then echo 'pkg install curl'; elif [ "$OS" = darwin ]; then echo 'brew install curl'; else echo 'sudo apt install curl'; fi)"
fi

TERMUX_PREFIX="${PREFIX:-$TERMUX_PREFIX_DEFAULT}"
GLIBC_LD="$TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1"

# --------------------------------------------------------------- version -----

resolve_latest() {
  local body
  body=$(curl -fsSL --max-time 30 "$VERSION_API" 2>/dev/null) \
    || die "could not reach $VERSION_API"
  printf '%s' "$body" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n 1
}

if [ -n "$VERSION" ]; then
  TARGET_VERSION="$VERSION"
else
  TARGET_VERSION=$(resolve_latest)
  [ -n "$TARGET_VERSION" ] || die "could not determine the latest OpenCode version"
fi

case "$TARGET_VERSION" in
  2.*) ;;
  *) die "release channel reports $TARGET_VERSION, which is not 2.x. Pin one with: $0 -v 2.1.4" ;;
esac

# ------------------------------------------------------------------ plan -----

if $TERMUX; then
  PLAN="Termux (arm64) -> npm package $TERMUX_WRAPPER@$TARGET_VERSION"
  log "Termux wrapper keeps the official @opencode/cli-linux-arm64 binary working"
  log "on Android by re-pointing its ELF interpreter at the Termux glibc runtime."
else
  PLAN="$OS-$ARCH -> official installer $( [ "$OS" = linux ] && echo '(glibc/musl + baseline auto-detected)' || echo '(Rosetta auto-detected)')"
fi

info "OpenCode 2.x installer"
log  "target version : $TARGET_VERSION"
log  "plan           : $PLAN"
log  "install prefix : $(if $TERMUX; then echo "${NPM_PREFIX:-$(npm prefix -g 2>/dev/null || echo "$TERMUX_PREFIX")}"; else echo "$HOME/.opencode"; fi)"

if $DRY_RUN; then
  log "dry run: nothing was changed"
  exit 0
fi

# --------------------------------------------------------------- helpers -----

oc_binary() {
  if [ -x "$HOME/.opencode/bin/opencode" ]; then
    printf '%s\n' "$HOME/.opencode/bin/opencode"
  elif have opencode; then
    command -v opencode
  else
    return 1
  fi
}

verify() {
  local bin ver
  bin=$(oc_binary) || {
    err "opencode is not on PATH yet."
    err "Native installs live in $HOME/.opencode/bin - add it to PATH or open a new shell:"
    err "  export PATH=\"\$HOME/.opencode/bin:\$PATH\""
    return 1
  }
  log "verifying $bin"
  ver=$("$bin" --version 2>/dev/null | tail -n 1)
  ver=${ver##* }
  ver=${ver#v}
  case "$ver" in
    2.*) info "installed: opencode $ver ($bin)" ;;
    "")  err "could not read the installed version from $bin"; return 1 ;;
    *)   err "expected a 2.x build but found '$ver'"; return 1 ;;
  esac
}

# ------------------------------------------------------------ termux path -----

termux_install() {
  have npm || die "npm is required on Termux. Install it with: pkg install nodejs-lts"
  have node || die "node is required on Termux. Install it with: pkg install nodejs-lts"

  local deps_missing=false
  [ -x "$GLIBC_LD" ] || deps_missing=true
  have patchelf || deps_missing=true

  if $deps_missing; then
    if ! $INSTALL_DEPS; then
      err "missing Termux dependencies (glibc runtime and/or patchelf)."
      err "install them and re-run: pkg install glibc-runner patchelf"
      exit 1
    fi
    have pkg || die "missing glibc runtime and 'pkg' is unavailable. Install glibc-runner and patchelf manually."
    info "installing Termux dependencies: glibc-runner patchelf"
    pkg install -y glibc-runner patchelf
  fi

  local spec="$TERMUX_WRAPPER@$TARGET_VERSION"
  local args=(-g "$spec")
  [ -n "$NPM_PREFIX" ] && args+=(--prefix "$NPM_PREFIX")
  info "npm install ${args[*]}"
  npm install "${args[@]}"

  repair_shebang "${NPM_PREFIX:-$TERMUX_PREFIX}/lib/node_modules/$TERMUX_WRAPPER/bin/opencode-termux"
}

# npm rewrites bin shebangs to "#!/usr/bin/env node", but Android has no /usr/bin.
repair_shebang() {
  local bin="$1"
  [ -f "$bin" ] || return 0
  if have termux-fix-shebang; then
    termux-fix-shebang "$bin" >/dev/null 2>&1 || true
  fi
  if head -n 1 "$bin" 2>/dev/null | grep -q '^#!/usr/bin/env '; then
    log "repairing shebang in $bin"
    sed -i.bak '1s|^#!/usr/bin/env |#!/'"$TERMUX_PREFIX"'/bin/|' "$bin"
    rm -f "$bin.bak"
  fi
}

# ------------------------------------------------------------ native path -----

native_install() {
  local script
  script=$(mktemp "${TMPDIR:-/tmp}/opencode-install.XXXXXX") || die "could not create a temp file"
  trap 'rm -f "$script"' RETURN

  info "downloading the official installer"
  curl -fsSL --max-time 120 "$INSTALL_URL" -o "$script" \
    || die "could not download $INSTALL_URL"

  info "running installer (version $TARGET_VERSION)"
  # VERSION pins the build; unset it lets the installer use the latest 2.x channel.
  VERSION="$TARGET_VERSION" bash "$script"
}

# ------------------------------------------------------------------- main -----

if $TERMUX; then
  termux_install
else
  native_install
fi

if $VERIFY; then
  verify || exit 1
fi

cat <<'EOF'

Next steps
  1. opencode            start the TUI
  2. /connect            add a provider (or use OpenCode Console)
  3. opencode service status
  4. opencode update     update later (Termux: npm i -g @bash0816/opencode-termux@latest)

Docs: https://opencode.ai/v2/docs/
EOF
