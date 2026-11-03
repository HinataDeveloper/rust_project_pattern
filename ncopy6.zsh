#!/usr/bin/env zsh

# ==============================================================================
# NCOPY v6.4 - Full 'src' Directory Tree Iteration Engine
# Developed for: هیناتا (Hinata)
# ==============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_NAME="$(basename -- "$0")"
SOURCE_DIR="src"
TEMPLATE_DIR="template_src"
SNAP_DIR="snapshots"
LOG_FILE="$SNAP_DIR/.ncopy.log"

# --- Flags ---
DO_FMT=0
DO_CHECK=0
DO_GIT_CHECK=1
VERBOSE=0
DRY_RUN=0
FORCE=0

# --- Colors ---
if [[ -t 1 ]]; then
    C_RES='\033[0m'
    C_BOLD='\033[1m'
    C_RED='\033[31m'
    C_GRN='\033[32m'
    C_YLW='\033[33m'
    C_BLU='\033[34m'
else
    C_RES='' C_BOLD='' C_RED='' C_GRN='' C_YLW='' C_BLU=''
fi

info()    { printf "${C_BLU}[INFO]${C_RES} %s\n" "$1"; }
success() { printf "${C_GRN}[OK]${C_RES}   %s\n" "$1"; }
warn()    { printf "${C_YLW}[WARN]${C_RES} %s\n" "$1" >&2; }
error()   { printf "${C_RED}[ERR]${C_RES}  %s\n" "$1" >&2; }
die()     { error "$1"; exit 1; }

# اطمینان از وجود پوشه snapshots
ensure_snap_dir() {
    if [[ ! -d "$SNAP_DIR" && "$DRY_RUN" -eq 0 ]]; then
        mkdir -p -- "$SNAP_DIR"
        info "Created snapshot directory: '$SNAP_DIR/'"
    fi
}

# --- Verification ---
check_env() {
    [[ -f "Cargo.toml" ]] || die "Error: Cargo.toml not found in current directory."
    [[ -d "$SOURCE_DIR" ]] || die "Error: '$SOURCE_DIR' directory does not exist."

    ensure_snap_dir

    if [[ "$DO_GIT_CHECK" -eq 1 && -d ".git" ]]; then
        if ! grep -qs "^$SNAP_DIR" .gitignore 2>/dev/null; then
            warn "'$SNAP_DIR' is not in .gitignore."
        fi
    fi
}

get_directory_hash() {
    local target="$1"
    if [[ ! -d "$target" ]]; then
        echo "none"
        return
    fi
    find "$target" -type f -exec sha256sum {} + | sort | sha256sum | awk '{print $1}'
}

log_event() {
    local msg="$1"
    local dir="${2:-}"
    local hash=""
    [[ -n "$dir" && -d "$dir" ]] && hash="$(get_directory_hash "$dir")"

    local entry="$(date '+%Y-%m-%d %H:%M:%S') | $msg ${hash:+[SHA:$hash]}"

    if [[ "$DRY_RUN" -eq 0 ]]; then
        ensure_snap_dir
        printf '%s\n' "$entry" >> "$LOG_FILE"
    fi
}

# --- Action ---
# --- Action ---
get_next_index() {
    local max=0
    local d name raw_idx idx

    if [[ ! -d "$SNAP_DIR" ]]; then
        printf "001"
        return
    fi

    # استفاده از پرانتز گرد برای Glob Qualifierهای Zsh:
    # N = nullglob
    # / = فقط دایرکتوری‌ها
    for d in "$SNAP_DIR"/src_*(N/); do
        name="${d:t}" # معادل basename

        # تطابق نام پوشه به سبک استاندارد Zsh Globbing
        if [[ "$name" == src_<->* ]]; then
            # استخراج عدد بلافاصله بعد از _src
            raw_idx="${name#src_}"
            raw_idx="${raw_idx%%_*}"

            if [[ "$raw_idx" == <-> ]]; then
                idx=$(( 10#$raw_idx ))
                (( idx > max )) && max=$idx
            fi
        fi
    done

    printf "%03d" $(( max + 1 ))
} 
# --- get_next_index ---

# --- Actions ---
create_snapshot() {
    ensure_snap_dir

    local idx ts target
    idx="$(get_next_index | tr -d '\r\n[:space:]')"
    ts="$(date '+%Y%m%d_%H%M%S')"
    target="$SNAP_DIR/src_${idx}_${ts}"

    info "Creating full snapshot of entire '$SOURCE_DIR/' -> '$target'..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] mkdir -p $SNAP_DIR"
        info "[dry-run] cp -a $SOURCE_DIR $target"
    else
        mkdir -p -- "$target"
        # کپی کامل محتویات src داخل snapshot جدید
        cp -a -- "$SOURCE_DIR"/. "$target"/
        log_event "Snapshot #$idx created: $(basename "$target")" "$target"
        success "Saved snapshot directory: $target"

        printf "${C_BOLD}Archived files in this snapshot:${C_RES}\n"
        find "$target" -type f -printf "  - %P\n"
    fi
}

create_backup() {
    local ts
    ts="$(date '+%Y%m%d_%H%M%S')"
    local bak=".src_backup_${ts}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] Backup: cp -a $SOURCE_DIR $bak"
    else
        mkdir -p -- "$bak"
        cp -a -- "$SOURCE_DIR"/. "$bak"/
        log_event "Backup created: $bak" "$bak"
    fi
}

setup_template_if_empty() {
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        info "Template directory '$TEMPLATE_DIR' missing. Initializing with modular template..."
        mkdir -p "$TEMPLATE_DIR"
        cat << 'EOF' > "$TEMPLATE_DIR/lib.rs"
pub fn run_logic() {
    println!("Core engine logic from lib.rs");
}
EOF
        cat << 'EOF' > "$TEMPLATE_DIR/main.rs"
fn main() {
    println!("Runner initialized.");
}
EOF
        success "Initialized '$TEMPLATE_DIR' with default main.rs and lib.rs."
    fi
}

perform_reset() {
    setup_template_if_empty

    local current_h
    current_h="$(get_directory_hash "$SOURCE_DIR")"
    local template_h
    template_h="$(get_directory_hash "$TEMPLATE_DIR")"

    if [[ "$current_h" == "$template_h" ]]; then
        info "Current '$SOURCE_DIR/' is identical to template. Reset skipped."
        return 0
    fi

    create_backup

    info "Purging current '$SOURCE_DIR/' and replacing with '$TEMPLATE_DIR/'..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] rm -rf $SOURCE_DIR && cp -a $TEMPLATE_DIR $SOURCE_DIR"
    else
        rm -rf -- "$SOURCE_DIR"
        mkdir -p -- "$SOURCE_DIR"
        cp -a -- "$TEMPLATE_DIR"/. "$SOURCE_DIR"/
        log_event "Reset to template" "$SOURCE_DIR"
        success "'$SOURCE_DIR/' successfully refreshed from '$TEMPLATE_DIR/'."
    fi

    [[ "$DO_FMT" -eq 1 ]] && { info "Formatting code..."; cargo fmt || true; }
    [[ "$DO_CHECK" -eq 1 ]] && { info "Checking build..."; cargo check || warn "Cargo check failed!"; }
}

cmd_run() {
    create_snapshot
    perform_reset
}

cmd_latest() {
    ensure_snap_dir
    local last
    last=$(find "$SNAP_DIR" -mindepth 1 -maxdepth 1 -type d -name "src_*" 2>/dev/null | sort | tail -n 1)
    if [[ -z "$last" ]]; then
        warn "No snapshots found."
    else
        info "Latest snapshot: $last"
        printf "${C_BOLD}Snapshot content listing:${C_RES}\n"
        find "$last" -type f -printf "  %p\n"
    fi
}

cmd_rollback() {
    local latest_bak
    latest_bak=$(find . -mindepth 1 -maxdepth 1 -type d -name ".src_backup_*" 2>/dev/null | sort | tail -n 1)
    [[ -z "$latest_bak" ]] && die "No backup folder (.src_backup_*) found."

    info "Restoring from $latest_bak..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] Restore $latest_bak -> $SOURCE_DIR"
    else
        rm -rf -- "$SOURCE_DIR"
        mkdir -p -- "$SOURCE_DIR"
        cp -a -- "$latest_bak"/. "$SOURCE_DIR"/
        success "Restored '$SOURCE_DIR/' from backup."
        log_event "Rollback from $latest_bak" "$SOURCE_DIR"
    fi
}

cmd_clean() {
    if [[ "$FORCE" -ne 1 ]]; then
        read -r "confirm?Delete ALL snapshots and emergency backups? (y/N) " 2>/dev/null || read -p "Delete ALL snapshots and emergency backups? (y/N) " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."
    fi
    rm -rf "$SNAP_DIR"/src_*
    rm -rf .src_backup_*
    success "Snapshots and temporary backups cleaned."
}

cmd_status() {
    ensure_snap_dir
    local snap_count
    snap_count=$(find "$SNAP_DIR" -mindepth 1 -maxdepth 1 -type d -name "src_*" 2>/dev/null | wc -l | tr -d ' ')
    printf "${C_BOLD}--- Project Tree Status ---${C_RES}\n"
    printf "Directory      : %s\n" "$(pwd)"
    printf "Source Hash    : %s\n" "$(get_directory_hash "$SOURCE_DIR")"
    printf "Files in src/  :\n"
    find "$SOURCE_DIR" -type f -printf "  - %p\n"
    printf "Total Snaps    : %s\n" "$snap_count"
}

show_help() {
    cat <<EOF
${C_BOLD}NCOPY v6.3 - Directory Tree Snapshot Engine${C_RES}
Usage: $SCRIPT_NAME <command> [options]

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

# --- Entry Point ---
[[ $# -lt 1 ]] && { show_help; exit 1; }
COMMAND="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fmt) DO_FMT=1 ;;
        --check) DO_CHECK=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        -v) VERBOSE=1 ;;
        *) warn "Unknown argument: $1" ;;
    esac
    shift
done

check_env

case "$COMMAND" in
    run)      cmd_run ;;
    snapshot) create_snapshot ;;
    reset)    perform_reset ;;
    rollback) cmd_rollback ;;
    latest)   cmd_latest ;;
    status)   cmd_status ;;
    clean)    cmd_clean ;;
    list)
        ensure_snap_dir
        find "$SNAP_DIR" -mindepth 1 -maxdepth 1 -type d -name "src_*" 2>/dev/null | sort || warn "No snapshots found."
        ;;
    help)     show_help ;;
    *)        die "Unknown command '$COMMAND'. Run '$SCRIPT_NAME help'." ;;
esac
