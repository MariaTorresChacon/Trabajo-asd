#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-$ROOT_DIR/.bottleneck_detector}"
OPT_LEVEL="${OPT_LEVEL:-O3}"
REPEATS="${REPEATS:-1}"
MAX_OMP_THREADS="${MAX_OMP_THREADS:-}"
MAX_MPI_PROCS="${MAX_MPI_PROCS:-}"
HOSTFILE="${HOSTFILE:-}"
RUN_HYBRID="${RUN_HYBRID:-1}"
WITH_PERF="${WITH_PERF:-auto}"

SEQ_SRC="$ROOT_DIR/Trabajo_asd/cracker.c"
OMP_SRC="$ROOT_DIR/Trabajo_asd_openMP/cracker_openMP.c"
MPI_SRC="$ROOT_DIR/Trabajo_asd_MPI/cracker_MPI.c"
HYB_SRC="$ROOT_DIR/Trabajo_asd_openMP_MPI/cracker_openMP_MPI.c"

SEQ_BIN_DEFAULT="$ROOT_DIR/Trabajo_asd/cracker_${OPT_LEVEL}"
OMP_BIN_DEFAULT="$ROOT_DIR/Trabajo_asd_openMP/cracker_OMP_${OPT_LEVEL}"
MPI_BIN_DEFAULT="$ROOT_DIR/Trabajo_asd_MPI/cracker_MPI_${OPT_LEVEL}"
HYB_BIN_DEFAULT="$ROOT_DIR/Trabajo_asd_openMP_MPI/cracker_OMP_MPI_${OPT_LEVEL}"

SEQ_BIN=""
OMP_BIN=""
MPI_BIN=""
HYB_BIN=""

MPIRUN_BIN=""
PHYSICAL_CPUS=1
LOGICAL_CPUS=1
PERF_AVAILABLE=0
TIME_BIN="/usr/bin/time"
RAW_DIR=""
RESULTS_TSV=""
REPORT_TXT=""
STATIC_TXT=""
PROBES_TXT=""

usage() {
  cat <<EOF
Uso:
  $(basename "$0") [opciones]

Opciones:
  --opt-level O0|O1|O2|O3   Optimización a analizar (default: $OPT_LEVEL)
  --repeats N               Repeticiones por configuración (default: $REPEATS)
  --max-omp N               Máximo de hilos OpenMP a probar
  --max-mpi N               Máximo de procesos MPI a probar
  --hostfile PATH           Hostfile para mpirun
  --skip-hybrid             No ejecutar la versión híbrida
  --with-perf yes|no|auto   Intentar perf stat si está disponible (default: $WITH_PERF)
  --workdir PATH            Directorio de salida (default: $WORKDIR)
  -h, --help                Mostrar ayuda

Salida:
  $WORKDIR/report.txt
  $WORKDIR/results.tsv
  $WORKDIR/static_findings.txt
  $WORKDIR/probes.txt
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --opt-level)
        OPT_LEVEL="${2:-}"
        shift 2
        ;;
      --repeats)
        REPEATS="${2:-}"
        shift 2
        ;;
      --max-omp)
        MAX_OMP_THREADS="${2:-}"
        shift 2
        ;;
      --max-mpi)
        MAX_MPI_PROCS="${2:-}"
        shift 2
        ;;
      --hostfile)
        HOSTFILE="${2:-}"
        shift 2
        ;;
      --skip-hybrid)
        RUN_HYBRID=0
        shift
        ;;
      --with-perf)
        WITH_PERF="${2:-}"
        shift 2
        ;;
      --workdir)
        WORKDIR="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Argumento no reconocido: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

setup_paths() {
  RAW_DIR="$WORKDIR/raw"
  RESULTS_TSV="$WORKDIR/results.tsv"
  REPORT_TXT="$WORKDIR/report.txt"
  STATIC_TXT="$WORKDIR/static_findings.txt"
  PROBES_TXT="$WORKDIR/probes.txt"
  mkdir -p "$RAW_DIR"
}

detect_cpus() {
  if [[ "$(uname -s)" == "Linux" ]]; then
    LOGICAL_CPUS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
    if have_cmd lscpu; then
      PHYSICAL_CPUS="$(lscpu -p=socket,core 2>/dev/null | grep -v '^#' | sort -u | wc -l | tr -d ' ')"
    else
      PHYSICAL_CPUS="$LOGICAL_CPUS"
    fi
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    LOGICAL_CPUS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)"
    PHYSICAL_CPUS="$(sysctl -n hw.physicalcpu 2>/dev/null || echo "$LOGICAL_CPUS")"
  else
    LOGICAL_CPUS=1
    PHYSICAL_CPUS=1
  fi

  [[ -z "$MAX_OMP_THREADS" ]] && MAX_OMP_THREADS="$PHYSICAL_CPUS"
  [[ -z "$MAX_MPI_PROCS" ]] && MAX_MPI_PROCS="$PHYSICAL_CPUS"
}

detect_tools() {
  if have_cmd mpirun; then
    MPIRUN_BIN="$(command -v mpirun)"
  elif have_cmd mpiexec; then
    MPIRUN_BIN="$(command -v mpiexec)"
  fi

  if [[ "$WITH_PERF" == "yes" ]]; then
    have_cmd perf || { echo "Se pidió perf pero no está disponible." >&2; exit 1; }
    PERF_AVAILABLE=1
  elif [[ "$WITH_PERF" == "auto" ]] && have_cmd perf; then
    PERF_AVAILABLE=1
  fi

  if [[ ! -x "$TIME_BIN" ]] && have_cmd gtime; then
    TIME_BIN="$(command -v gtime)"
  fi
}

ensure_binaries() {
  local cflags="-${OPT_LEVEL}"

  if [[ -x "$SEQ_BIN_DEFAULT" ]]; then
    SEQ_BIN="$SEQ_BIN_DEFAULT"
  else
    gcc $cflags "$SEQ_SRC" -o "$WORKDIR/cracker_seq_${OPT_LEVEL}"
    SEQ_BIN="$WORKDIR/cracker_seq_${OPT_LEVEL}"
  fi

  if [[ -x "$OMP_BIN_DEFAULT" ]]; then
    OMP_BIN="$OMP_BIN_DEFAULT"
  else
    gcc $cflags -fopenmp "$OMP_SRC" -o "$WORKDIR/cracker_omp_${OPT_LEVEL}"
    OMP_BIN="$WORKDIR/cracker_omp_${OPT_LEVEL}"
  fi

  if [[ -n "$MPIRUN_BIN" ]]; then
    if [[ -x "$MPI_BIN_DEFAULT" ]]; then
      MPI_BIN="$MPI_BIN_DEFAULT"
    else
      mpicc $cflags "$MPI_SRC" -o "$WORKDIR/cracker_mpi_${OPT_LEVEL}"
      MPI_BIN="$WORKDIR/cracker_mpi_${OPT_LEVEL}"
    fi

    if [[ "$RUN_HYBRID" -eq 1 ]]; then
      if [[ -x "$HYB_BIN_DEFAULT" ]]; then
        HYB_BIN="$HYB_BIN_DEFAULT"
      else
        mpicc $cflags -fopenmp "$HYB_SRC" -o "$WORKDIR/cracker_hybrid_${OPT_LEVEL}"
        HYB_BIN="$WORKDIR/cracker_hybrid_${OPT_LEVEL}"
      fi
    fi
  fi
}

seq_values() {
  local max="$1"
  local i
  for ((i = 1; i <= max; i++)); do
    printf '%s\n' "$i"
  done
}

hybrid_pairs() {
  local max_procs="$1"
  local max_threads="$2"
  local p t
  printf '1 1\n'
  for p in $(seq_values "$max_procs"); do
    for t in $(seq_values "$max_threads"); do
      if (( p == 1 && t == 1 )); then
        continue
      fi
      if (( p * t <= LOGICAL_CPUS )); then
        if (( p == 1 || t == 1 || p == t || p * t == PHYSICAL_CPUS )); then
          printf '%s %s\n' "$p" "$t"
        fi
      fi
    done
  done | sort -n -k1,1 -k2,2 | awk '!seen[$0]++'
}

extract_app_time() {
  local file="$1"
  awk '
    /TIEMPO/ {
      for (i = 1; i <= NF; ++i) {
        gsub(",", ".", $i)
        if ($i ~ /^[0-9]+(\.[0-9]+)?$/) {
          value = $i
        }
      }
    }
    END {
      if (value != "") {
        print value
      }
    }
  ' "$file"
}

extract_time_metric() {
  local file="$1"
  local key="$2"
  awk -v wanted="$key" '$1 == wanted { print $2 }' "$file" | tail -n 1
}

best_number() {
  sort -n | head -n 1
}

avg_number() {
  awk '{s += $1; n += 1} END {if (n) printf "%.6f\n", s / n}'
}

run_timed() {
  local label="$1"
  local kind="$2"
  local procs="$3"
  local threads="$4"
  shift 4
  local -a cmd=( "$@" )
  local stdout_file="$RAW_DIR/${label}.out"
  local stderr_file="$RAW_DIR/${label}.time"
  local app_values_file="$RAW_DIR/${label}.app_times"
  local real_values_file="$RAW_DIR/${label}.real_times"
  local user_values_file="$RAW_DIR/${label}.user_times"
  local sys_values_file="$RAW_DIR/${label}.sys_times"
  : > "$app_values_file"
  : > "$real_values_file"
  : > "$user_values_file"
  : > "$sys_values_file"

  local rep
  for ((rep = 1; rep <= REPEATS; rep++)); do
    if [[ "$threads" -gt 0 ]]; then
      OMP_NUM_THREADS="$threads" OMP_PROC_BIND=close OMP_PLACES=cores \
        "$TIME_BIN" -p "${cmd[@]}" > "${stdout_file}.${rep}" 2> "${stderr_file}.${rep}"
    else
      "$TIME_BIN" -p "${cmd[@]}" > "${stdout_file}.${rep}" 2> "${stderr_file}.${rep}"
    fi

    extract_app_time "${stdout_file}.${rep}" >> "$app_values_file"
    extract_time_metric "${stderr_file}.${rep}" real >> "$real_values_file"
    extract_time_metric "${stderr_file}.${rep}" user >> "$user_values_file"
    extract_time_metric "${stderr_file}.${rep}" sys >> "$sys_values_file"
  done

  local app_time real_time user_time sys_time cpu_eff
  app_time="$(best_number < "$app_values_file")"
  real_time="$(best_number < "$real_values_file")"
  user_time="$(avg_number < "$user_values_file")"
  sys_time="$(avg_number < "$sys_values_file")"
  cpu_eff="$(awk -v u="$user_time" -v s="$sys_time" -v r="$real_time" 'BEGIN { if (r > 0) printf "%.3f", (u + s) / r; else print "0.000" }')"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$kind" "$procs" "$threads" "$app_time" "$real_time" "$user_time" "$cpu_eff" \
    >> "$RESULTS_TSV"
}

run_benchmarks() {
  printf 'mode\tprocs\tthreads\tapp_time\treal_time\tuser_time\tcpu_eff\n' > "$RESULTS_TSV"

  log "Ejecutando secuencial"
  run_timed "seq_1" "seq" 1 0 "$SEQ_BIN"

  log "Barrido OpenMP hasta $MAX_OMP_THREADS hilos"
  local t
  for t in $(seq_values "$MAX_OMP_THREADS"); do
    run_timed "omp_${t}" "omp" 1 "$t" "$OMP_BIN"
  done

  if [[ -n "$MPIRUN_BIN" && -n "$MPI_BIN" ]]; then
    log "Barrido MPI hasta $MAX_MPI_PROCS procesos"
    local p
    for p in $(seq_values "$MAX_MPI_PROCS"); do
      local -a mpi_cmd=( "$MPIRUN_BIN" "-np" "$p" )
      [[ -n "$HOSTFILE" ]] && mpi_cmd+=( "--hostfile" "$HOSTFILE" )
      mpi_cmd+=( "$MPI_BIN" )
      run_timed "mpi_${p}" "mpi" "$p" 0 "${mpi_cmd[@]}"
    done
  fi

  if [[ "$RUN_HYBRID" -eq 1 && -n "$MPIRUN_BIN" && -n "$HYB_BIN" ]]; then
    log "Barrido híbrido MPI+OpenMP"
    while read -r p t; do
      local -a hyb_cmd=( "$MPIRUN_BIN" "-np" "$p" )
      [[ -n "$HOSTFILE" ]] && hyb_cmd+=( "--hostfile" "$HOSTFILE" )
      hyb_cmd+=( "$HYB_BIN" )
      run_timed "hyb_${p}x${t}" "hybrid" "$p" "$t" "${hyb_cmd[@]}"
    done < <(hybrid_pairs "$MAX_MPI_PROCS" "$MAX_OMP_THREADS")
  fi
}

line_of_pattern() {
  local file="$1"
  local pattern="$2"
  grep -n "$pattern" "$file" | head -n 1 | cut -d: -f1
}

static_analysis() {
  : > "$STATIC_TXT"
  {
    echo "Hallazgos estáticos"
    echo "==================="
    echo

    local loop_line mod_line div_line omp_cancel_line mpi_allreduce_line mpi_send_line
    loop_line="$(line_of_pattern "$SEQ_SRC" 'indice_a_cadena(i, LONGITUD_CONTRASENA, cadena)')"
    mod_line="$(line_of_pattern "$SEQ_SRC" 'indice % NUM_CAR')"
    div_line="$(line_of_pattern "$SEQ_SRC" 'indice= indice / NUM_CAR')"
    omp_cancel_line="$(grep -n 'omp cancel\|break' "$OMP_SRC" || true)"
    mpi_allreduce_line="$(line_of_pattern "$MPI_SRC" 'MPI_Allreduce')"
    mpi_send_line="$(line_of_pattern "$MPI_SRC" 'MPI_Send')"

    if [[ -n "$loop_line" && -n "$mod_line" && -n "$div_line" ]]; then
      echo "- Generación de candidatos en el hot path: [${SEQ_SRC}:${loop_line}] llama a [${SEQ_SRC}:${mod_line}] y [${SEQ_SRC}:${div_line}] en cada iteración. Eso implica varias divisiones y módulos enteros por contraseña probada."
    fi

    if [[ -z "$omp_cancel_line" ]]; then
      echo "- No hay salida temprana real en OpenMP: aunque un hilo encuentre la contraseña, el resto del `parallel for` sigue recorriendo su rango completo."
    fi

    if grep -q 'for (long long i = inicio; i < final; i++)' "$MPI_SRC"; then
      echo "- La versión MPI también recorre el rango completo de cada proceso antes de comunicar el resultado. El trabajo no se corta al encontrar la contraseña."
    fi

    if [[ -n "$mpi_allreduce_line" && -n "$mpi_send_line" ]]; then
      echo "- La comunicación MPI es mínima y ocurre al final: un `MPI_Allreduce` y, como mucho, un `MPI_Send/MPI_Recv` de 7 bytes. Si MPI se estanca, la primera sospecha no debería ser la red."
    fi
  } >> "$STATIC_TXT"
}

compile_probe_sources() {
  cat > "$WORKDIR/omp_runtime_probe.c" <<'EOF'
#include <omp.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  long long iterations = 2176782336LL;
  if (argc > 1) {
    iterations = atoll(argv[1]);
  }
  volatile unsigned long long sink = 0;
  double start = omp_get_wtime();
  #pragma omp parallel for reduction(+:sink)
  for (long long i = 0; i < iterations; ++i) {
    sink += (unsigned long long)(i & 1ULL);
  }
  double end = omp_get_wtime();
  printf("PROBE_OMP_TIME %.6f\n", end - start);
  if (sink == 0xdeadbeefULL) {
    printf("ignore %llu\n", sink);
  }
  return 0;
}
EOF

  cat > "$WORKDIR/mpi_runtime_probe.c" <<'EOF'
#include <mpi.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
  MPI_Init(&argc, &argv);
  int rank, size;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);

  int local = (rank == 0) ? 1 : 0;
  int global = 0;
  char payload[8] = "asd123";
  char recvbuf[8] = {0};

  MPI_Barrier(MPI_COMM_WORLD);
  double start = MPI_Wtime();
  MPI_Allreduce(&local, &global, 1, MPI_INT, MPI_MAX, MPI_COMM_WORLD);
  if (size > 1) {
    if (rank == 0) {
      MPI_Recv(recvbuf, sizeof(recvbuf), MPI_CHAR, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    } else if (rank == 1) {
      MPI_Send(payload, sizeof(payload), MPI_CHAR, 0, 0, MPI_COMM_WORLD);
    }
  }
  double end = MPI_Wtime();

  if (rank == 0) {
    printf("PROBE_MPI_TIME %.6f\n", end - start);
  }

  MPI_Finalize();
  return 0;
}
EOF

  gcc "-${OPT_LEVEL}" -fopenmp "$WORKDIR/omp_runtime_probe.c" -o "$WORKDIR/omp_runtime_probe"
  if [[ -n "$MPIRUN_BIN" ]]; then
    mpicc "-${OPT_LEVEL}" "$WORKDIR/mpi_runtime_probe.c" -o "$WORKDIR/mpi_runtime_probe"
  fi
}

probe_time_from_output() {
  local file="$1"
  awk '{print $NF}' "$file" | tail -n 1
}

run_probes() {
  : > "$PROBES_TXT"
  compile_probe_sources

  local seq_time
  seq_time="$(awk -F '\t' '$1 == "seq" { print $4 }' "$RESULTS_TSV" | head -n 1)"

  {
    echo "Micropruebas"
    echo "============"
    echo
  } >> "$PROBES_TXT"

  local best_omp_thread best_mpi_proc
  best_omp_thread="$(awk -F '\t' '$1 == "omp" { if (best == "" || $4 < best) { best = $4; cfg = $3 } } END { print cfg }' "$RESULTS_TSV")"
  if [[ -n "$best_omp_thread" ]]; then
    OMP_NUM_THREADS="$best_omp_thread" "$WORKDIR/omp_runtime_probe" > "$RAW_DIR/omp_probe.out"
    local omp_probe_time
    omp_probe_time="$(probe_time_from_output "$RAW_DIR/omp_probe.out")"
    echo "- Overhead bruto del runtime OpenMP con $best_omp_thread hilos: ${omp_probe_time}s" >> "$PROBES_TXT"
    if [[ -n "$seq_time" ]]; then
      awk -v p="$omp_probe_time" -v s="$seq_time" 'BEGIN { if (s > 0) printf "- Fracción frente al secuencial O3: %.4f%%\n", (p / s) * 100 }' >> "$PROBES_TXT"
    fi
  fi

  best_mpi_proc="$(awk -F '\t' '$1 == "mpi" { if (best == "" || $4 < best) { best = $4; cfg = $2 } } END { print cfg }' "$RESULTS_TSV")"
  if [[ -n "$best_mpi_proc" && -n "$MPIRUN_BIN" ]]; then
    local -a probe_cmd=( "$MPIRUN_BIN" "-np" "$best_mpi_proc" )
    [[ -n "$HOSTFILE" ]] && probe_cmd+=( "--hostfile" "$HOSTFILE" )
    probe_cmd+=( "$WORKDIR/mpi_runtime_probe" )
    "${probe_cmd[@]}" > "$RAW_DIR/mpi_probe.out"
    local mpi_probe_time
    mpi_probe_time="$(probe_time_from_output "$RAW_DIR/mpi_probe.out")"
    echo "- Coste bruto de un `MPI_Allreduce` + mensaje pequeño con $best_mpi_proc procesos: ${mpi_probe_time}s" >> "$PROBES_TXT"
    if [[ -n "$seq_time" ]]; then
      awk -v p="$mpi_probe_time" -v s="$seq_time" 'BEGIN { if (s > 0) printf "- Fracción frente al secuencial O3: %.6f%%\n", (p / s) * 100 }' >> "$PROBES_TXT"
    fi
  fi
}

run_perf_if_possible() {
  [[ "$PERF_AVAILABLE" -eq 1 ]] || return 0

  {
    echo
    echo "perf stat"
    echo "========="
  } >> "$PROBES_TXT"

  perf stat -x, -e cycles,instructions,cache-references,cache-misses \
    "$SEQ_BIN" > /dev/null 2> "$RAW_DIR/perf_seq.csv" || true
  echo "- Guardado perf secuencial en $RAW_DIR/perf_seq.csv" >> "$PROBES_TXT"

  local best_omp_thread
  best_omp_thread="$(awk -F '\t' '$1 == "omp" { if (best == "" || $4 < best) { best = $4; cfg = $3 } } END { print cfg }' "$RESULTS_TSV")"
  if [[ -n "$best_omp_thread" ]]; then
    OMP_NUM_THREADS="$best_omp_thread" perf stat -x, -e cycles,instructions,cache-references,cache-misses \
      "$OMP_BIN" > /dev/null 2> "$RAW_DIR/perf_omp.csv" || true
    echo "- Guardado perf OpenMP en $RAW_DIR/perf_omp.csv" >> "$PROBES_TXT"
  fi
}

emit_summary_table() {
  local seq_time
  seq_time="$(awk -F '\t' '$1 == "seq" { print $4 }' "$RESULTS_TSV" | head -n 1)"
  {
    echo "Resumen de tiempos"
    echo "=================="
    echo
    printf '%-8s %-6s %-7s %-11s %-10s %-10s %-10s %-10s\n' "modo" "proc" "hilos" "app_time" "speedup" "eff" "cpu_eff" "real"
    awk -F '\t' -v seq="$seq_time" '
      NR == 1 { next }
      {
        workers = ($1 == "seq") ? 1 : (($1 == "omp") ? $3 : (($1 == "mpi") ? $2 : $2 * $3))
        speedup = (seq > 0 && $4 > 0) ? seq / $4 : 0
        eff = (workers > 0) ? speedup / workers : 0
        printf "%-8s %-6s %-7s %-11.6f %-10.3f %-10.3f %-10.3f %-10.6f\n", $1, $2, $3, $4, speedup, eff, $7, $5
      }
    ' "$RESULTS_TSV"
    echo
  } >> "$REPORT_TXT"
}

plateau_point() {
  local mode="$1"
  awk -F '\t' -v wanted="$mode" '
    $1 == wanted {
      workers = (wanted == "omp") ? $3 : ((wanted == "mpi") ? $2 : $2 * $3)
      time = $4 + 0.0
      if (count == 0) {
        prev_workers = workers
        prev_time = time
        count = 1
        next
      }
      improvement = (prev_time - time) / prev_time
      if (!plateau && improvement < 0.10) {
        plateau = workers
      }
      prev_workers = workers
      prev_time = time
      count += 1
    }
    END {
      if (plateau) print plateau
    }
  ' "$RESULTS_TSV"
}

best_workers() {
  local mode="$1"
  awk -F '\t' -v wanted="$mode" '
    $1 == wanted {
      workers = (wanted == "omp") ? $3 : ((wanted == "mpi") ? $2 : $2 * $3)
      if (best == "" || $4 < best) {
        best = $4
        best_workers = workers
      }
    }
    END { print best_workers }
  ' "$RESULTS_TSV"
}

best_cpu_eff() {
  local mode="$1"
  awk -F '\t' -v wanted="$mode" '
    $1 == wanted {
      if (best == "" || $4 < best) {
        best = $4
        cpu = $7
      }
    }
    END { print cpu }
  ' "$RESULTS_TSV"
}

diagnose() {
  local omp_plateau mpi_plateau hyb_plateau omp_best mpi_best hyb_best omp_cpu mpi_cpu hyb_cpu
  omp_plateau="$(plateau_point omp)"
  mpi_plateau="$(plateau_point mpi)"
  hyb_plateau="$(plateau_point hybrid)"
  omp_best="$(best_workers omp)"
  mpi_best="$(best_workers mpi)"
  hyb_best="$(best_workers hybrid)"
  omp_cpu="$(best_cpu_eff omp)"
  mpi_cpu="$(best_cpu_eff mpi)"
  hyb_cpu="$(best_cpu_eff hybrid)"

  {
    echo "Diagnóstico"
    echo "==========="
    echo
    echo "- CPU físicas detectadas: $PHYSICAL_CPUS"
    echo "- CPU lógicas detectadas: $LOGICAL_CPUS"
    echo

    if [[ -n "$omp_plateau" ]]; then
      echo "- OpenMP se aplana alrededor de $omp_plateau hilos."
      awk -v c="$omp_cpu" -v p="$PHYSICAL_CPUS" 'BEGIN {
        if (c >= p * 0.75) {
          printf "  Evidencia: la CPU efectiva en la mejor configuración OpenMP es %.3f, cerca del límite físico. La causa principal apunta a saturación de núcleos / throughput de CPU, no a falta de hilos.\n", c
        } else {
          printf "  Evidencia: la CPU efectiva en la mejor configuración OpenMP es %.3f, lejos del límite físico. Revisa afinidad, tamaño del problema o contención externa.\n", c
        }
      }'
    fi

    if [[ -n "$mpi_plateau" ]]; then
      echo "- MPI se aplana alrededor de $mpi_plateau procesos."
      if [[ -f "$RAW_DIR/mpi_probe.out" ]]; then
        local mpi_probe_time
        mpi_probe_time="$(probe_time_from_output "$RAW_DIR/mpi_probe.out")"
        awk -v p="$mpi_probe_time" 'BEGIN {
          if (p < 0.01) {
            printf "  Evidencia: el coste medido de las primitivas MPI del programa es %.6fs, demasiado pequeño para explicar tiempos de varios segundos. La red/colectivas no son el cuello principal.\n", p
          } else {
            printf "  Evidencia: el coste medido de las primitivas MPI es %.6fs. Aun así, compáralo con el tiempo total antes de culpar a la red.\n", p
          }
        }'
      fi
      awk -v c="$mpi_cpu" -v p="$PHYSICAL_CPUS" 'BEGIN {
        if (c >= p * 0.75) {
          printf "  Evidencia adicional: la CPU efectiva en la mejor configuración MPI es %.3f. El estancamiento encaja con saturación de cores disponibles.\n", c
        } else {
          printf "  Evidencia adicional: la CPU efectiva en la mejor configuración MPI es %.3f. Si no escala, revisa hostfile, mapeo de procesos y afinidad.\n", c
        }
      }'
    fi

    if [[ -n "$hyb_best" ]]; then
      echo "- La mejor configuración híbrida usa $hyb_best workers totales."
      awk -v c="$hyb_cpu" -v p="$PHYSICAL_CPUS" 'BEGIN {
        if (c >= p * 0.75) {
          printf "  Evidencia: la versión híbrida también consume cerca de la capacidad física (CPU efectiva %.3f). Si no mejora frente a MPI, es porque MPI ya estaba saturando la máquina.\n", c
        } else {
          printf "  Evidencia: la CPU efectiva híbrida es %.3f. Si el rendimiento no mejora, probablemente hay sobrecoste de coordinación sin trabajo suficiente por worker.\n", c
        }
      }'
    fi

    echo
    echo "Cuellos de botella más probables en este código:"
    echo "- Generación de candidatos por división/módulo dentro del hot path."
    echo "- Ausencia de salida temprana: el espacio completo se sigue recorriendo incluso después de encontrar la contraseña."
    echo "- Saturación temprana de núcleos físicos disponibles cuando OpenMP o MPI dejan de escalar."
    echo "- La comunicación MPI solo debería considerarse culpable si en tu máquina la microprueba sale anormalmente alta."
  } >> "$REPORT_TXT"
}

main() {
  parse_args "$@"
  setup_paths
  detect_cpus
  detect_tools
  ensure_binaries

  : > "$REPORT_TXT"
  {
    echo "Detector de cuellos de botella"
    echo "=============================="
    echo
    echo "Repositorio: $ROOT_DIR"
    echo "Workdir: $WORKDIR"
    echo "Optimización: $OPT_LEVEL"
    echo "Repeticiones: $REPEATS"
    echo
  } >> "$REPORT_TXT"

  static_analysis
  run_benchmarks
  run_probes
  run_perf_if_possible

  cat "$STATIC_TXT" >> "$REPORT_TXT"
  echo >> "$REPORT_TXT"
  emit_summary_table
  cat "$PROBES_TXT" >> "$REPORT_TXT"
  echo >> "$REPORT_TXT"
  diagnose

  log "Informe generado en $REPORT_TXT"
  log "Resultados tabulados en $RESULTS_TSV"
}

main "$@"
