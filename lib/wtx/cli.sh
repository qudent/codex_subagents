# shellcheck shell=bash

wtx::set_defaults() {
  NAME=""
  CMD=""
  FROM_REF="HEAD"
  NO_OPEN=0
  VERBOSE=0
  GIT_LOGGING=1
  INTERNAL_POST_COMMIT=0
  CLOSE_MODE=""
  DRY_RUN_FLAG=0
  DELETE_BRANCHES_FLAG=0
}

wtx::parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        wtx::usage
        exit 0
        ;;
      -c)
        shift
        CMD="${1:-}"
        if [ -z "$CMD" ]; then
          echo "Missing argument for -c" >&2
          exit 64
        fi
        ;;
      --from)
        shift
        FROM_REF="${1:-HEAD}"
        ;;
      --no-open)
        NO_OPEN=1
        ;;
      --dry-run)
        DRY_RUN_FLAG=1
        ;;
      --delete-branches)
        DELETE_BRANCHES_FLAG=1
        ;;
      --verbose)
        VERBOSE=1
        ;;
      --no-git-logging)
        GIT_LOGGING=0
        ;;
      --_post-commit)
        INTERNAL_POST_COMMIT=1
        ;;
      --close|--close-merge|--close-force)
        echo "Close workflow is not implemented yet." >&2
        exit 78
        ;;
      --*)
        echo "Unknown option: $1" >&2
        exit 64
        ;;
      *)
        if [ -z "$NAME" ]; then
          NAME="$1"
        else
          echo "Unexpected arg: $1" >&2
          wtx::usage
          exit 64
        fi
        ;;
    esac
    shift
  done

}
