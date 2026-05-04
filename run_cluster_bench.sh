#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   ./run_cluster_bench.sh [hostfile]
# Variables opcionales:
#   NP_MPI=6 NP_HYBRID=3 OMP_THREADS=2 ./run_cluster_bench.sh

HOSTFILE="${1:-hostfile.txt}"
NP_MPI="${NP_MPI:-6}"
NP_HYBRID="${NP_HYBRID:-3}"
OMP_THREADS="${OMP_THREADS:-2}"

MPI_BIN="${MPI_BIN:-./cracker_MPI}"
HYBRID_BIN="${HYBRID_BIN:-./cracker_openMP_MPI}"

if [[ ! -f "$HOSTFILE" ]]; then
  echo "ERROR: no existe el hostfile: $HOSTFILE" >&2
  exit 1
fi

if [[ ! -x "$MPI_BIN" ]]; then
  echo "ERROR: no existe o no es ejecutable: $MPI_BIN" >&2
  exit 1
fi

if [[ ! -x "$HYBRID_BIN" ]]; then
  echo "ERROR: no existe o no es ejecutable: $HYBRID_BIN" >&2
  exit 1
fi

echo "=== MPI PURO ==="
echo "mpirun --hostfile $HOSTFILE -np $NP_MPI $MPI_BIN"
mpirun --hostfile "$HOSTFILE" -np "$NP_MPI" "$MPI_BIN"

echo
echo "=== HIBRIDO MPI+OpenMP ==="
echo "mpirun --hostfile $HOSTFILE -np $NP_HYBRID --map-by ppr:1:node $HYBRID_BIN $OMP_THREADS"
mpirun --hostfile "$HOSTFILE" -np "$NP_HYBRID" --map-by ppr:1:node "$HYBRID_BIN" "$OMP_THREADS"
