#!/usr/bin/env zsh
# Enable strict execution mode
set -euo pipefail

# =========================
# Zsh Native Colors
# =========================
autoload -Uz colors && colors

if [[ "${NO_COLOR:-0}" == "1" ]]; then
  CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_CYAN='' CLR_RESET=''
else
  CLR_RED="$fg[red]"
  CLR_GREEN="$fg[green]"
  CLR_YELLOW="$fg[yellow]"
  CLR_BLUE="$fg[blue]"
  CLR_CYAN="$fg[cyan]"
  CLR_RESET="$reset_color"
fi

# =========================
# Logging helpers
# =========================
info()    { print -r -- "${CLR_BLUE}[INFO]${CLR_RESET} $*"; }
success() { print -r -- "${CLR_GREEN}[OK]${CLR_RESET} $*"; }
warn()    { print -r -- "${CLR_YELLOW}[WARN]${CLR_RESET} $*"; }
error()   { print -u2 -r -- "${CLR_RED}[ERROR]${CLR_RESET} $*"; }
die()     { error "$*"; exit 1; }

# =========================
# Checks
# =========================
require_file() {
  local target_file="$1"
  [[ -f "$target_file" ]] || die "File not found: $target_file (run this in your Rust project root)"
}

require_command() {
  local cmd="$1"
  (( $+commands[$cmd] )) || die "Required command not found: $cmd"
}

# =========================
# Project detection
# =========================
get_project_name() {
  # Extract [package].name from Cargo.toml using awk
  awk -F '"' '
    /^\[package\]/ { in_package=1; next }
    /^\[/ && !/^\[package\]/ { in_package=0 }
    in_package && /^name[[:space:]]*=/ { print $2; exit }
  ' Cargo.toml
}

# =========================
# Help
# =========================
show_help() {
  cat <<'EOF'
Usage:
  ./run.sh <command> [options] [-- program_args...]

Commands:
  fix         Run cargo fix (safe default: allow dirty)
  check       Run cargo check (denies warnings)
  clippy      Run cargo clippy (denies warnings)
  build       Run cargo build (dev, denies warnings)
  run         Pipeline: check -> clippy -> build -> run (fails on any warning)
  release     Pipeline: check -> clippy -> build --release -> run --release
  test        Run cargo test
  clean       Run cargo clean
  fmt         Run cargo fmt
  all         Run fmt + fix + check + clippy + test + run (dev)

Common options (for run/release):
  --bin <name>        Choose a specific binary (for multi-bin projects)
  --package <name>    Choose a specific package (workspace). Default: auto from Cargo.toml
  --no-clear          Don't clear terminal
  --no-color          Disable colored output (same as NO_COLOR=1)

Examples:
  ./run.sh check
  ./run.sh run
  ./run.sh run hello 123
  ./run.sh run -- --flag value
  ./run.sh run --bin server -- --port 8080
  ./run.sh release --bin cli -- input.txt
  NO_COLOR=1 ./run.sh all
EOF
}

# =========================
# Argument parsing
# =========================
COMMAND="${1:-help}"
shift || true

integer NO_CLEAR=0
BIN_NAME=""
PACKAGE_NAME=""
typeset -a PROGRAM_ARGS=()

while (( $# > 0 )); do
  case "$1" in
    --bin)
      (( $# >= 2 )) || die "--bin requires a value"
      BIN_NAME="$2"
      shift 2
      ;;
    --package)
      (( $# >= 2 )) || die "--package requires a value"
      PACKAGE_NAME="$2"
      shift 2
      ;;
    --no-clear)
      NO_CLEAR=1
      shift
      ;;
    --no-color)
      CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_CYAN='' CLR_RESET=''
      shift
      ;;
    --help|-h)
      COMMAND="help"
      shift
      ;;
    --)
      shift
      PROGRAM_ARGS+=("$@")
      break
      ;;
    *)
      PROGRAM_ARGS+=("$1")
      shift
      ;;
  esac
done

# =========================
# Environment checks
# =========================
require_command cargo
require_file Cargo.toml

AUTO_PROJECT_NAME="$(get_project_name || true)"
[[ -n "${AUTO_PROJECT_NAME:-}" ]] || die "Could not extract [package].name from Cargo.toml"

if [[ -z "${PACKAGE_NAME:-}" ]]; then
  PACKAGE_NAME="$AUTO_PROJECT_NAME"
fi

if (( NO_CLEAR == 0 )); then
  clear 2>/dev/null || true
fi

info "Project: ${CLR_CYAN}${AUTO_PROJECT_NAME}${CLR_RESET}"
info "Package: ${CLR_CYAN}${PACKAGE_NAME}${CLR_RESET}"
if [[ -n "${BIN_NAME:-}" ]]; then
  info "Bin:     ${CLR_CYAN}${BIN_NAME}${CLR_RESET}"
fi

# Build common cargo flags array
typeset -a CARGO_SEL_ARGS=(--package "$PACKAGE_NAME")
if [[ -n "${BIN_NAME:-}" ]]; then
  CARGO_SEL_ARGS+=(--bin "$BIN_NAME")
fi

# =========================
# Command implementations
# =========================
cmd_fix() {
  info "Running: cargo fix"
  cargo fix --allow-dirty
  success "cargo fix done"
}

cmd_check() {
  info "Running: cargo check (strict: -D warnings)"
  RUSTFLAGS="-D warnings" cargo check "${CARGO_SEL_ARGS[@]}"
  success "cargo check passed (clean)"
}

cmd_clippy() {
  info "Running: cargo clippy (strict: -D warnings)"
  cargo clippy "${CARGO_SEL_ARGS[@]}" -- -D warnings
  success "cargo clippy passed (clean)"
}

cmd_build() {
  info "Running: cargo build (dev, strict: -D warnings)"
  RUSTFLAGS="-D warnings" cargo build "${CARGO_SEL_ARGS[@]}"
  success "cargo build done"
}

cmd_run() {
  info "Pipeline: check -> clippy -> build -> execute"

  # Step 1: cargo check (zero warnings)
  cmd_check

  # Step 2: cargo clippy (zero warnings)
  cmd_clippy

  # Step 3: cargo build (dev mode with zero warnings)
  cmd_build

  # Step 4: Run application
  info "Running: application binary (dev)"
  cargo run --color=always "${CARGO_SEL_ARGS[@]}" --profile dev -- "${PROGRAM_ARGS[@]}"
  success "execution finished successfully"
}

cmd_release() {
  info "Pipeline (Release): check -> clippy -> build --release -> execute"

  cmd_check
  cmd_clippy

  info "Building binary (release mode)"
  RUSTFLAGS="-D warnings" cargo build --release "${CARGO_SEL_ARGS[@]}"

  info "Running: application binary (release)"
  cargo run --color=always "${CARGO_SEL_ARGS[@]}" --release -- "${PROGRAM_ARGS[@]}"
  success "release execution finished successfully"
}

cmd_test() {
  info "Running: cargo test"
  cargo test "${CARGO_SEL_ARGS[@]}"
  success "cargo test done"
}

cmd_clean() {
  info "Running: cargo clean"
  cargo clean
  success "cargo clean done"
}

cmd_fmt() {
  info "Running: cargo fmt"
  cargo fmt
  success "cargo fmt done"
}

cmd_all() {
  cmd_fmt
  cmd_fix
  cmd_run
  cmd_test
}

# =========================
# Dispatch
# =========================
case "$COMMAND" in
  fix)     cmd_fix ;;
  check)   cmd_check ;;
  clippy)  cmd_clippy ;;
  build)   cmd_build ;;
  run)     cmd_run ;;
  release) cmd_release ;;
  test)    cmd_test ;;
  clean)   cmd_clean ;;
  fmt)     cmd_fmt ;;
  all)     cmd_all ;;
  help|--help|-h|"") show_help ;;
  *)
    error "Unknown command: $COMMAND"
    print ""
    show_help
    exit 2
    ;;
esac
