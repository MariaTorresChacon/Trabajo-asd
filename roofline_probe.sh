#!/usr/bin/env bash
set -euo pipefail

# Real bandwidth probe for Roofline/Arithmetic Intensity workflows.
# - Memory bandwidth: STREAM (Triad Best Rate).
# - Network bandwidth: iperf3 TCP tests against peer nodes.
# - Output: JSON summary + saved raw logs.
# - Cleanup: removes only packages installed by this script.

SCRIPT_NAME="$(basename "$0")"
WORKDIR="${WORKDIR:-$PWD/.roofline_probe}"
STREAM_URL="https://www.cs.virginia.edu/stream/FTP/Code/stream.c"
STREAM_ARRAY_SIZE="${STREAM_ARRAY_SIZE:-200000000}"
STREAM_NTIMES="${STREAM_NTIMES:-50}"
IPERF_PARALLEL="${IPERF_PARALLEL:-8}"
IPERF_SECONDS="${IPERF_SECONDS:-60}"
IPERF_PORT="${IPERF_PORT:-5201}"
JSON_OUT=""
PPEAK_GFLOPS=""

MODE="all"
PEERS=()
NO_CLEANUP=0
DO_INSTALL=1

usage() {
  cat <<EOF
Uso:
  $SCRIPT_NAME --all --peers IP1,IP2 [opciones]
  $SCRIPT_NAME --server [opciones]
  $SCRIPT_NAME --memory-only [opciones]
  $SCRIPT_NAME --net-only --peers IP1,IP2 [opciones]

Modos:
  --all              Ejecuta STREAM + red (cliente) + limpieza (default).
  --server           Solo arranca iperf3 en modo servidor.
  --memory-only      Solo benchmark de memoria (STREAM).
  --net-only         Solo benchmark de red (cliente iperf3 a peers).

Opciones:
  --peers LIST       Lista separada por coma (ej: 10.0.0.11,10.0.0.12).
  --ppeak GFLOPS     Pico de cómputo para calcular ridge point.
  --json-out PATH    Ruta de salida JSON (default: $WORKDIR/summary.json).
  --workdir PATH     Directorio temporal de trabajo.
  --array-size N     STREAM_ARRAY_SIZE (default: $STREAM_ARRAY_SIZE).
  --ntimes N         STREAM NTIMES (default: $STREAM_NTIMES).
  --iperf-p N        Flujos paralelos iperf3 (default: $IPERF_PARALLEL).
  --iperf-t N        Duración de test iperf3 en segundos (default: $IPERF_SECONDS).
  --iperf-port N     Puerto iperf3 (default: $IPERF_PORT).
  --no-cleanup       No desinstala paquetes al final.
  --no-install       No instala paquetes (falla si faltan).
  -h, --help         Mostrar ayuda.

Notas:
  - En modo red cliente, cada peer debe tener iperf3 server escuchando.
  - Si no quieres arrancar server manualmente en cada peer, ejecuta:
      sudo $SCRIPT_NAME --server
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Falta comando requerido: $1" >&2
    return 1
  }
}

join_by() {
  local d="$1"
  shift || true
  local first=1
  for x in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      printf '%s' "$x"
      first=0
    else
      printf '%s%s' "$d" "$x"
    fi
  done
}

to_bytes_per_second_from_mbps() {
  # decimal Mbps -> B/s
  local mbps="$1"
  awk -v x="$mbps" 'BEGIN { printf "%.0f", (x*1000000)/8 }'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        MODE="all"
        shift
        ;;
      --server)
        MODE="server"
        shift
        ;;
      --memory-only)
        MODE="memory-only"
        shift
        ;;
      --net-only)
        MODE="net-only"
        shift
        ;;
      --peers)
        IFS=',' read -r -a PEERS <<< "${2:-}"
        shift 2
        ;;
      --ppeak)
        PPEAK_GFLOPS="${2:-}"
        shift 2
        ;;
      --json-out)
        JSON_OUT="${2:-}"
        shift 2
        ;;
      --workdir)
        WORKDIR="${2:-}"
        shift 2
        ;;
      --array-size)
        STREAM_ARRAY_SIZE="${2:-}"
        shift 2
        ;;
      --ntimes)
        STREAM_NTIMES="${2:-}"
        shift 2
        ;;
      --iperf-p)
        IPERF_PARALLEL="${2:-}"
        shift 2
        ;;
      --iperf-t)
        IPERF_SECONDS="${2:-}"
        shift 2
        ;;
      --iperf-port)
        IPERF_PORT="${2:-}"
        shift 2
        ;;
      --no-cleanup)
        NO_CLEANUP=1
        shift
        ;;
      --no-install)
        DO_INSTALL=0
        shift
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

SUDO=""
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  SUDO="sudo"
fi

APT_NEW_FILE=""
cleanup_packages() {
  [[ "$NO_CLEANUP" -eq 1 ]] && return 0
  [[ -z "${APT_NEW_FILE:-}" ]] && return 0
  [[ ! -s "$APT_NEW_FILE" ]] && return 0

  mapfile -t pkgs < "$APT_NEW_FILE"
  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    return 0
  fi

  log "Desinstalando paquetes instalados por este script: $(join_by ',' "${pkgs[@]}")"
  $SUDO apt-get -y purge "${pkgs[@]}" >/dev/null
  $SUDO apt-get -y autoremove --purge >/dev/null
}

install_deps() {
  local required_pkgs=(build-essential numactl wget iperf3 jq bc)
  local before after
  before="$(mktemp)"
  after="$(mktemp)"
  APT_NEW_FILE="$WORKDIR/new_packages.txt"
  mkdir -p "$WORKDIR"

  dpkg-query -W -f='${binary:Package}\n' | sort > "$before"
  log "Instalando dependencias: ${required_pkgs[*]}"
  $SUDO apt-get update -y >/dev/null
  $SUDO apt-get install -y "${required_pkgs[@]}" >/dev/null
  dpkg-query -W -f='${binary:Package}\n' | sort > "$after"
  comm -13 "$before" "$after" > "$APT_NEW_FILE" || true
  rm -f "$before" "$after"
}

ensure_deps_available() {
  local deps=(gcc numactl wget iperf3 jq awk sed grep nproc)
  for c in "${deps[@]}"; do
    require_cmd "$c"
  done
}

run_stream() {
  mkdir -p "$WORKDIR"
  local stream_c="$WORKDIR/stream.c"
  local stream_bin="$WORKDIR/stream"
  local log_out="$WORKDIR/stream.out"
  local cpu_threads
  cpu_threads="$(nproc)"

  log "Descargando STREAM source"
  wget -q -O "$stream_c" "$STREAM_URL"

  log "Compilando STREAM (ARRAY_SIZE=$STREAM_ARRAY_SIZE, NTIMES=$STREAM_NTIMES)"
  gcc -O3 -march=native -fopenmp \
    -DSTREAM_ARRAY_SIZE="$STREAM_ARRAY_SIZE" \
    -DNTIMES="$STREAM_NTIMES" \
    "$stream_c" -o "$stream_bin"

  export OMP_NUM_THREADS="$cpu_threads"
  export OMP_PLACES=cores
  export OMP_PROC_BIND=spread

  log "Ejecutando STREAM con $OMP_NUM_THREADS hilos"
  numactl --interleave=all "$stream_bin" | tee "$log_out" >/dev/null

  local triad_mbs
  triad_mbs="$(awk '/Triad:/{print $2}' "$log_out" | tail -n1)"
  if [[ -z "$triad_mbs" ]]; then
    echo "No se pudo parsear Triad Best Rate de STREAM" >&2
    return 1
  fi

  local triad_bps
  triad_bps="$(awk -v x="$triad_mbs" 'BEGIN { printf "%.0f", x*1000000 }')"

  printf '%s\n' "$triad_mbs" > "$WORKDIR/stream_triad_mbs.txt"
  printf '%s\n' "$triad_bps" > "$WORKDIR/stream_triad_Bps.txt"
}

start_iperf_server() {
  log "Arrancando iperf3 server en puerto $IPERF_PORT (Ctrl+C para salir)"
  exec iperf3 -s -p "$IPERF_PORT"
}

run_iperf_client_one() {
  local peer="$1"
  local out_fwd="$WORKDIR/iperf_${peer//./_}_fwd.json"
  local out_rev="$WORKDIR/iperf_${peer//./_}_rev.json"
  local fwd_bps rev_bps fwd_mbps rev_mbps agg_mbps agg_bps

  log "Probando red contra $peer (forward)"
  iperf3 -c "$peer" -p "$IPERF_PORT" -P "$IPERF_PARALLEL" -t "$IPERF_SECONDS" -J > "$out_fwd"
  log "Probando red contra $peer (reverse)"
  iperf3 -c "$peer" -p "$IPERF_PORT" -P "$IPERF_PARALLEL" -t "$IPERF_SECONDS" -R -J > "$out_rev"

  fwd_bps="$(jq -r '.end.sum_received.bits_per_second // .end.sum.bits_per_second // 0' "$out_fwd")"
  rev_bps="$(jq -r '.end.sum_received.bits_per_second // .end.sum.bits_per_second // 0' "$out_rev")"
  fwd_mbps="$(awk -v b="$fwd_bps" 'BEGIN { printf "%.3f", b/1000000 }')"
  rev_mbps="$(awk -v b="$rev_bps" 'BEGIN { printf "%.3f", b/1000000 }')"
  agg_mbps="$(awk -v a="$fwd_mbps" -v b="$rev_mbps" 'BEGIN { printf "%.3f", a+b }')"
  agg_bps="$(to_bytes_per_second_from_mbps "$agg_mbps")"

  jq -n \
    --arg peer "$peer" \
    --argjson fwd_bps "$fwd_bps" \
    --argjson rev_bps "$rev_bps" \
    --argjson fwd_mbps "$fwd_mbps" \
    --argjson rev_mbps "$rev_mbps" \
    --argjson agg_mbps "$agg_mbps" \
    --argjson agg_Bps "$agg_bps" \
    '{
      peer: $peer,
      forward_mbps: $fwd_mbps,
      reverse_mbps: $rev_mbps,
      aggregate_mbps: $agg_mbps,
      aggregate_Bps: $agg_Bps,
      raw_bits_per_second: { forward: $fwd_bps, reverse: $rev_bps }
    }'
}

run_network_suite() {
  mkdir -p "$WORKDIR"
  if [[ "${#PEERS[@]}" -eq 0 ]]; then
    echo "Debes indicar --peers para test de red." >&2
    return 1
  fi

  local results_file="$WORKDIR/network_results.ndjson"
  : > "$results_file"
  local ok=0
  local fail=0

  for peer in "${PEERS[@]}"; do
    if run_iperf_client_one "$peer" >> "$results_file"; then
      ok=$((ok+1))
    else
      log "Fallo test con peer $peer"
      fail=$((fail+1))
    fi
  done

  jq -s . "$results_file" > "$WORKDIR/network_results.json"

  local p50 p90 max avg
  p50="$(jq -r 'map(.aggregate_mbps) | sort | if length==0 then 0 else .[(length*0.50|floor)] end' "$WORKDIR/network_results.json")"
  p90="$(jq -r 'map(.aggregate_mbps) | sort | if length==0 then 0 else .[(length*0.90|floor)] end' "$WORKDIR/network_results.json")"
  max="$(jq -r 'map(.aggregate_mbps) | if length==0 then 0 else max end' "$WORKDIR/network_results.json")"
  avg="$(jq -r 'map(.aggregate_mbps) | if length==0 then 0 else (add/length) end' "$WORKDIR/network_results.json")"

  jq -n \
    --argjson peers_ok "$ok" \
    --argjson peers_fail "$fail" \
    --argjson agg_mbps_p50 "$p50" \
    --argjson agg_mbps_p90 "$p90" \
    --argjson agg_mbps_avg "$avg" \
    --argjson agg_mbps_max "$max" \
    --argjson agg_Bps_p50 "$(to_bytes_per_second_from_mbps "$p50")" \
    --argjson agg_Bps_p90 "$(to_bytes_per_second_from_mbps "$p90")" \
    --argjson agg_Bps_avg "$(to_bytes_per_second_from_mbps "$avg")" \
    --argjson agg_Bps_max "$(to_bytes_per_second_from_mbps "$max")" \
    '{
      peers_ok: $peers_ok,
      peers_fail: $peers_fail,
      aggregate_mbps: {
        p50: $agg_mbps_p50,
        p90: $agg_mbps_p90,
        avg: $agg_mbps_avg,
        max: $agg_mbps_max
      },
      aggregate_Bps: {
        p50: $agg_Bps_p50,
        p90: $agg_Bps_p90,
        avg: $agg_Bps_avg,
        max: $agg_Bps_max
      }
    }' > "$WORKDIR/network_summary.json"
}

build_summary() {
  mkdir -p "$WORKDIR"
  [[ -n "$JSON_OUT" ]] || JSON_OUT="$WORKDIR/summary.json"

  local has_stream=0
  local has_net=0
  [[ -f "$WORKDIR/stream_triad_mbs.txt" ]] && has_stream=1
  [[ -f "$WORKDIR/network_summary.json" ]] && has_net=1

  local stream_mbs stream_Bps ridge_ai
  stream_mbs=0
  stream_Bps=0
  ridge_ai=null

  if [[ "$has_stream" -eq 1 ]]; then
    stream_mbs="$(cat "$WORKDIR/stream_triad_mbs.txt")"
    stream_Bps="$(cat "$WORKDIR/stream_triad_Bps.txt")"
    if [[ -n "$PPEAK_GFLOPS" ]]; then
      ridge_ai="$(awk -v p="$PPEAK_GFLOPS" -v b="$stream_Bps" 'BEGIN { if (b>0) printf "%.6f", (p*1e9)/b; else print "null" }')"
    fi
  fi

  jq -n \
    --arg mode "$MODE" \
    --arg host "$(hostname)" \
    --arg date_utc "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg workdir "$WORKDIR" \
    --argjson stream_present "$has_stream" \
    --argjson net_present "$has_net" \
    --argjson stream_mbs "$stream_mbs" \
    --argjson stream_Bps "$stream_Bps" \
    --argjson ppeak_gflops "${PPEAK_GFLOPS:-null}" \
    --argjson ridge_ai "${ridge_ai}" \
    --slurpfile net "$WORKDIR/network_summary.json" \
    --slurpfile net_detail "$WORKDIR/network_results.json" \
    '{
      host: $host,
      timestamp_utc: $date_utc,
      mode: $mode,
      workdir: $workdir,
      memory: (if $stream_present==1 then {
        stream_triad_MBps: $stream_mbs,
        stream_triad_Bps: $stream_Bps
      } else null end),
      network: (if $net_present==1 then {
        summary: ($net[0] // null),
        peer_results: ($net_detail[0] // [])
      } else null end),
      roofline: (if ($stream_present==1 and $ppeak_gflops != null) then {
        ppeak_GFLOPs: $ppeak_gflops,
        ridge_point_FLOP_per_Byte: $ridge_ai
      } else null end)
    }' > "$JSON_OUT"
}

print_human_report() {
  local report="$1"
  echo
  echo "===== RESULTADOS ====="
  jq -r '
    "Host: " + .host,
    "Fecha UTC: " + .timestamp_utc,
    "Modo: " + .mode,
    (if .memory != null then
      "BW memoria real (STREAM Triad): \(.memory.stream_triad_MBps) MB/s"
    else
      "BW memoria real: n/a"
    end),
    (if .network != null then
      "BW red agregada p50/p90/avg/max (Mb/s): \(.network.summary.aggregate_mbps.p50)/\(.network.summary.aggregate_mbps.p90)/\(.network.summary.aggregate_mbps.avg)/\(.network.summary.aggregate_mbps.max)"
    else
      "BW red: n/a"
    end),
    (if .roofline != null then
      "Ridge point IA (FLOP/Byte): \(.roofline.ridge_point_FLOP_per_Byte)"
    else
      "Ridge point IA: n/a (usa --ppeak GFLOPS)"
    end),
    "JSON completo: '"$report"'"
  ' "$report"
  echo "======================"
  echo
}

main() {
  parse_args "$@"
  mkdir -p "$WORKDIR"

  trap 'cleanup_packages' EXIT

  if [[ "$DO_INSTALL" -eq 1 ]]; then
    install_deps
  fi

  ensure_deps_available

  case "$MODE" in
    server)
      start_iperf_server
      ;;
    memory-only)
      run_stream
      build_summary
      print_human_report "${JSON_OUT:-$WORKDIR/summary.json}"
      ;;
    net-only)
      run_network_suite
      build_summary
      print_human_report "${JSON_OUT:-$WORKDIR/summary.json}"
      ;;
    all)
      run_stream
      run_network_suite
      build_summary
      print_human_report "${JSON_OUT:-$WORKDIR/summary.json}"
      ;;
    *)
      echo "Modo no soportado: $MODE" >&2
      exit 1
      ;;
  esac

  if [[ "$NO_CLEANUP" -eq 1 ]]; then
    log "Se omitió cleanup por --no-cleanup"
  else
    log "Cleanup automático completado."
  fi
}

main "$@"
