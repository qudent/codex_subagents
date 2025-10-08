# common helpers shared across wtx modules (bash 3.2 compatible)

need() { command -v "$1" >/dev/null 2>&1; }

logv() {
  if [ "${VERBOSE:-0}" -eq 1 ]; then
    echo "[wtx] $*"
  fi
}

die() {
  echo "[wtx] $*" >&2
  exit 2
}

sanitize_component() {
  printf %s "$1" | tr '/:' '__'
}

q() {
  printf %q "$1"
}
