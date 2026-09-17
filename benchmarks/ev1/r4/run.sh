#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_EXE="${UPSTREAM_EXE:?set UPSTREAM_EXE}"
D2_EXE="${D2_EXE:?set D2_EXE}"
RUN_ROOT="${RUN_ROOT:?set RUN_ROOT}"
REPEATS="${REPEATS:-3}"
SCENARIOS="${SCENARIOS:-sparse moderate}"

if [[ -e "$RUN_ROOT" ]]; then
  echo "refusing to reuse $RUN_ROOT" >&2
  exit 2
fi
mkdir -p "$RUN_ROOT"

run_upstream() {
  local mode="$1" storage="$2" chain="$3" output="$4" log="$5" timing="$6" metadata="$7" post_h="$8"
  mkdir -p "$(dirname "$output")" "$(dirname "$log")"
  local -a worker_env=(
    "RUST_LOG=warn" "G2_QUIET_LOG=1" "G2_MODE=$mode" "G2_WORKLOAD=$WORKLOAD"
    "G2_STORAGE=$storage" "G2_CHAIN_DB=$chain" "G2_HANDOFF_HEIGHT=$HANDOFF"
    "G2_TRANSACTION_COUNT=$TX_COUNT" "G2_OUTPUTS_PER_TRANSACTION=$OUTPUTS_PER_TRANSACTION"
    "G2_BATCH_SIZE=$BATCH_SIZE" "G2_MATCH_GAP=$MATCH_GAP" "G2_METADATA=$metadata"
    "G2_OUTPUT=$output" "G2_POST_H_OUTPUT=$post_h"
  )
  if [[ -n "${FILTER_CACHE_INPUT:-}" ]]; then
    worker_env+=("G2_FILTER_CACHE_INPUT=$FILTER_CACHE_INPUT")
  fi
  env "${worker_env[@]}" /usr/bin/time -f 'elapsed_s=%e cpu=%P max_rss_kb=%M' -o "$timing" \
    "$UPSTREAM_EXE" 'tests::rp2_authority_replay::g2_realism_worker' --exact --ignored --nocapture \
    >"$log" 2>&1
}

run_d2() {
  local mode="$1" storage="$2" script_hex="$3" artifact="$4" result="$5" log="$6" timing="$7"
  mkdir -p "$(dirname "$result")" "$(dirname "$log")"
  env D2_G2_MODE="$mode" D2_G2_STORAGE="$storage" D2_G2_ARTIFACT="$artifact" \
    D2_G2_SCRIPT="$script_hex" D2_G2_RESULT="$result" \
    /usr/bin/time -f 'elapsed_s=%e cpu=%P max_rss_kb=%M' -o "$timing" \
    "$D2_EXE" 'upstream::tests::production_g2_worker' --exact --ignored --nocapture \
    >"$log" 2>&1
}

storage_bytes() { du -sb "$1" | awk '{print $1}'; }

for scenario in $SCENARIOS; do
  if [[ "$scenario" == h36 ]]; then
    WORKLOAD='CONTROLLED-H36-HARNESS-GATE'; HANDOFF=36; TX_COUNT=1; MATCH_GAP=0; OUTPUTS_PER_TRANSACTION=1; BATCH_SIZE=1
  elif [[ "$scenario" == sparse ]]; then
    WORKLOAD='CONTROLLED-SCALED-SPARSE'; HANDOFF=10000; TX_COUNT=100; MATCH_GAP=100; OUTPUTS_PER_TRANSACTION=1; BATCH_SIZE=1
  elif [[ "$scenario" == moderate ]]; then
    WORKLOAD='CONTROLLED-MODERATE-CONTROL'; HANDOFF=5000; TX_COUNT=996; MATCH_GAP=10; OUTPUTS_PER_TRANSACTION=4; BATCH_SIZE=2
  else
    echo "unknown scenario: $scenario" >&2; exit 1
  fi

  SCENARIO_ROOT="$RUN_ROOT/$scenario"; mkdir -p "$SCENARIO_ROOT"
  for repetition in $(seq 1 "$REPEATS"); do
    REP_ROOT="$SCENARIO_ROOT/run-$repetition"; EVIDENCE="$REP_ROOT/evidence"; mkdir -p "$EVIDENCE"
    METADATA="$EVIDENCE/metadata.json"; ARTIFACT="$EVIDENCE/handoff.d2"; POST_H="$EVIDENCE/post-h.json"
    SOURCE_STORAGE="$REP_ROOT/source-storage"; SOURCE_CHAIN="$REP_ROOT/source-chain-db"
    D2_STORAGE="$REP_ROOT/d2-destination-storage"; D2_CHAIN="$REP_ROOT/d2-destination-chain-db"
    BASE_STORAGE="$REP_ROOT/baseline-storage"; BASE_CHAIN="$REP_ROOT/baseline-chain-db"

    run_upstream prepare-source "$SOURCE_STORAGE" "$SOURCE_CHAIN" "$EVIDENCE/source-preparation.json" "$EVIDENCE/source-preparation.log" "$EVIDENCE/source-preparation.time" "$METADATA" "$POST_H"
    FILTER_CACHE_INPUT="$EVIDENCE/source-preparation.json" run_upstream validate-cache "$SOURCE_STORAGE" "$SOURCE_CHAIN" "$EVIDENCE/filter-cache-validation.json" "$EVIDENCE/filter-cache-validation.log" "$EVIDENCE/filter-cache-validation.time" "$METADATA" "$POST_H"
    SCRIPT_HEX="$(sed -n 's/.*\"script_hex\": \"\([^\"]*\)\".*/\1/p' "$METADATA")"
    [[ -n "$SCRIPT_HEX" ]] || { echo "script_hex missing" >&2; exit 1; }
    # Public D2 has no private registration-check mode. Export is the public
    # registration/identity gate and reports backend, handoff height, and rows.
    run_d2 export "$SOURCE_STORAGE" "$SCRIPT_HEX" "$ARTIFACT" "$EVIDENCE/export.json" "$EVIDENCE/export.log" "$EVIDENCE/export.time"
    grep -q '"backend":"sqlite"' "$EVIDENCE/export.json"
    grep -q "\"handoff_height\":$HANDOFF" "$EVIDENCE/export.json"
    grep -Eq '"index_rows":[1-9][0-9]*' "$EVIDENCE/export.json"

    mkdir -p "$D2_CHAIN" "$BASE_CHAIN"
    /usr/bin/time -f 'elapsed_s=%e cpu=%P max_rss_kb=%M' -o "$EVIDENCE/provider-copy.time" \
      bash -c 'cp -a "$1"/. "$2"/ && cp -a "$1"/. "$3"/' _ "$SOURCE_CHAIN" "$D2_CHAIN" "$BASE_CHAIN"

    run_upstream prepare-destination "$D2_STORAGE" "$D2_CHAIN" "$EVIDENCE/d2-preparation.json" "$EVIDENCE/d2-preparation.log" "$EVIDENCE/d2-preparation.time" "$METADATA" "$POST_H"
    for d2_mode in inspect validate import reopen; do
      run_d2 "$d2_mode" "$D2_STORAGE" "$SCRIPT_HEX" "$ARTIFACT" "$EVIDENCE/d2-$d2_mode.json" "$EVIDENCE/d2-$d2_mode.log" "$EVIDENCE/d2-$d2_mode.time"
    done
    run_upstream append-post-h "$D2_STORAGE" "$D2_CHAIN" "$EVIDENCE/d2-post-h.json" "$EVIDENCE/d2-post-h.log" "$EVIDENCE/d2-post-h.time" "$METADATA" "$EVIDENCE/d2-post-h.json"
    FILTER_CACHE_INPUT="$EVIDENCE/source-preparation.json" run_upstream continue "$D2_STORAGE" "$D2_CHAIN" "$EVIDENCE/d2-continuation.json" "$EVIDENCE/d2-continuation.log" "$EVIDENCE/d2-continuation.time" "$METADATA" "$EVIDENCE/d2-post-h.json"

    run_upstream prepare-destination "$BASE_STORAGE" "$BASE_CHAIN" "$EVIDENCE/baseline-preparation.json" "$EVIDENCE/baseline-preparation.log" "$EVIDENCE/baseline-preparation.time" "$METADATA" "$POST_H"
    run_upstream rescan "$BASE_STORAGE" "$BASE_CHAIN" "$EVIDENCE/baseline-rescan.json" "$EVIDENCE/baseline-rescan.log" "$EVIDENCE/baseline-rescan.time" "$METADATA" "$POST_H"
    run_upstream append-post-h "$BASE_STORAGE" "$BASE_CHAIN" "$EVIDENCE/baseline-post-h.json" "$EVIDENCE/baseline-post-h.log" "$EVIDENCE/baseline-post-h.time" "$METADATA" "$EVIDENCE/baseline-post-h.json"
    FILTER_CACHE_INPUT="$EVIDENCE/baseline-rescan.json" run_upstream continue "$BASE_STORAGE" "$BASE_CHAIN" "$EVIDENCE/baseline-continuation.json" "$EVIDENCE/baseline-continuation.log" "$EVIDENCE/baseline-continuation.time" "$METADATA" "$EVIDENCE/d2-post-h.json"

    artifact_bytes="$(wc -c < "$ARTIFACT")"; d2_storage_bytes="$(storage_bytes "$D2_STORAGE")"; baseline_storage_bytes="$(storage_bytes "$BASE_STORAGE")"
    printf '{"scenario":"%s","workload":"%s","handoff_height":%s,"transaction_count":%s,"outputs_per_transaction":%s,"batch_size":%s,"match_gap":%s,"artifact_bytes":%s,"d2_storage_bytes":%s,"baseline_storage_bytes":%s}\n' "$scenario" "$WORKLOAD" "$HANDOFF" "$TX_COUNT" "$OUTPUTS_PER_TRANSACTION" "$BATCH_SIZE" "$MATCH_GAP" "$artifact_bytes" "$d2_storage_bytes" "$baseline_storage_bytes" > "$REP_ROOT/run.json"
  done
done

echo "completed $RUN_ROOT"
