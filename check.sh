#!/usr/bin/env bash
# Compares what each observer action read against the pristine input.
set -euo pipefail
cd "$(dirname "$0")"
bin=$(bazel info bazel-bin --config=remote 2>/dev/null)
echo "== corrupting actions"
cat "$bin/corrupt_direct.log" "$bin/corrupt_via_symlink.log"
echo
echo "== observers"
bad=0
for f in "$bin"/observed_*.txt; do
  exec_line=$(head -1 "$f")
  if diff -q <(tail -n +2 "$f") input.txt >/dev/null; then
    echo "ok        $(basename "$f") $exec_line"
  else
    echo "CORRUPTED $(basename "$f") $exec_line"
    tail -n +2 "$f" | grep CORRUPTED | sed 's/^/            /'
    bad=$((bad+1))
  fi
done
echo
echo "$bad observer(s) received modified bytes for a pristine digest."
[ "$bad" -eq 0 ]
