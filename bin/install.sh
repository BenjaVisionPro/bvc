#!/usr/bin/env bash
set -euo pipefail

BVC_REPO_URL="${BVC_REPO_URL:-https://github.com/BenjaVisionPro/bvc.git}"
BVC_REPO_BRANCH="${BVC_REPO_BRANCH:-main}"
BVC_PREFIX="/opt"
BVC_SKIP_PATH_UPDATE="${BVC_SKIP_PATH_UPDATE:-0}"

usage() {
  cat <<'USAGE'
BenjaVision Catalyst installer

Usage:
  install.sh [--prefix <path>] [--no-path-update]

Examples:
  curl -fsSL https://raw.githubusercontent.com/BenjaVisionPro/bvc/refs/heads/main/bin/install.sh | bash -s
  curl -fsSL https://raw.githubusercontent.com/BenjaVisionPro/bvc/refs/heads/main/bin/install.sh | bash -s -- --prefix "$HOME/catalyst"

Options:
  --prefix <path>       Install under <path>/bvc. Default: /opt
  --no-path-update      Do not edit the shell profile
  -h, --help            Show this help
USAGE
}

info() { printf '%s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

expand_path() {
  case "$1" in
    '') fail "empty path" ;;
    ~) printf '%s\n' "$HOME" ;;
    ~/*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || fail "--prefix requires a path"
      BVC_PREFIX="$2"
      shift 2
      ;;
    --prefix=*)
      BVC_PREFIX="${1#--prefix=}"
      shift
      ;;
    --no-path-update)
      BVC_SKIP_PATH_UPDATE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "$(uname -s 2>/dev/null || true)" in
  Darwin|Linux)
    ;;
  MINGW*|MSYS*|CYGWIN*)
    fail "native Windows shells are not supported. Use Linux on Windows/WSL instead."
    ;;
  *)
    fail "unsupported platform: $(uname -s 2>/dev/null || echo unknown)"
    ;;
esac

command -v git >/dev/null 2>&1 || fail "git is required"

BVC_PREFIX="$(expand_path "$BVC_PREFIX")"
BVC_INSTALL_DIR="${BVC_PREFIX%/}/bvc"
BVC_BIN_DIR="$BVC_INSTALL_DIR/bin"

sudo_if_needed() {
  if "$@" 2>/dev/null; then
    return 0
  fi

  command -v sudo >/dev/null 2>&1 || fail "permission denied and sudo is not available: $*"
  sudo "$@"
}

ensure_writable_install_dir() {
  if [ -e "$BVC_INSTALL_DIR" ]; then
    if [ ! -w "$BVC_INSTALL_DIR" ]; then
      command -v sudo >/dev/null 2>&1 || fail "$BVC_INSTALL_DIR is not writable and sudo is not available"
      sudo chown -R "$(id -u):$(id -g)" "$BVC_INSTALL_DIR"
    fi
    return 0
  fi

  parent="$(dirname "$BVC_INSTALL_DIR")"
  if [ -w "$parent" ]; then
    mkdir -p "$BVC_INSTALL_DIR"
  else
    command -v sudo >/dev/null 2>&1 || fail "$parent is not writable and sudo is not available"
    sudo mkdir -p "$BVC_INSTALL_DIR"
    sudo chown "$(id -u):$(id -g)" "$BVC_INSTALL_DIR"
  fi
}

install_or_update_repo() {
  ensure_writable_install_dir

  if [ -d "$BVC_INSTALL_DIR/.git" ]; then
    info "Updating bvc in $BVC_INSTALL_DIR"
    git -C "$BVC_INSTALL_DIR" fetch --quiet origin "$BVC_REPO_BRANCH"
    git -C "$BVC_INSTALL_DIR" checkout --quiet "$BVC_REPO_BRANCH"
    git -C "$BVC_INSTALL_DIR" pull --ff-only --quiet origin "$BVC_REPO_BRANCH"
  elif [ -z "$(find "$BVC_INSTALL_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
    info "Installing bvc into $BVC_INSTALL_DIR"
    git clone --quiet --branch "$BVC_REPO_BRANCH" "$BVC_REPO_URL" "$BVC_INSTALL_DIR"
  else
    fail "$BVC_INSTALL_DIR already exists and is not an empty directory or git checkout"
  fi

  chmod +x "$BVC_BIN_DIR"/*.sh "$BVC_BIN_DIR/bvc" 2>/dev/null || true
}

profile_file_for_shell() {
  shell_name="${SHELL##*/}"
  case "$shell_name" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) printf '%s\n' "$HOME/.bashrc" ;;
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    *)    printf '%s\n' "$HOME/.profile" ;;
  esac
}

path_already_available() {
  case ":${PATH}:" in
    *":$BVC_BIN_DIR:"*) return 0 ;;
    *) return 1 ;;
  esac
}

profile_already_mentions_path() {
  profile_file="$1"
  [ -f "$profile_file" ] || return 1
  grep -F "$BVC_BIN_DIR" "$profile_file" >/dev/null 2>&1
}

add_bin_to_path() {
  [ "$BVC_SKIP_PATH_UPDATE" = "1" ] && return 0
  path_already_available && return 0

  profile_file="$(profile_file_for_shell)"
  mkdir -p "$(dirname "$profile_file")"

  if profile_already_mentions_path "$profile_file"; then
    return 0
  fi

  shell_name="${SHELL##*/}"
  {
    printf '\n# BenjaVision Catalyst Toolkit\n'
    if [ "$shell_name" = "fish" ]; then
      printf 'fish_add_path %s\n' "$BVC_BIN_DIR"
    else
      printf 'export PATH="%s:$PATH"\n' "$BVC_BIN_DIR"
    fi
  } >> "$profile_file"

  info "Added $BVC_BIN_DIR to PATH in $profile_file"
}

install_or_update_repo
add_bin_to_path

info "bvc installed successfully."
info "Install directory: $BVC_INSTALL_DIR"

if ! path_already_available; then
  info "Open a new terminal, or run:"
  if [ "${SHELL##*/}" = "fish" ]; then
    info "  fish_add_path $BVC_BIN_DIR"
  else
    info "  export PATH=\"$BVC_BIN_DIR:\$PATH\""
  fi
fi
