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

# NOTE: the --help option prints lines 3-12 of this file (the block above).
#       Keep that block at the top when editing this script.

# `set -u` makes the script stop with an error when it uses a variable that was
# never set, instead of silently treating it as empty. This catches typos early.
set -u

# --- Settings ---------------------------------------------------------------
# `${NAME:-default}` means: use the environment variable NAME if you set it,
# otherwise use the default after ":-". So you can override these when running
# the script, e.g.:  PONGO_VERSION=2.28.1 scripts/setup.sh
#   PONGO_VERSION : Pongo release (git tag) to install
#   PONGO_REPO    : where Pongo is downloaded from
#   PONGO_HOME    : folder Pongo is cloned into
#   PONGO_BIN_DIR : folder where the 'pongo' command is put
PONGO_VERSION="${PONGO_VERSION:-2.29.0}"
PONGO_REPO="https://github.com/Kong/kong-pongo.git"
PONGO_HOME="${PONGO_HOME:-$HOME/.local/share/kong-pongo}"
PONGO_BIN_DIR="${PONGO_BIN_DIR:-$HOME/.local/bin}"

# --- Command-line options ---------------------------------------------------
# Look at the first argument ($1) given to the script:
#   --check      only report what is missing, don't install anything
#   -h / --help  print the usage text from the top of this file and stop
#   (nothing)    normal run: check everything and install/update Pongo
#   anything else is an error (exit code 2)
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

# The repo root is the parent folder of the folder this script is in
# (scripts/ -> repo root), no matter from where you start the script.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Counts the problems found; the script exits with an error if this is > 0.
ERRORS=0

# --- Output helpers ---------------------------------------------------------
# Colors only when the output goes to a terminal (`-t 1` = "is stdout a
# terminal?"). When the output is redirected to a file, no color codes are used.
if [ -t 1 ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi

# Small functions to print a result line. `$*` is all the text passed to them.
#   ok   : check passed
#   warn : not blocking, but worth knowing
#   fail : blocking problem; also adds 1 to the ERRORS counter
#   info : extra explanation/hint below the previous line
ok()   { echo "  ${GREEN}ok${RESET}    $*"; }
warn() { echo "  ${YELLOW}warn${RESET}  $*"; }
fail() { echo "  ${RED}FAIL${RESET}  $*"; ERRORS=$((ERRORS + 1)); }
info() { echo "        $*"; }

# Returns "true" when running inside WSL (Windows Subsystem for Linux): the
# Linux kernel version string of WSL contains the word "microsoft".
is_wsl() { grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; }

# ===========================================================================
# Part 1: prerequisites
# ===========================================================================
echo "${BOLD}Prerequisites${RESET}"

# Show which platform we are on (informational only). `uname -s` prints the
# operating system name, "Darwin" means macOS.
if is_wsl; then
  ok "running in WSL2"
elif [ "$(uname -s)" = "Darwin" ]; then
  ok "running on macOS"
else
  ok "running on $(uname -s)"
fi

# Command-line tools Pongo needs. `command -v <tool>` succeeds when the tool is
# installed (found on the PATH); `>/dev/null 2>&1` hides its output.
# For every missing tool, print how to install it.
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

# Pongo also needs a tool to calculate MD5 checksums. Its name differs per
# platform (md5sum on Linux, gmd5sum or md5 on macOS); any one of them is fine.
if command -v md5sum >/dev/null 2>&1 || command -v gmd5sum >/dev/null 2>&1 || command -v md5 >/dev/null 2>&1; then
  ok "md5 tool"
else
  fail "no md5sum/gmd5sum/md5 found (install coreutils)"
fi

# Docker checks, in three steps:
#   1. is the `docker` command installed at all?
#   2. is the Docker engine (daemon) running and reachable? (`docker info`)
#   3. is Docker Compose available? (new `docker compose` or old `docker-compose`)
# Pongo uses Docker to run Kong, Postgres and the mock services.
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
# In WSL, the Windows drives are mounted under /mnt/c, /mnt/d, ... so a repo
# path starting with /mnt/<letter>/ is on Windows. This is only a warning.
case "$REPO_ROOT" in
  /mnt/[a-zA-Z]/*)
    warn "this repo is on the Windows filesystem ($REPO_ROOT)"
    info "Integration tests will fail there. Clone it inside WSL instead, e.g. ~/GIT/"
    ;;
  *) ok "repo is on the Linux filesystem" ;;
esac

# Git's "autocrlf" setting: when it is "true", git converts files to Windows
# line endings (CRLF) on checkout, which breaks shell scripts. This repo is
# protected by its .gitattributes file, but other plugin repos may not be,
# so we warn about it. (`|| true` keeps going when the setting doesn't exist.)
autocrlf="$(git config --get core.autocrlf 2>/dev/null || true)"
if [ "$autocrlf" = "true" ]; then
  warn "git core.autocrlf=true; .gitattributes forces LF for this repo, but other plugin repos may get CRLF"
  info "Consider: git config --global core.autocrlf input"
else
  ok "git core.autocrlf=${autocrlf:-unset}"
fi

# ===========================================================================
# Part 2: install (or check) Pongo
# ===========================================================================
echo
echo "${BOLD}Pongo ${PONGO_VERSION}${RESET}"

# Prints the Pongo version that is currently installed in PONGO_HOME, by asking
# git which release tag is checked out there. Prints nothing (and "fails")
# when Pongo isn't installed yet, or when no exact release tag is checked out.
installed_version() {
  [ -d "$PONGO_HOME/.git" ] || return 1
  git -C "$PONGO_HOME" describe --tags --exact-match 2>/dev/null
}

# Remember the installed version (empty when not installed).
current="$(installed_version || true)"

# Decide what to do, from top to bottom; only the first matching case runs:
#   1. --check given            -> only report the state, change nothing
#   2. right version installed  -> nothing to do
#   3. other version installed  -> download the wanted release and switch to it
#   4. folder exists, no git    -> don't touch it, report a problem
#   5. not installed            -> download (clone) Pongo at the wanted release
# `--depth 1` downloads only that one release instead of the full git history.
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

# Make the `pongo` command available: create a shortcut (symbolic link)
#   ~/.local/bin/pongo  ->  ~/.local/share/kong-pongo/pongo.sh
# Skipped with --check, or when the Pongo download failed.
# An existing link is updated; a real file with the same name is never
# overwritten (it may be something else the user installed).
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

# Check that typing `pongo` in a terminal runs *this* Pongo. The PATH is the
# list of folders your shell searches for commands. Three possible outcomes:
#   - pongo not found on the PATH  -> explain how to add ~/.local/bin to it
#   - a different pongo is found   -> warn, because that one would be used
#   - our pongo is found           -> all good
# `realpath` resolves links, so we compare the real files behind them.
on_path="$(command -v pongo 2>/dev/null || true)"
if [ -z "$on_path" ]; then
  if [ -f "$target" ]; then
    warn "'pongo' is not on your PATH yet"
    # Ubuntu's default ~/.profile already adds ~/.local/bin to the PATH when
    # that folder exists, so a new terminal is enough in that case.
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

# ===========================================================================
# Part 3: summary
# ===========================================================================
# Exit code 1 when any check failed (useful when other scripts call this one),
# exit code 0 (success) otherwise. Warnings don't count as failures.
echo
if [ "$ERRORS" -gt 0 ]; then
  echo "${RED}$ERRORS problem(s) found.${RESET} See docs/prerequisites.md and docs/troubleshooting.md."
  exit 1
fi

echo "${GREEN}All set.${RESET} Next: run the example tests from the repo root:"
echo "  pongo run"
