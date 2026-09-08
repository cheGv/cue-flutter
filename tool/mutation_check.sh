#!/usr/bin/env bash
# tool/mutation_check.sh — prove a fence test bites, without eating your work.
#
#   tool/mutation_check.sh <file> <sed-expression> <test-path> [flutter test args…]
#
# Snapshots the WORKING-TREE version of <file> (never `git checkout`, which
# restores HEAD and silently strips uncommitted edits — during a build the
# file under mutation always has uncommitted changes), applies the sed
# mutation in place, runs the test, then restores the snapshot byte-for-byte
# and verifies the restore with cmp. The restore runs from a trap, so an
# interrupted run still puts the file back.
#
# Exit codes:
#   0  the mutation was CAUGHT (the test failed under mutation) — what you want
#   1  the mutation SURVIVED (the test still passed) — the fence has a hole
#   2  usage / the mutation did not change the file / restore failed
#
# Example (Step 3's two checks):
#   tool/mutation_check.sh lib/services/cas_assessment_service.dart \
#     's/    await ClientsQuery(client: _sb).requireLiveClient(clientId);/    \/\/ MUTATION/' \
#     test/client_liveness_fence_test.dart
#   tool/mutation_check.sh lib/services/today_widgets_service.dart \
#     "0,/.isFilter('clients.deleted_at', null)/s//\/\/ MUTATION/" \
#     test/client_liveness_fence_test.dart

set -u

if [ $# -lt 3 ]; then
  sed -n '2,25p' "$0"
  exit 2
fi

file="$1"; expr="$2"; testpath="$3"; shift 3

if [ ! -f "$file" ]; then
  echo "mutation_check: no such file: $file" >&2
  exit 2
fi

snapshot="$(mktemp)"
cp -p -- "$file" "$snapshot"

restore() {
  cp -p -- "$snapshot" "$file"
  if cmp -s -- "$snapshot" "$file"; then
    rm -f -- "$snapshot"
  else
    echo "mutation_check: RESTORE FAILED — working-tree copy kept at $snapshot" >&2
    exit 2
  fi
}
trap restore EXIT INT TERM

sed -i -- "$expr" "$file"
if cmp -s -- "$snapshot" "$file"; then
  echo "mutation_check: the sed expression changed nothing in $file" >&2
  exit 2
fi

echo "mutation_check: mutated $file, running $testpath"
if flutter test --no-pub "$testpath" "$@" >/dev/null 2>&1; then
  echo "mutation_check: SURVIVED — $testpath still passes with $file mutated"
  exit 1
else
  echo "mutation_check: CAUGHT — $testpath fails with $file mutated"
  exit 0
fi
