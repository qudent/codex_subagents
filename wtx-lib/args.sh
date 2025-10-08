# argument parsing for wtx entrypoint

wtx_print_help() {
  cat <<'EOH'
wtx — create/reuse git worktrees and tmux/screen sessions.

Usage:
  wtx [NAME] [-c CMD] [--from REF] [--mux auto|tmux|screen] [--no-open]
  wtx close [--merge|--force] [BRANCH]
  wtx prune [--dry-run] [--delete-branches]
Flags:
  -c CMD         Send raw keystrokes (exactly, then Enter)
  --from REF     Base branch/commit (default: HEAD)
  --mux MODE     auto|tmux|screen (default: auto)
  --no-open      Do not attach; print attach command instead
  --verbose      Extra diagnostics
  --close[-merge|-force]  Close after launching (main command)
EOH
}

wtx_parse_args() {
  SUBCOMMAND=""
  if [ $# -gt 0 ]; then
    case "$1" in
      close|prune) SUBCOMMAND="$1"; shift ;;
    esac
  fi

  NAME=""; CMD=""; FROM_REF="HEAD"; MUX="${MUX:-auto}"; NO_OPEN=0; VERBOSE=0
  CLOSE_AFTER=0; CLOSE_MODE="soft"

  if [ "$SUBCOMMAND" = "close" ]; then
    CLOSE_BRANCH=""; CLOSE_MODE="soft"
    while [ $# -gt 0 ]; do
      case "$1" in
        -h|--help) wtx_print_help; exit 0 ;;
        --merge) CLOSE_MODE="merge" ;;
        --force) CLOSE_MODE="force" ;;
        --verbose) VERBOSE=1 ;;
        --*) die "Unknown option for close: $1" ;;
        *) [ -z "$CLOSE_BRANCH" ] || die "Unexpected arg: $1"; CLOSE_BRANCH="$1" ;;
      esac
      shift
    done
  elif [ "$SUBCOMMAND" = "prune" ]; then
    PRUNE_DRY_RUN=0; PRUNE_DELETE_BRANCHES=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -h|--help) wtx_print_help; exit 0 ;;
        --dry-run) PRUNE_DRY_RUN=1 ;;
        --delete-branches) PRUNE_DELETE_BRANCHES=1 ;;
        --verbose) VERBOSE=1 ;;
        --*) die "Unknown option for prune: $1" ;;
        *) die "Unexpected arg: $1" ;;
      esac
      shift
    done
  else
    while [ $# -gt 0 ]; do
      case "$1" in
        -h|--help) wtx_print_help; exit 0 ;;
        -c) shift; CMD="${1:-}"; [ -n "$CMD" ] || die "Missing argument for -c" ;;
        --from) shift; FROM_REF="${1:-HEAD}" ;;
        --mux) shift; MUX="${1:-auto}" ;;
        --no-open) NO_OPEN=1 ;;
        --verbose) VERBOSE=1 ;;
        --close) CLOSE_AFTER=1; CLOSE_MODE="soft" ;;
        --close-force) CLOSE_AFTER=1; CLOSE_MODE="force" ;;
        --close-merge) CLOSE_AFTER=1; CLOSE_MODE="merge" ;;
        --*) die "Unknown option: $1" ;;
        *) [ -z "$NAME" ] || die "Unexpected arg: $1"; NAME="$1" ;;
      esac
      shift
    done
  fi
}
