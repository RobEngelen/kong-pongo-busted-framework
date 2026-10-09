#!/usr/bin/env bash
#
# Runs the Pongo tests of plugin projects that live outside this repo.
#
#   scripts/test-plugin.sh [options] DIR [DIR...] [-- busted options/spec files]
#
# DIR is a plugin project root: it contains kong/plugins/<name>/handler.lua and a
# spec/ folder. Windows paths (C:\...) work too in WSL. Examples:
#
#   scripts/test-plugin.sh ~/GIT/my-plugin
#   scripts/test-plugin.sh /mnt/c/Users/me/repos/kong/plugins/*
#   scripts/test-plugin.sh ~/GIT/my-plugin -- --tags=off ./spec/my-plugin/10-integration_spec.lua
#   KONG_VERSION=3.10.0.14 KONG_LICENSE_DATA="$(cat ~/kong-license.json)" scripts/test-plugin.sh ~/GIT/my-plugin
#
# On WSL, plugins on the Windows filesystem (/mnt/c/...) are copied to a staging
# folder on the Linux filesystem first, because Kong's integration tests can't
# run on a Windows mount (kong-pongo issue #368). The original is never modified.
#
# Options:
#   --keep-logs   keep Kong's ./servroot (and logs/error.log) after the tests
#   --clean       remove all staging folders and exit
#   -h, --help    show this help

set -u

STAGE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/kong-pongo-framework/stage"

if [ -t 1 ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi

usage() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "${RED}error:${RESET} $*" >&2; exit 2; }
is_wsl() { grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; }

# --- arguments --------------------------------------------------------------
DIRS=()
BUSTED_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --keep-logs) export KONG_TEST_DONT_CLEAN=true ;;
    --clean)
      [ -d "$STAGE_ROOT" ] || { echo "nothing to clean"; exit 0; }
      # Kong creates files as root/nobody inside the container, so remove them from a container too.
      docker run --rm -v "$STAGE_ROOT:/stage" busybox:1.37 sh -c 'rm -rf /stage/* /stage/.[!.]*' \
        && rmdir "$STAGE_ROOT" 2>/dev/null
      echo "removed $STAGE_ROOT"
      exit 0
      ;;
    --) shift; BUSTED_ARGS=("$@"); break ;;
    -*) die "unknown option $1 (use --help)" ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done

[ ${#DIRS[@]} -gt 0 ] || { usage; exit 2; }
command -v pongo >/dev/null 2>&1 || die "pongo not found on PATH; run scripts/setup.sh first"

# --- helpers ----------------------------------------------------------------
to_linux_path() {
  local p="$1"
  case "$p" in
    [A-Za-z]:\\*|[A-Za-z]:/*)
      command -v wslpath >/dev/null 2>&1 || die "Windows path given, but wslpath is not available: $p"
      p="$(wslpath -u "$p")"
      ;;
  esac
  realpath "$p" 2>/dev/null || die "folder not found: $1"
}

on_windows_fs() {
  is_wsl || return 1
  case "$1" in /mnt/[a-zA-Z]/*) return 0 ;; esac
  local fstype
  fstype="$(findmnt -n -o FSTYPE -T "$1" 2>/dev/null)"
  [ "$fstype" = "9p" ] || [ "$fstype" = "drvfs" ] || [ "$fstype" = "v9fs" ]
}

stage() {
  local src="$1" dest="$2"
  mkdir -p "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude=/servroot/ --exclude=/.git/ --exclude='/luacov.*' "$src"/ "$dest"/
  else
    find "$dest" -mindepth 1 -maxdepth 1 ! -name servroot -exec rm -rf {} +
    tar -C "$src" --exclude=./servroot --exclude=./.git -cf - . | tar -C "$dest" -xf -
  fi
  # Windows line endings break shell scripts, e.g. the .pongo/pongo-setup.sh hook
  local f
  for f in "$dest"/.pongo/*.sh; do
    [ -f "$f" ] && sed -i 's/\r$//' "$f"
  done
}

# --- run --------------------------------------------------------------------
FAILED=()
PASSED=()
SKIPPED=()

for arg in "${DIRS[@]}"; do
  dir="$(to_linux_path "$arg")" || exit 2
  name="$(basename "$dir")"
  echo
  echo "${BOLD}=== $name${RESET}  ($dir)"

  if ! ls "$dir"/kong/plugins/*/handler.lua >/dev/null 2>&1; then
    echo "${YELLOW}skipped:${RESET} no kong/plugins/<name>/handler.lua found, not a plugin project"
    SKIPPED+=("$name")
    continue
  fi

  workdir="$dir"
  if on_windows_fs "$dir"; then
    hash="$(printf '%s' "$dir" | md5sum | cut -c1-8)"
    workdir="$STAGE_ROOT/$name-$hash"
    echo "Windows filesystem detected, testing a copy in: $workdir"
    stage "$dir" "$workdir"
  fi

  if [ ${#BUSTED_ARGS[@]} -gt 0 ]; then
    (cd "$workdir" && pongo run -- "${BUSTED_ARGS[@]}")
  else
    (cd "$workdir" && pongo run)
  fi
  status=$?

  log="$workdir/servroot/logs/error.log"
  if [ -f "$log" ]; then
    if [ $status -ne 0 ]; then
      echo
      echo "${BOLD}--- last 50 lines of Kong's error.log ---${RESET}"
      tail -n 50 "$log"
    fi
    echo "Kong log: $log"
    is_wsl && command -v wslpath >/dev/null 2>&1 && echo "          $(wslpath -w "$log")"
  elif [ $status -ne 0 ]; then
    echo "Tip: rerun with --keep-logs to keep Kong's error.log for debugging."
  fi

  if [ $status -eq 0 ]; then PASSED+=("$name"); else FAILED+=("$name"); fi

  # With several plugins, stop each environment (postgres, ...) before the next one.
  if [ ${#DIRS[@]} -gt 1 ]; then
    (cd "$workdir" && pongo down >/dev/null 2>&1)
  fi
done

echo
echo "${BOLD}=== Summary${RESET}"
[ ${#PASSED[@]} -gt 0 ] && echo "${GREEN}passed:${RESET} ${PASSED[*]}"
[ ${#FAILED[@]} -gt 0 ] && echo "${RED}failed:${RESET} ${FAILED[*]}"
[ ${#SKIPPED[@]} -gt 0 ] && echo "${YELLOW}skipped:${RESET} ${SKIPPED[*]}"
if [ ${#DIRS[@]} -eq 1 ] && [ -n "${workdir:-}" ]; then
  echo "Stop the test environment when you're done: (cd \"$workdir\" && pongo down)"
fi

[ ${#FAILED[@]} -eq 0 ] && [ ${#PASSED[@]} -gt 0 ]
