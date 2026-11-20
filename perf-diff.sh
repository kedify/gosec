#!/bin/bash

set -euo pipefail

base_ref=${GOSEC_PERF_BASE:-origin/master}
base_commit=$(git rev-parse --verify --end-of-options "$base_ref^{commit}")
build_dir=$(mktemp -d)
reference_dir="$build_dir/reference"
trap 'git worktree remove --force "$reference_dir" 2>/dev/null || true; rm -rf -- "$build_dir"' EXIT
git worktree add --detach "$reference_dir" "$base_commit" >/dev/null

clock=date
if command -v gdate >/dev/null; then
  clock=gdate
fi

# Scan the current folder and measure the duration.
scan() {
  local start end
  start=$("$clock" +%s%3N)
  "$1" -quiet ./... >/dev/null || return
  end=$("$clock" +%s%3N)
  printf '%s\n' "$((end - start))"
}

# Build both versions before measuring so they use the same toolchain and input.
make -C "$reference_dir" build >/dev/null
make build >/dev/null

# Warm both binaries, then compare median timings from interleaved scans.
scan "$reference_dir/gosec" >/dev/null
scan ./gosec >/dev/null
reference_times=()
current_times=()
for attempt in 1 2 3; do
  reference_times+=("$(scan "$reference_dir/gosec")")
  current_times+=("$(scan ./gosec)")
done
duration_master=$(printf '%s\n' "${reference_times[@]}" | sort -n | sed -n '2p')
duration=$(printf '%s\n' "${current_times[@]}" | sort -n | sed -n '2p')
echo "gosec reference time: ${duration_master}ms"
echo "gosec time: ${duration}ms"

# Compute the difference of the execution time.
diff=$((duration - duration_master))
if [[ diff -lt 0 ]]; then
  diff=$((-diff))
fi
echo "diff: ${diff}ms"
perf=$((100 - (duration * 100) / duration_master))
echo "perf diff: ${perf}%"

# Fail the build if there is a performance degradation of more than 10%.
if [[ $perf -lt -10 ]]; then
  exit 1
fi
