#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

SAMPLES="${SAMPLES:-8}"
MAX_TIME="${MAX_TIME:-10}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-4}"
HAS_RG=0
if command -v rg >/dev/null 2>&1; then
  HAS_RG=1
fi

if ! [[ "$SAMPLES" =~ ^[0-9]+$ ]] || [ "$SAMPLES" -lt 1 ]; then
  echo "ERROR: SAMPLES must be a positive integer"
  exit 2
fi

if ! [[ "$MAX_TIME" =~ ^[0-9]+$ ]] || [ "$MAX_TIME" -lt 2 ]; then
  echo "ERROR: MAX_TIME must be an integer >= 2"
  exit 2
fi

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR=".analysis/perf/pipeline_probe_${TS}"
mkdir -p "$OUTDIR"

extract_secret() {
  local key="$1"
  local file value
  for file in Secrets.private.xcconfig Secrets.xcconfig; do
    [ -f "$file" ] || continue
    value=$(awk -v target="$key" '
      {
        line = $0
        if (line ~ /^[[:space:]]*\/\//) { next }
        pos = index(line, "=")
        if (pos == 0) { next }
        k = substr(line, 1, pos - 1)
        v = substr(line, pos + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if (k == target) {
          last = v
        }
      }
      END {
        if (length(last) > 0) {
          print last
        }
      }
    ' "$file" 2>/dev/null | tail -n1 | sed 's#\\/#/#g' | tr -d '\r')
    if [ -n "${value:-}" ]; then
      echo "$value"
      return
    fi
  done
}

trim_spaces() {
  local input="$1"
  echo "$input" | tr -d '[:space:]'
}

is_placeholder_ref() {
  local value="${1:-}"
  [[ "$value" =~ ^\$\(.+\)$ ]]
}

extract_app_base() {
  local from_env="${APP_API_BASE_OVERRIDE:-}"
  if [ -n "$from_env" ]; then
    echo "$from_env"
    return
  fi

  local from_secret
  from_secret=$(extract_secret APP_API_BASE_URL)
  if [ -n "$from_secret" ]; then
    echo "$from_secret"
    return
  fi

  local from_pbx
  from_pbx=$(awk -F' = ' '/APP_API_BASE_URL = / {gsub(/"|;| /, "", $2); print $2; exit}' antios5.xcodeproj/project.pbxproj 2>/dev/null)
  if [ -n "$from_pbx" ]; then
    echo "$from_pbx"
    return
  fi

  echo "https://www.antianxiety.app"
}

APP_BASE="$(extract_app_base)"
SUPABASE_URL="$(extract_secret SUPABASE_URL)"
SUPABASE_ANON_KEY="$(trim_spaces "$(extract_secret SUPABASE_ANON_KEY)")"
OPENAI_BASE="$(extract_secret OPENAI_API_BASE)"
OPENAI_KEY="$(trim_spaces "$(extract_secret OPENAI_API_KEY)")"
OPENAI_MODEL="$(trim_spaces "$(extract_secret OPENAI_MODEL)")"
OPENAI_EMBED_BASE="$(extract_secret OPENAI_EMBEDDING_API_BASE)"
OPENAI_EMBED_KEY="$(trim_spaces "$(extract_secret OPENAI_EMBEDDING_API_KEY)")"
OPENAI_EMBED_MODEL="$(trim_spaces "$(extract_secret OPENAI_EMBEDDING_MODEL)")"
OPENAI_EMBED_ENABLED_RAW="$(trim_spaces "$(extract_secret OPENAI_EMBEDDING_ENABLED)")"

if is_placeholder_ref "$OPENAI_BASE"; then OPENAI_BASE=""; fi
if is_placeholder_ref "$OPENAI_KEY"; then OPENAI_KEY=""; fi
if is_placeholder_ref "$OPENAI_MODEL"; then OPENAI_MODEL=""; fi
if is_placeholder_ref "$OPENAI_EMBED_BASE"; then OPENAI_EMBED_BASE=""; fi
if is_placeholder_ref "$OPENAI_EMBED_KEY"; then OPENAI_EMBED_KEY=""; fi
if is_placeholder_ref "$OPENAI_EMBED_MODEL"; then OPENAI_EMBED_MODEL=""; fi
if is_placeholder_ref "$OPENAI_EMBED_ENABLED_RAW"; then OPENAI_EMBED_ENABLED_RAW=""; fi

echo "perf_probe_outdir=$OUTDIR"
echo "samples=$SAMPLES"
echo "max_time=${MAX_TIME}s"

echo -e "probe\tsample\thttp\ttime_s\treachable\tsuccess\ttls_error\terr_msg" > "$OUTDIR/raw.tsv"
echo -e "probe\tsamples\treachable_rate\tsuccess_rate\ttls_error_rate\tp50_s\tp95_s" > "$OUTDIR/summary.tsv"

calc_percentile() {
  local probe_file="$1"
  local percentile="$2"
  awk -F'\t' '$4==1 {print $3}' "$probe_file" | sort -n | awk -v p="$percentile" '
    { a[++n] = $1 }
    END {
      if (n == 0) { print "NA"; exit }
      idx = int((p * n + 99) / 100)
      if (idx < 1) idx = 1
      if (idx > n) idx = n
      printf "%.3f", a[idx]
    }
  '
}

summarize_probe() {
  local probe_name="$1"
  local probe_file="$2"

  local samples reachable success tls_errors
  samples=$(awk 'END{print NR+0}' "$probe_file")
  reachable=$(awk -F'\t' '$4==1 {c++} END{print c+0}' "$probe_file")
  success=$(awk -F'\t' '$5==1 {c++} END{print c+0}' "$probe_file")
  tls_errors=$(awk -F'\t' '$6==1 {c++} END{print c+0}' "$probe_file")

  local reachable_rate success_rate tls_rate p50 p95
  if [ "$samples" -gt 0 ]; then
    reachable_rate=$(awk -v a="$reachable" -v b="$samples" 'BEGIN{printf "%.2f", (b==0?0:a/b)}')
    success_rate=$(awk -v a="$success" -v b="$samples" 'BEGIN{printf "%.2f", (b==0?0:a/b)}')
    tls_rate=$(awk -v a="$tls_errors" -v b="$samples" 'BEGIN{printf "%.2f", (b==0?0:a/b)}')
  else
    reachable_rate="0.00"
    success_rate="0.00"
    tls_rate="0.00"
  fi

  p50=$(calc_percentile "$probe_file" 50)
  p95=$(calc_percentile "$probe_file" 95)

  echo -e "${probe_name}\t${samples}\t${reachable_rate}\t${success_rate}\t${tls_rate}\t${p50}\t${p95}" >> "$OUTDIR/summary.tsv"
}

run_probe() {
  local name="$1"
  local method="$2"
  local url="$3"
  local payload="$4"
  shift 4
  local headers=()
  if [ "$#" -gt 0 ]; then
    headers=("$@")
  fi

  local probe_file="$OUTDIR/${name}.tsv"
  : > "$probe_file"

  for i in $(seq 1 "$SAMPLES"); do
    local body_file err_file http_code total_time reachable success tls_error err_msg
    body_file="$OUTDIR/${name}_${i}.body"
    err_file="$OUTDIR/${name}_${i}.err"

    local cmd
    cmd=(curl --http1.1 --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" -sS -o "$body_file" -w "%{http_code}\t%{time_total}" -X "$method" "$url")

    local h
    if [ "${#headers[@]}" -gt 0 ]; then
      for h in "${headers[@]}"; do
        if [ -n "$h" ]; then
          cmd+=( -H "$h" )
        fi
      done
    fi

    if [ -n "$payload" ]; then
      cmd+=( --data "$payload" )
    fi

    local result
    result=$("${cmd[@]}" 2>"$err_file" || true)

    http_code=$(echo "$result" | awk -F'\t' '{print $1}')
    total_time=$(echo "$result" | awk -F'\t' '{print $2}')

    if [ -z "$http_code" ]; then http_code="000"; fi
    if [ -z "$total_time" ]; then total_time="${MAX_TIME}"; fi

    if [ "$http_code" != "000" ]; then reachable=1; else reachable=0; fi
    success=0
    if [[ "$http_code" =~ ^[0-9]+$ ]]; then
      case "$name" in
        # With publishable/anon key and no user JWT, Supabase REST may reply 401/403
        # while connectivity and API gateway are still healthy.
        supabase_rest)
          if { [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; } || [ "$http_code" -eq 401 ] || [ "$http_code" -eq 403 ]; then
            success=1
          fi
          ;;
        *)
          if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            success=1
          fi
          ;;
      esac
    fi

    if [ "$HAS_RG" -eq 1 ]; then
      if rg -qi "ssl|tls|certificate" "$err_file"; then
        tls_error=1
      else
        tls_error=0
      fi
    else
      if grep -Eiq "ssl|tls|certificate" "$err_file"; then
        tls_error=1
      else
        tls_error=0
      fi
    fi

    err_msg=$(tr '\n' ' ' < "$err_file" | tr '\t' ' ' | sed 's/  */ /g' | sed 's/^ //; s/ $//')
    if [ -z "$err_msg" ]; then err_msg="-"; fi

    echo -e "${name}\t${i}\t${http_code}\t${total_time}\t${reachable}\t${success}\t${tls_error}\t${err_msg}" >> "$OUTDIR/raw.tsv"
    echo -e "${i}\t${http_code}\t${total_time}\t${reachable}\t${success}\t${tls_error}\t${err_msg}" >> "$probe_file"
  done

  summarize_probe "$name" "$probe_file"
}

is_truthy() {
  local raw="${1:-}"
  local lowered
  lowered=$(echo "$raw" | tr '[:upper:]' '[:lower:]')
  case "$lowered" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

APP_HEALTH_URL="${APP_BASE%/}/api/health"
run_probe "app_api_health" "GET" "$APP_HEALTH_URL" ""

if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_ANON_KEY" ]; then
  SUPA_URL="${SUPABASE_URL%/}/rest/v1/"
  run_probe "supabase_rest" "GET" "$SUPA_URL" "" "apikey: $SUPABASE_ANON_KEY" "Authorization: Bearer $SUPABASE_ANON_KEY"
else
  echo "WARN: Supabase credentials missing, skip supabase probe" | tee -a "$OUTDIR/notes.txt"
fi

if [ -n "$OPENAI_BASE" ] && [ -n "$OPENAI_KEY" ]; then
  EMBED_BASE="${OPENAI_EMBED_BASE:-$OPENAI_BASE}"
  EMBED_KEY="${OPENAI_EMBED_KEY:-$OPENAI_KEY}"
  EMBED_MODEL="${OPENAI_EMBED_MODEL:-text-embedding-3-small}"
  CHAT_MODEL="${OPENAI_MODEL:-deepseek-v3.2}"
  EMBED_ENABLED="${OPENAI_EMBED_ENABLED_RAW:-true}"
  EMBED_PAYLOAD="{\"model\":\"${EMBED_MODEL}\",\"input\":\"latency probe from antios5\"}"
  CHAT_PAYLOAD="{\"model\":\"${CHAT_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"temperature\":0,\"max_tokens\":8}"

  if is_truthy "$EMBED_ENABLED"; then
    if [ -n "$EMBED_BASE" ] && [ -n "$EMBED_KEY" ]; then
      run_probe "ai_embeddings" "POST" "${EMBED_BASE%/}/embeddings" "$EMBED_PAYLOAD" "Authorization: Bearer $EMBED_KEY" "Content-Type: application/json"
    else
      echo "WARN: embedding base/key missing, skip ai_embeddings probe" | tee -a "$OUTDIR/notes.txt"
    fi
  else
    echo "WARN: OPENAI_EMBEDDING_ENABLED=$EMBED_ENABLED, skip ai_embeddings probe" | tee -a "$OUTDIR/notes.txt"
  fi
  run_probe "ai_chat_ping" "POST" "${OPENAI_BASE%/}/chat/completions" "$CHAT_PAYLOAD" "Authorization: Bearer $OPENAI_KEY" "Content-Type: application/json"
else
  echo "WARN: OpenAI credentials missing, skip ai probes" | tee -a "$OUTDIR/notes.txt"
fi

echo "=== Pipeline Perf Summary ==="
column -t -s $'\t' "$OUTDIR/summary.tsv"
echo "raw=$OUTDIR/raw.tsv"
echo "summary=$OUTDIR/summary.tsv"
