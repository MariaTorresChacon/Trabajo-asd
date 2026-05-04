#!/usr/bin/env bash
set -euo pipefail

files_to_remove=(
  # Posibles salidas antiguas en la raiz
  "cracker_O0" "cracker_O1" "cracker_O2" "cracker_O3"
  "cracker_MPI_O0" "cracker_MPI_O1" "cracker_MPI_O2" "cracker_MPI_O3"
  "cracker_OMP_O0" "cracker_OMP_O1" "cracker_OMP_O2" "cracker_OMP_O3"
  "cracker_OMP_MPI_O0" "cracker_OMP_MPI_O1" "cracker_OMP_MPI_O2" "cracker_OMP_MPI_O3"
  "cracker_seq" "cracker_MPI" "cracker_openMP" "cracker_openMP_MPI"

  # Salidas en carpeta secuencial
  "Trabajo_asd/cracker_O0" "Trabajo_asd/cracker_O1" "Trabajo_asd/cracker_O2" "Trabajo_asd/cracker_O3"
  "Trabajo_asd/cracker_seq" "Trabajo_asd/cracker_vs_style"

  # Salidas en carpeta MPI
  "Trabajo_asd_MPI/cracker_MPI_O0" "Trabajo_asd_MPI/cracker_MPI_O1" "Trabajo_asd_MPI/cracker_MPI_O2" "Trabajo_asd_MPI/cracker_MPI_O3"
  "Trabajo_asd_MPI/cracker_MPI"

  # Salidas en carpeta OpenMP
  "Trabajo_asd_openMP/cracker_OMP_O0" "Trabajo_asd_openMP/cracker_OMP_O1" "Trabajo_asd_openMP/cracker_OMP_O2" "Trabajo_asd_openMP/cracker_OMP_O3"
  "Trabajo_asd_openMP/cracker_openMP"

  # Salidas en carpeta OpenMP+MPI
  "Trabajo_asd_openMP_MPI/cracker_OMP_MPI_O0" "Trabajo_asd_openMP_MPI/cracker_OMP_MPI_O1" "Trabajo_asd_openMP_MPI/cracker_OMP_MPI_O2" "Trabajo_asd_openMP_MPI/cracker_OMP_MPI_O3"
  "Trabajo_asd_openMP_MPI/cracker_openMP_MPI"
)

deleted=0
for file in "${files_to_remove[@]}"; do
  if [[ -e "$file" ]]; then
    rm -f "$file"
    echo "Eliminado: $file"
    deleted=$((deleted + 1))
  fi
done

echo "Limpieza completada. Archivos eliminados: $deleted"
