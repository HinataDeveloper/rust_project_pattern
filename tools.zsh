#!/usr/bin/env zsh
# ==============================================================================
# tools.zsh - one script for all my Rust-project helpers
#
#   tools.zsh run <cmd> ...      (was run.zsh)    cargo runner / pipelines
#   tools.zsh ncopy <cmd> ...    (was ncopy6.zsh) src snapshot + template reset
#   tools.zsh commit "message"   (was commit.zsh) ncopy run + git add + commit
#   tools.zsh grv                (was grv.zsh)    write rust_version.txt
#   tools.zsh cb [paths...]      (was cb.zsh)     codebook-lsp lint
# ==============================================================================

emulate -R zsh                       # predictable behavior regardless of user's shell options
setopt err_exit no_unset pipe_fail   # zsh-native equivalent of: set -euo pipefail

# ==============================================================================
# Shared: colors
# ==============================================================================
autoload -Uz colors && colors

typeset CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_CYAN='' CLR_BOLD='' CLR_RESET=''
typeset CARGO_COLOR=never

enable_color() {
  CLR_RED="$fg[red]" CLR_GREEN="$fg[green]" CLR_YELLOW="$fg[yellow]"
  CLR_BLUE="$fg[blue]" CLR_CYAN="$fg[cyan]" CLR_BOLD="$bold_color" CLR_RESET="$reset_color"
  CARGO_COLOR=always
}
disable_color() {
  CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_CYAN='' CLR_BOLD='' CLR_RESET=''
  CARGO_COLOR=never
}

# Only color when writing to a terminal; honor NO_COLOR (any non-empty value)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then enable_color; fi

# ==============================================================================
# Shared: logging helpers
# ==============================================================================
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

clear_screen() { if [[ -t 1 ]]; then clear; fi; }

# ==============================================================================
# TOOL 1: run  (cargo runner)
# ==============================================================================
run_help() {
  cat <<'EOF'
Usage:
  tools.zsh run <command> [options] [-- program_args...]

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
  tools.zsh run check
  tools.zsh run run hello 123
  tools.zsh run run -- --flag value
  tools.zsh run run --bin server -- --port 8080
  tools.zsh run release --bin cli -- input.txt
  tools.zsh run test my_test_name
  NO_COLOR=1 tools.zsh run all
EOF
}

run_project_name() {
  # [package].name from Cargo.toml (empty for a virtual workspace root)
  awk '
    /^\[package\]/ { in_pkg = 1; next }
    /^\[/          { in_pkg = 0 }
    in_pkg && /^name[[:space:]]*=/ {
      sub(/^name[[:space:]]*=[[:space:]]*"/, ""); sub(/".*/, ""); print; exit
    }
  ' Cargo.toml
}

# The run_* command functions below read CARGO_ARGS, STRICT and PROGRAM_ARGS,
# which are local variables of tool_run (zsh uses dynamic scoping).
run_fix()       { step "cargo fix" cargo fix --allow-dirty --allow-staged "${CARGO_ARGS[@]}"; }
run_check()     { step "cargo check" "${STRICT[@]}" cargo check "${CARGO_ARGS[@]}"; }
run_clippy()    { step "cargo clippy" "${STRICT[@]}" cargo clippy "${CARGO_ARGS[@]}" -- -D warnings; }
run_build()     { step "cargo build" "${STRICT[@]}" cargo build "${CARGO_ARGS[@]}"; }
run_test()      { step "cargo test"  "${STRICT[@]}" cargo test "${CARGO_ARGS[@]}" -- "${PROGRAM_ARGS[@]}"; }
run_clean()     { step "cargo clean" cargo clean; }
run_fmt()       { step "cargo fmt" cargo fmt; }
run_fmt_check() { step "cargo fmt --check" cargo fmt --check; }

run_run() {
  info "Pipeline: clippy -> run"
  run_clippy
  step "run (dev)" "${STRICT[@]}" cargo run "${CARGO_ARGS[@]}" -- "${PROGRAM_ARGS[@]}"
}

run_release() {
  info "Pipeline (release): clippy -> run --release"
  run_clippy
  step "run (release)" "${STRICT[@]}" cargo run --release "${CARGO_ARGS[@]}" -- "${PROGRAM_ARGS[@]}"
}

run_all() {
  run_fmt
  run_fix
  run_clippy
  run_test
  run_run
}

tool_run() {
  local COMMAND=help
  if (( $# > 0 )); then
    COMMAND="$1"
    shift
  fi

  local -i NO_CLEAR=0
  local BIN_NAME='' PACKAGE_NAME=''
  local -a PROGRAM_ARGS=()

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
    help|--help|-h|"") run_help; return 0 ;;
  esac

  # Environment checks
  (( $+commands[cargo] )) || die "Required command not found: cargo"
  [[ -f Cargo.toml ]]     || die "Cargo.toml not found (run this in your Rust project root)"

  local AUTO_PROJECT_NAME
  AUTO_PROJECT_NAME="$(run_project_name)"
  [[ -n "$PACKAGE_NAME" ]] || PACKAGE_NAME="$AUTO_PROJECT_NAME"

  if (( NO_CLEAR == 0 )); then clear_screen; fi

  info "Project: ${CLR_CYAN}${AUTO_PROJECT_NAME:-<workspace>}${CLR_RESET}"
  [[ -z "$PACKAGE_NAME" ]] || info "Package: ${CLR_CYAN}${PACKAGE_NAME}${CLR_RESET}"
  [[ -z "$BIN_NAME"     ]] || info "Bin:     ${CLR_CYAN}${BIN_NAME}${CLR_RESET}"

  # Common cargo flags
  local -a CARGO_ARGS=(--color "$CARGO_COLOR")
  [[ -z "$PACKAGE_NAME" ]] || CARGO_ARGS+=(--package "$PACKAGE_NAME")
  [[ -z "$BIN_NAME"     ]] || CARGO_ARGS+=(--bin "$BIN_NAME")

  # IMPORTANT: use the *same* RUSTFLAGS for every cargo call. Cargo treats a change
  # in RUSTFLAGS as a new configuration and recompiles everything.
  # User-defined RUSTFLAGS are preserved and "-D warnings" is appended.
  local STRICT_RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-D warnings"
  local -a STRICT=(env "RUSTFLAGS=$STRICT_RUSTFLAGS")

  case "$COMMAND" in
    fix)       run_fix ;;
    check)     run_check ;;
    clippy)    run_clippy ;;
    build)     run_build ;;
    run)       run_run ;;
    release)   run_release ;;
    test)      run_test ;;
    clean)     run_clean ;;
    fmt)       run_fmt ;;
    fmt-check) run_fmt_check ;;
    all)       run_all ;;
    *)
      error "Unknown run command: $COMMAND"
      print ""
      run_help
      exit 2
      ;;
  esac

  info "Finished in ${SECONDS}s"
}

# ==============================================================================
# TOOL 2: ncopy  (full 'src' snapshot + reset from template)
# ==============================================================================
typeset NC_SOURCE_DIR="src"
typeset NC_TEMPLATE_DIR="template_src"
typeset NC_SNAP_DIR="snapshots"
typeset NC_LOG_FILE="$NC_SNAP_DIR/.ncopy.log"

integer NC_DO_FMT=0 NC_DO_CHECK=0 NC_DO_GIT_CHECK=1 NC_DRY_RUN=0 NC_FORCE=0

nc_ensure_snap_dir() {
  if [[ ! -d "$NC_SNAP_DIR" ]] && (( NC_DRY_RUN == 0 )); then
    mkdir -p -- "$NC_SNAP_DIR"
    info "Created snapshot directory: '$NC_SNAP_DIR/'"
  fi
}

nc_check_env() {
  [[ -f "Cargo.toml" ]]       || die "Cargo.toml not found in current directory."
  [[ -d "$NC_SOURCE_DIR" ]]   || die "'$NC_SOURCE_DIR' directory does not exist."

  nc_ensure_snap_dir

  if (( NC_DO_GIT_CHECK == 1 )) && [[ -d ".git" ]]; then
    if ! grep -qs "^$NC_SNAP_DIR" .gitignore 2>/dev/null; then
      warn "'$NC_SNAP_DIR' is not in .gitignore."
    fi
  fi
}

# Hash of a directory's contents. Paths are taken relative to the directory, so
# two different directories with identical files give the same hash.
nc_dir_hash() {
  local target="$1"
  if [[ ! -d "$target" ]]; then
    print "none"
    return 0
  fi
  ( cd -- "$target" && find . -type f -exec sha256sum {} + | sort | sha256sum | awk '{print $1}' )
}

nc_log_event() {
  local msg="$1" dir="${2:-}" suffix=''
  if [[ -n "$dir" && -d "$dir" ]]; then
    suffix=" [SHA:$(nc_dir_hash "$dir")]"
  fi
  if (( NC_DRY_RUN == 0 )); then
    nc_ensure_snap_dir
    print -r -- "$(date '+%Y-%m-%d %H:%M:%S') | ${msg}${suffix}" >> "$NC_LOG_FILE"
  fi
}

# Next snapshot number, zero padded: 001, 002, ...
nc_next_index() {
  local -i max=0 idx=0
  local d name raw

  for d in "$NC_SNAP_DIR"/src_*(N/); do
    name="${d:t}"
    raw="${name#src_}"
    raw="${raw%%_*}"
    if [[ "$raw" == <-> ]]; then
      idx=$(( 10#$raw ))
      if (( idx > max )); then max=$idx; fi
    fi
  done

  printf '%03d' $(( max + 1 ))
}

nc_snapshot() {
  nc_ensure_snap_dir

  local idx ts target
  idx="$(nc_next_index)"
  ts="$(date '+%Y%m%d_%H%M%S')"
  target="$NC_SNAP_DIR/src_${idx}_${ts}"

  info "Creating full snapshot of entire '$NC_SOURCE_DIR/' -> '$target'..."

  if (( NC_DRY_RUN == 1 )); then
    info "[dry-run] mkdir -p $NC_SNAP_DIR"
    info "[dry-run] cp -a $NC_SOURCE_DIR $target"
  else
    mkdir -p -- "$target"
    cp -a -- "$NC_SOURCE_DIR"/. "$target"/
    nc_log_event "Snapshot #$idx created: ${target:t}" "$target"
    success "Saved snapshot directory: $target"

    print -r -- "${CLR_BOLD}Archived files in this snapshot:${CLR_RESET}"
    find "$target" -type f -printf "  - %P\n"
  fi
}

nc_backup() {
  local ts bak
  ts="$(date '+%Y%m%d_%H%M%S')"
  bak=".src_backup_${ts}"

  if (( NC_DRY_RUN == 1 )); then
    info "[dry-run] Backup: cp -a $NC_SOURCE_DIR $bak"
  else
    mkdir -p -- "$bak"
    cp -a -- "$NC_SOURCE_DIR"/. "$bak"/
    nc_log_event "Backup created: $bak" "$bak"
  fi
}

nc_setup_template() {
  if [[ ! -d "$NC_TEMPLATE_DIR" ]]; then
    info "Template directory '$NC_TEMPLATE_DIR' missing. Initializing with modular template..."
    mkdir -p "$NC_TEMPLATE_DIR"
    cat << 'EOF' > "$NC_TEMPLATE_DIR/lib.rs"
pub fn run_logic() {
    println!("Core engine logic from lib.rs");
}
EOF
    cat << 'EOF' > "$NC_TEMPLATE_DIR/main.rs"
fn main() {
    println!("Runner initialized.");
}
EOF
    success "Initialized '$NC_TEMPLATE_DIR' with default main.rs and lib.rs."
  fi
}

nc_reset() {
  nc_setup_template

  local current_h template_h
  current_h="$(nc_dir_hash "$NC_SOURCE_DIR")"
  template_h="$(nc_dir_hash "$NC_TEMPLATE_DIR")"

  if [[ "$current_h" == "$template_h" ]]; then
    info "Current '$NC_SOURCE_DIR/' is identical to template. Reset skipped."
    return 0
  fi

  nc_backup

  info "Purging current '$NC_SOURCE_DIR/' and replacing with '$NC_TEMPLATE_DIR/'..."
  if (( NC_DRY_RUN == 1 )); then
    info "[dry-run] rm -rf $NC_SOURCE_DIR && cp -a $NC_TEMPLATE_DIR $NC_SOURCE_DIR"
  else
    rm -rf -- "$NC_SOURCE_DIR"
    mkdir -p -- "$NC_SOURCE_DIR"
    cp -a -- "$NC_TEMPLATE_DIR"/. "$NC_SOURCE_DIR"/
    nc_log_event "Reset to template" "$NC_SOURCE_DIR"
    success "'$NC_SOURCE_DIR/' successfully refreshed from '$NC_TEMPLATE_DIR/'."
  fi

  if (( NC_DO_FMT == 1 )); then
    info "Formatting code..."
    cargo fmt || true
  fi
  if (( NC_DO_CHECK == 1 )); then
    info "Checking build..."
    cargo check || warn "Cargo check failed!"
  fi
  return 0
}

nc_run() {
  nc_snapshot
  nc_reset
}

nc_latest() {
  nc_ensure_snap_dir
  local -a snaps=("$NC_SNAP_DIR"/src_*(N/))
  if (( $#snaps == 0 )); then
    warn "No snapshots found."
  else
    local last="${snaps[-1]}"
    info "Latest snapshot: $last"
    print -r -- "${CLR_BOLD}Snapshot content listing:${CLR_RESET}"
    find "$last" -type f -printf "  %p\n"
  fi
}

nc_list() {
  nc_ensure_snap_dir
  local -a snaps=("$NC_SNAP_DIR"/src_*(N/))
  if (( $#snaps == 0 )); then
    warn "No snapshots found."
  else
    print -rl -- $snaps
  fi
}

nc_rollback() {
  local -a baks=(.src_backup_*(N/))
  (( $#baks > 0 )) || die "No backup folder (.src_backup_*) found."
  local latest_bak="${baks[-1]}"

  info "Restoring from $latest_bak..."
  if (( NC_DRY_RUN == 1 )); then
    info "[dry-run] Restore $latest_bak -> $NC_SOURCE_DIR"
  else
    rm -rf -- "$NC_SOURCE_DIR"
    mkdir -p -- "$NC_SOURCE_DIR"
    cp -a -- "$latest_bak"/. "$NC_SOURCE_DIR"/
    success "Restored '$NC_SOURCE_DIR/' from backup."
    nc_log_event "Rollback from $latest_bak" "$NC_SOURCE_DIR"
  fi
}

nc_clean() {
  local confirm=''
  if (( NC_FORCE != 1 )); then
    read -r "confirm?Delete ALL snapshots and emergency backups? (y/N) " || confirm=''
    [[ "$confirm" == [Yy] ]] || die "Aborted."
  fi
  local -a junk=("$NC_SNAP_DIR"/src_*(N) .src_backup_*(N))
  if (( $#junk > 0 )); then rm -rf -- $junk; fi
  success "Snapshots and temporary backups cleaned."
}

nc_status() {
  nc_ensure_snap_dir
  local -a snaps=("$NC_SNAP_DIR"/src_*(N/))
  print -r -- "${CLR_BOLD}--- Project Tree Status ---${CLR_RESET}"
  print -r -- "Directory      : $PWD"
  print -r -- "Source Hash    : $(nc_dir_hash "$NC_SOURCE_DIR")"
  print -r -- "Files in src/  :"
  find "$NC_SOURCE_DIR" -type f -printf "  - %p\n"
  print -r -- "Total Snaps    : $#snaps"
}

nc_help() {
  cat <<EOF
${CLR_BOLD}NCOPY v6.4 - Directory Tree Snapshot Engine${CLR_RESET}
Usage: tools.zsh ncopy <command> [options]

Commands:
  run        Snapshot current 'src/', then reset from 'template_src/'
  snapshot   Snapshot current 'src/' directory only
  reset      Reset 'src/' directly from 'template_src/'
  rollback   Undo last reset from emergency backup
  latest     List content of latest snapshot
  list       Show list of snapshot directories
  status     Show current files and hashes
  clean      Delete snapshots & backups
  help       Show help

Options:
  --fmt      Run cargo fmt after reset
  --check    Run cargo check after reset
  --dry-run  Simulate without altering files
  --force    Bypass confirmations
EOF
}

tool_ncopy() {
  NC_DO_FMT=0 NC_DO_CHECK=0 NC_DRY_RUN=0 NC_FORCE=0

  if (( $# < 1 )); then nc_help; exit 1; fi
  local cmd="$1"; shift

  while (( $# > 0 )); do
    case "$1" in
      --fmt)     NC_DO_FMT=1 ;;
      --check)   NC_DO_CHECK=1 ;;
      --dry-run) NC_DRY_RUN=1 ;;
      --force)   NC_FORCE=1 ;;
      *)         warn "Unknown argument: $1" ;;
    esac
    shift
  done

  case "$cmd" in
    help|-h|--help) nc_help; return 0 ;;
  esac

  nc_check_env

  case "$cmd" in
    run)      nc_run ;;
    snapshot) nc_snapshot ;;
    reset)    nc_reset ;;
    rollback) nc_rollback ;;
    latest)   nc_latest ;;
    list)     nc_list ;;
    status)   nc_status ;;
    clean)    nc_clean ;;
    *)        die "Unknown ncopy command '$cmd'. Run 'tools.zsh ncopy help'." ;;
  esac
}

# ==============================================================================
# TOOL 3: commit  (ncopy run + git add + git commit)
# ==============================================================================
tool_commit() {
  local msg="${1:-}"
  [[ -n "$msg" ]] || die "Commit message required.  Usage: tools.zsh commit \"message\""

  clear_screen
  tool_ncopy run
  git add --all
  git commit -m "$msg"
  git push origin
  print ""
  success "Commit was done successfully ..."
  print ""
}

# ==============================================================================
# TOOL 4: grv  (Rust toolchain versions -> rust_version.txt)
# ==============================================================================
tool_grv() {
  { rustc -Vv && echo "" && cargo -Vv; } | sed 's|^|// |' > rust_version.txt
  success "Wrote rust_version.txt"
}

# ==============================================================================
# TOOL 5: cb  (codebook-lsp lint)
# ==============================================================================
tool_cb() {
  (( $+commands[codebook-lsp] )) || die "Required command not found: codebook-lsp"
  local -a targets=("$@")
  (( $#targets > 0 )) || targets=(src)

  clear_screen
  # codebook-lsp lint src/main.rs src/lib.rs
  codebook-lsp lint "${targets[@]}"
}

# ==============================================================================
# Main help + dispatcher
# ==============================================================================
show_help() {
  cat <<'EOF'
Usage: tools.zsh <tool> [args...]

Tools:
  run      Cargo runner: fix, check, clippy, build, run, release, test, ...
           (tools.zsh run --help)
  ncopy    src snapshots and template reset
           (tools.zsh ncopy help)
  commit   ncopy run, then git add --all and git commit -m "<message>"
  grv      Write rustc/cargo versions to rust_version.txt
  cb       Run codebook-lsp lint (default path: src)
  help     Show this help

Examples:
  tools.zsh run clippy
  tools.zsh ncopy snapshot --dry-run
  tools.zsh commit "chapter 15 exercises"
  tools.zsh grv
  tools.zsh cb src/main.rs
EOF
}

main() {
  local tool="${1:-help}"
  if (( $# > 0 )); then shift; fi

  case "$tool" in
    run)            tool_run "$@" ;;
    ncopy)          tool_ncopy "$@" ;;
    commit)         tool_commit "$@" ;;
    grv)            tool_grv "$@" ;;
    cb)             tool_cb "$@" ;;
    help|-h|--help) show_help ;;
    *)
      error "Unknown tool: $tool"
      print ""
      show_help
      exit 2
      ;;
  esac
}

main "$@"