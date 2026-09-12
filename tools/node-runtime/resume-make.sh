#!/usr/bin/env bash
# Resume the Node cross-compile in $SRC and record the real exit code in the log.
#
# Why this is a script and not an inline `wsl bash -lc '...'`:
#   passing a payload that itself contains quotes through
#   PowerShell -> wsl -> bash gets mangled (observed: the compound command silently
#   did not run, leaving the previous run's log tail in place, and MAKE_EXIT was
#   never written). A script file has no quoting to lose. ASCII only.
SRC="${1:-$HOME/ohos/node-v22.23.2}"
LOG="$HOME/ohos/build-node.log"

if [ ! -d "$SRC" ]; then
  echo "ERROR: no source tree at $SRC" >&2
  exit 1
fi

cd "$SRC"
JOBS="$(nproc)"
echo "=== make -j${JOBS} (resume) $(date -Is) ===" > "$LOG"
make -j"${JOBS}" >> "$LOG" 2>&1
code=$?
echo "MAKE_EXIT=$code" >> "$LOG"
echo "MAKE_EXIT=$code"
exit 0
