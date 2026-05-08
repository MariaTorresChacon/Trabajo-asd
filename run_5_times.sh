#!/usr/bin/env bash
set -euo pipefail

RUNS=5

usage() {
  cat <<'EOF'
Usage:
  ./run_5_times.sh <script-or-command> [args...]

Description:
  Runs the provided script or command 5 consecutive times, forwarding all
  additional arguments unchanged, and prints the execution time of each run.

Examples:
  ./run_5_times.sh ./detect_bottlenecks.sh --hostfile hostfile.txt
  ./run_5_times.sh bash ./compile_all_optimizations.sh
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to measure elapsed time." >&2
  exit 1
fi

TARGET=("$@")

if ! command -v "${TARGET[0]}" >/dev/null 2>&1 && [[ ! -x "${TARGET[0]}" ]]; then
  echo "ERROR: target command not found or not executable: ${TARGET[0]}" >&2
  exit 1
fi

times=()

for ((run = 1; run <= RUNS; run++)); do
  echo "Run $run/$RUNS: ${TARGET[*]}"

  start_ns="$(python3 -c 'import time; print(time.perf_counter_ns())')"
  "${TARGET[@]}"
  end_ns="$(python3 -c 'import time; print(time.perf_counter_ns())')"
  elapsed="$(python3 -c 'import sys; start = int(sys.argv[1]); end = int(sys.argv[2]); print(f"{(end - start) / 1_000_000_000:.6f}")' "$start_ns" "$end_ns")"

  if [[ -z "$elapsed" ]]; then
    echo "ERROR: could not measure execution time for run $run." >&2
    exit 1
  fi

  times+=("$elapsed")
  echo "  Time: ${elapsed}s"
done

printf '\nExecution times:\n'
for ((i = 0; i < ${#times[@]}; i++)); do
  printf '  Run %d: %ss\n' "$((i + 1))" "${times[i]}"
done

summary="$(
  printf '%s\n' "${times[@]}" | awk '
    BEGIN {
      min = -1
      max = 0
      sum = 0
      count = 0
    }
    {
      value = $1 + 0
      if (min < 0 || value < min) min = value
      if (value > max) max = value
      sum += value
      count++
    }
    END {
      if (count == 0) exit 1
      printf "min=%.6f\nmax=%.6f\navg=%.6f\n", min, max, sum / count
    }
  '
)"

printf '\nSummary:\n'
printf '  %s\n' "${summary//$'\n'/$'\n  '}"
