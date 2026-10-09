#!/usr/bin/env bash
#
# Checks the prerequisites for testing Kong plugins with Pongo and installs
# Pongo at a pinned version. Safe to run multiple times.
#
#   scripts/setup.sh            check prerequisites + install/update Pongo
#   scripts/setup.sh --check    only check, change nothing
#
# Overridable through environment variables:
#   PONGO_VERSION   Pongo git tag to install        (pinned in this script)
#   PONGO_HOME      where Pongo gets cloned         (default ~/.local/share/kong-pongo)
#   PONGO_BIN_DIR   where the 'pongo' link is put   (default ~/.local/bin)

set -u

PONGO_VERSION="${PONGO_VERSION:-2.29.0}"
PONGO_REPO="https://github.com/Kong/kong-pongo.git"
PONGO_HOME="${PONGO_HOME:-$HOME/.local/share/kong-pongo}"
PONGO_BIN_DIR="${PONGO_BIN_DIR:-$HOME/.local/bin}"

CHECK_ONLY=false
case "${1:-}" in
  --check) CHECK_ONLY=true ;;
  -h|--help)
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *) echo "unknown option: $1 (use --help)" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

if [ -t 1 ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi

ok()   { echo "  ${GREEN}ok${RESET}    $*"; }
warn() { echo "  ${YELLOW}warn${RESET}  $*"; }
fail() { echo "  ${RED}FAIL${RESET}  $*"; ERRORS=$((ERRORS + 1)); }
info() { echo "        $*"; }

is_wsl() { grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; }

# ---------------------------------------------------------------------------
echo "${BOLD}Prerequisites${RESET}"

if is_wsl; then
  ok "running in WSL2"
elif [ "$(uname -s)" = "Darwin" ]; then
  ok "running on macOS"
else
  ok "running on $(uname -s)"
fi

for tool in git curl realpath; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    fail "$tool not found"
    if [ "$tool" = "realpath" ]; then
      info "macOS: brew install coreutils   |   Debian/Ubuntu: sudo apt install coreutils"
    else
      info "Debian/Ubuntu: sudo apt install $tool"
    fi
  fi
done

if command -v md5sum >/dev/null 2>&1 || command -v gmd5sum >/dev/null 2>&1 || command -v md5 >/dev/null 2>&1; then
  ok "md5 tool"
else
  fail "no md5sum/gmd5sum/md5 found (install coreutils)"
fi

if ! command -v docker >/dev/null 2>&1; then
  fail "docker not found"
  if is_wsl; then
    info "Install Docker Desktop on Windows, enable 'Use the WSL 2 based engine' and"
    info "Settings > Resources > WSL integration for this distro. See docs/prerequisites.md"
  fi
else
  if docker info >/dev/null 2>&1; then
    ok "docker daemon reachable ($(docker version --format '{{.Server.Version}}' 2>/dev/null))"
  else
    fail "docker is installed but the daemon is not reachable"
    if is_wsl; then
      info "Start Docker Desktop and check the WSL integration for this distro."
    else
      info "Start the docker service, and make sure your user is in the 'docker' group."
    fi
  fi
  if docker compose version >/dev/null 2>&1; then
    ok "docker compose ($(docker compose version --short 2>/dev/null))"
  elif command -v docker-compose >/dev/null 2>&1; then
    ok "docker-compose (legacy v1 binary)"
  else
    fail "docker compose not found"
  fi
fi

# Integration tests break when the plugin lives on the Windows filesystem
# (unix sockets can't be created there, see kong-pongo issue #368).
case "$REPO_ROOT" in
  /mnt/[a-zA-Z]/*)
    warn "this repo is on the Windows filesystem ($REPO_ROOT)"
    info "Integration tests will fail there. Clone it inside WSL instead, e.g. ~/GIT/"
    ;;
  *) ok "repo is on the Linux filesystem" ;;
esac

autocrlf="$(git config --get core.autocrlf 2>/dev/null || true)"
if [ "$autocrlf" = "true" ]; then
  warn "git core.autocrlf=true; .gitattributes forces LF for this repo, but other plugin repos may get CRLF"
  info "Consider: git config --global core.autocrlf input"
else
  ok "git core.autocrlf=${autocrlf:-unset}"
fi

# ---------------------------------------------------------------------------
echo
echo "${BOLD}Pongo ${PONGO_VERSION}${RESET}"

installed_version() {
  [ -d "$PONGO_HOME/.git" ] || return 1
  git -C "$PONGO_HOME" describe --tags --exact-match 2>/dev/null
}

current="$(installed_version || true)"

if [ "$CHECK_ONLY" = true ]; then
  if [ -z "$current" ]; then
    fail "Pongo not installed in $PONGO_HOME (run scripts/setup.sh without --check)"
  elif [ "$current" != "$PONGO_VERSION" ]; then
    warn "Pongo $current installed, $PONGO_VERSION expected (run scripts/setup.sh to update)"
  else
    ok "Pongo $current installed in $PONGO_HOME"
  fi
elif [ "$current" = "$PONGO_VERSION" ]; then
  ok "Pongo $current already installed in $PONGO_HOME"
elif [ -d "$PONGO_HOME/.git" ]; then
  echo "  updating $PONGO_HOME from ${current:-unknown} to $PONGO_VERSION"
  if git -C "$PONGO_HOME" fetch --quiet --depth 1 origin "refs/tags/$PONGO_VERSION:refs/tags/$PONGO_VERSION" \
     && git -C "$PONGO_HOME" -c advice.detachedHead=false checkout --quiet "$PONGO_VERSION"; then
    ok "Pongo updated to $PONGO_VERSION"
  else
    fail "could not update Pongo in $PONGO_HOME"
  fi
elif [ -e "$PONGO_HOME" ]; then
  fail "$PONGO_HOME exists but is not a git clone; remove it or set PONGO_HOME"
else
  echo "  cloning $PONGO_REPO ($PONGO_VERSION) into $PONGO_HOME"
  mkdir -p "$(dirname "$PONGO_HOME")"
  if git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$PONGO_VERSION" "$PONGO_REPO" "$PONGO_HOME"; then
    ok "Pongo $PONGO_VERSION cloned"
  else
    fail "could not clone Pongo"
  fi
fi

link="$PONGO_BIN_DIR/pongo"
target="$PONGO_HOME/pongo.sh"
if [ "$CHECK_ONLY" = false ] && [ -f "$target" ]; then
  if [ -L "$link" ] || [ ! -e "$link" ]; then
    mkdir -p "$PONGO_BIN_DIR"
    if [ "$(readlink "$link" 2>/dev/null)" != "$target" ]; then
      ln -sfn "$target" "$link"
      ok "linked $link -> $target"
    else
      ok "$link -> $target"
    fi
  else
    warn "$link exists and is not a symlink; left it alone"
  fi
fi

on_path="$(command -v pongo 2>/dev/null || true)"
if [ -z "$on_path" ]; then
  if [ -f "$target" ]; then
    warn "'pongo' is not on your PATH yet"
    if [ "$PONGO_BIN_DIR" = "$HOME/.local/bin" ] && grep -qs '\.local/bin' "$HOME/.profile"; then
      info "Your ~/.profile already adds ~/.local/bin; open a new terminal (or run: source ~/.profile)."
    else
      info "Add this to ~/.bashrc (or ~/.zshrc) and open a new shell:"
      info "  export PATH=\"$PONGO_BIN_DIR:\$PATH\""
    fi
  fi
elif [ "$(realpath "$on_path")" != "$(realpath "$target" 2>/dev/null)" ]; then
  warn "another pongo is first on your PATH: $on_path"
  info "It will be used instead of $target"
else
  ok "pongo on PATH: $on_path"
fi

# ---------------------------------------------------------------------------
echo
if [ "$ERRORS" -gt 0 ]; then
  echo "${RED}$ERRORS problem(s) found.${RESET} See docs/prerequisites.md and docs/troubleshooting.md."
  exit 1
fi

echo "${GREEN}All set.${RESET} Next: run the example tests from the repo root:"
echo "  pongo run"
