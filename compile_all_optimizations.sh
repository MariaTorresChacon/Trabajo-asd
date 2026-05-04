#!/usr/bin/env bash
set -euo pipefail

GCC="${GCC:-gcc}"
MPICC="${MPICC:-mpicc}"

OPT_LEVELS=(O0 O1 O2 O3)

SEQ_SRC="Trabajo_asd/cracker.c"
MPI_SRC="Trabajo_asd_MPI/cracker_MPI.c"
OMP_SRC="Trabajo_asd_openMP/cracker_openMP.c"
OMP_MPI_SRC="Trabajo_asd_openMP_MPI/cracker_openMP_MPI.c"

SEQ_DIR="Trabajo_asd"
MPI_DIR="Trabajo_asd_MPI"
OMP_DIR="Trabajo_asd_openMP"
OMP_MPI_DIR="Trabajo_asd_openMP_MPI"

for src in "$SEQ_SRC" "$MPI_SRC" "$OMP_SRC" "$OMP_MPI_SRC"; do
  if [[ ! -f "$src" ]]; then
    echo "ERROR: no existe el archivo fuente: $src" >&2
    exit 1
  fi
done

if [[ ! -f /etc/os-release ]] || ! grep -qi "ubuntu" /etc/os-release; then
  echo "ERROR: este script esta pensado para ejecutarse en Ubuntu." >&2
  exit 1
fi

if ! command -v "$GCC" >/dev/null 2>&1; then
  echo "ERROR: no se encontro el compilador GCC: $GCC" >&2
  exit 1
fi

if ! command -v "$MPICC" >/dev/null 2>&1; then
  echo "ERROR: no se encontro mpicc: $MPICC" >&2
  exit 1
fi

for opt in "${OPT_LEVELS[@]}"; do
  flag="-${opt}"
  echo "Compilando con $flag..."

  "$GCC" "$flag" "$SEQ_SRC" -o "${SEQ_DIR}/cracker_${opt}"
  "$MPICC" "$flag" "$MPI_SRC" -o "${MPI_DIR}/cracker_MPI_${opt}"
  "$GCC" "$flag" -fopenmp "$OMP_SRC" -o "${OMP_DIR}/cracker_OMP_${opt}"
  "$MPICC" "$flag" -fopenmp "$OMP_MPI_SRC" -o "${OMP_MPI_DIR}/cracker_OMP_MPI_${opt}"
done

echo "Compilacion completada."
