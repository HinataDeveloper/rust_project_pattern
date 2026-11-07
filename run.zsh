#!/usr/bin/env zsh
# Rust project runner (zsh)

### cargo clippy --all-targets --all-features -- -D warnings

emulate -R zsh                       # predictable behavior regardless of user's shell options
setopt err_exit no_unset pipe_fail   # zsh-native equivalent of: set -euo pipefail

# =========================
# Colors (zsh native)
# =========================
autoload -Uz colors && colors

typeset CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_CYAN='' CLR_RESET=''
typeset CARGO_COLOR=never

enable_color() {
  CLR_RED="$fg[red]" CLR_GREEN="$fg[green]" CLR_YELLOW="$fg[yellow]"
  CLR_BLUE="$fg[blue]" CLR_CYAN="$fg[cyan]" CLR_RESET="$reset_color"
  CARGO_COLOR=always
}
disable_color() {
  CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_CYAN='' CLR_RESET=''
  CARGO_COLOR=never
}

# Only color when writing to a terminal; honor NO_COLOR (any non-empty value)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then enable_color; fi

# =========================
# Logging helpers
# =========================
info()    { print -r -- "${CLR_BLUE}[INFO]${CLR_RESET} $*"; }
success() { print -r -- "${CLR_GREEN}[OK]${CLR_RESET} $*"; }
warn()    { print -u2 -r -- "${CLR_YELLOW}[WARN]${CLR_RESET} $*"; }
error()   { print -u2 -r -- "${CLR_RED}[ERROR]${CLR_RESET} $*"; }
die()     { error "$*"; exit 1; }

# Run a command; on failure report which step failed and keep its exit code.
step() {
  local label="$1"; shift
  local -i rc=0
  info "$label"
  "$@" || rc=$?
  if (( rc != 0 )); then
    error "$label failed (exit code $rc)"
    exit $rc
  fi
  success "$label"
}

# =========================
# Help
# =========================
show_help() {
  cat <<'EOF'
Usage:
  ./run.sh <command> [options] [-- program_args...]

Commands:
  fix         Run cargo fix (allows dirty/staged trees)
  check       Run cargo check (warnings are errors)
  clippy      Run cargo clippy (warnings are errors)
  build       Run cargo build (dev, warnings are errors)
  run         Pipeline: clippy -> run   (clippy already type-checks everything)
  release     Pipeline: clippy -> run --release
  test        Run cargo test (extra args are passed to the test harness)
  clean       Run cargo clean
  fmt         Run cargo fmt
  fmt-check   Run cargo fmt --check (no changes, for CI)
  all         fmt -> fix -> clippy -> test -> run

Options:
  --bin <name>        Choose a specific binary (multi-bin projects)
  --package <name>    Choose a package (workspaces). Default: auto from Cargo.toml
  --no-clear          Don't clear the terminal
  --no-color          Disable colored output (same as NO_COLOR=1)
  -h, --help          Show this help

Examples:
  ./run.sh check
  ./run.sh run hello 123
  ./run.sh run -- --flag value
  ./run.sh run --bin server -- --port 8080
  ./run.sh release --bin cli -- input.txt
  ./run.sh test my_test_name
  NO_COLOR=1 ./run.sh all
EOF
}

# =========================
# Argument parsing
# =========================
typeset COMMAND=help
if (( $# > 0 )); then
  COMMAND="$1"
  shift
fi

integer NO_CLEAR=0
typeset BIN_NAME='' PACKAGE_NAME=''
typeset -a PROGRAM_ARGS=()

while (( $# > 0 )); do
  case "$1" in
    --bin)
      (( $# >= 2 )) || die "--bin requires a value"
      BIN_NAME="$2"; shift 2 ;;
    --package)
      (( $# >= 2 )) || die "--package requires a value"
      PACKAGE_NAME="$2"; shift 2 ;;
    --no-clear) NO_CLEAR=1; shift ;;
    --no-color) disable_color; shift ;;
    -h|--help)  COMMAND=help; shift ;;
    --)         shift; PROGRAM_ARGS+=("$@"); break ;;
    *)          PROGRAM_ARGS+=("$1"); shift ;;
  esac
done

# Help must work anywhere, even outside a Rust project
case "$COMMAND" in
  help|--help|-h|"") show_help; exit 0 ;;
esac

# =========================
# Environment checks
# =========================
(( $+commands[cargo] )) || die "Required command not found: cargo"
[[ -f Cargo.toml ]]     || die "Cargo.toml not found (run this in your Rust project root)"

get_project_name() {
  # [package].name from Cargo.toml (empty for a virtual workspace root)
  awk '
    /^\[package\]/ { in_pkg = 1; next }
    /^\[/          { in_pkg = 0 }
    in_pkg && /^name[[:space:]]*=/ {
      sub(/^name[[:space:]]*=[[:space:]]*"/, ""); sub(/".*/, ""); print; exit
    }
  ' Cargo.toml
}

typeset AUTO_PROJECT_NAME
AUTO_PROJECT_NAME="$(get_project_name)"
[[ -n "$PACKAGE_NAME" ]] || PACKAGE_NAME="$AUTO_PROJECT_NAME"

if (( NO_CLEAR == 0 )) && [[ -t 1 ]]; then clear; fi

info "Project: ${CLR_CYAN}${AUTO_PROJECT_NAME:-<workspace>}${CLR_RESET}"
[[ -z "$PACKAGE_NAME" ]] || info "Package: ${CLR_CYAN}${PACKAGE_NAME}${CLR_RESET}"
[[ -z "$BIN_NAME"     ]] || info "Bin:     ${CLR_CYAN}${BIN_NAME}${CLR_RESET}"

# Common cargo flags
typeset -a CARGO_ARGS=(--color "$CARGO_COLOR")
[[ -z "$PACKAGE_NAME" ]] || CARGO_ARGS+=(--package "$PACKAGE_NAME")
[[ -z "$BIN_NAME"     ]] || CARGO_ARGS+=(--bin "$BIN_NAME")

# IMPORTANT: use the *same* RUSTFLAGS for every cargo call. Cargo treats a change
# in RUSTFLAGS as a new configuration and recompiles everything, so the original
# script rebuilt the project again in its final `cargo run`.
# User-defined RUSTFLAGS are preserved and "-D warnings" is appended.
typeset STRICT_RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-D warnings"
typeset -a STRICT=(env "RUSTFLAGS=$STRICT_RUSTFLAGS")

# =========================
# Commands
# =========================
cmd_fix()       { step "cargo fix" cargo fix --allow-dirty --allow-staged "${CARGO_ARGS[@]}"; }
cmd_check()     { step "cargo check" "${STRICT[@]}" cargo check "${CARGO_ARGS[@]}"; }
cmd_clippy()    { step "cargo clippy" "${STRICT[@]}" cargo clippy "${CARGO_ARGS[@]}" -- -D warnings; }
cmd_build()     { step "cargo build" "${STRICT[@]}" cargo build "${CARGO_ARGS[@]}"; }
cmd_test()      { step "cargo test"  "${STRICT[@]}" cargo test "${CARGO_ARGS[@]}" -- "${PROGRAM_ARGS[@]}"; }
cmd_clean()     { step "cargo clean" cargo clean; }
cmd_fmt()       { step "cargo fmt" cargo fmt; }
cmd_fmt_check() { step "cargo fmt --check" cargo fmt --check; }

cmd_run() {
  info "Pipeline: clippy -> run"
  cmd_clippy
  step "run (dev)" "${STRICT[@]}" cargo run "${CARGO_ARGS[@]}" -- "${PROGRAM_ARGS[@]}"
}

cmd_release() {
  info "Pipeline (release): clippy -> run --release"
  cmd_clippy
  step "run (release)" "${STRICT[@]}" cargo run --release "${CARGO_ARGS[@]}" -- "${PROGRAM_ARGS[@]}"
}

cmd_all() {
  cmd_fmt
  cmd_fix
  cmd_clippy
  cmd_test
  cmd_run
}

# =========================
# Dispatch
# =========================
case "$COMMAND" in
  fix)       cmd_fix ;;
  check)     cmd_check ;;
  clippy)    cmd_clippy ;;
  build)     cmd_build ;;
  run)       cmd_run ;;
  release)   cmd_release ;;
  test)      cmd_test ;;
  clean)     cmd_clean ;;
  fmt)       cmd_fmt ;;
  fmt-check) cmd_fmt_check ;;
  all)       cmd_all ;;
  *)
    error "Unknown command: $COMMAND"
    print ""
    show_help
    exit 2
    ;;
esac

info "Finished in ${SECONDS}s"
