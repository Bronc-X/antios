#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

extract_secret() {
  local key="$1"
  awk -F' = ' -v target="$key" '$1==target {print $2}' Secrets.xcconfig 2>/dev/null | sed 's#\\/#/#g' | tr -d '\r'
}

trim_spaces() {
  local input="$1"
  echo "$input" | tr -d '[:space:]'
}

is_placeholder_ref() {
  local value="${1:-}"
  [[ "$value" =~ ^\$\(.+\)$ ]]
}

is_positive_int() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

sleep_ms() {
  local ms="$1"
  local seconds
  seconds=$(awk -v v="$ms" 'BEGIN { printf "%.3f", (v / 1000.0) }')
  sleep "$seconds"
}

SUPABASE_URL="${SUPABASE_URL:-$(extract_secret SUPABASE_URL)}"
SUPABASE_SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-$(extract_secret SUPABASE_SERVICE_ROLE_KEY)}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$(extract_secret SUPABASE_ANON_KEY)}"
OPENAI_API_BASE="${OPENAI_API_BASE:-$(extract_secret OPENAI_API_BASE)}"
OPENAI_API_KEY="${OPENAI_API_KEY:-$(extract_secret OPENAI_API_KEY)}"
OPENAI_EMBEDDING_API_BASE="${OPENAI_EMBEDDING_API_BASE:-$(extract_secret OPENAI_EMBEDDING_API_BASE)}"
OPENAI_EMBEDDING_API_KEY="${OPENAI_EMBEDDING_API_KEY:-$(extract_secret OPENAI_EMBEDDING_API_KEY)}"
OPENAI_EMBEDDING_MODEL="${OPENAI_EMBEDDING_MODEL:-$(extract_secret OPENAI_EMBEDDING_MODEL)}"

SUPABASE_SERVICE_ROLE_KEY="$(trim_spaces "$SUPABASE_SERVICE_ROLE_KEY")"
SUPABASE_ANON_KEY="$(trim_spaces "$SUPABASE_ANON_KEY")"
OPENAI_API_KEY="$(trim_spaces "$OPENAI_API_KEY")"
OPENAI_EMBEDDING_API_KEY="$(trim_spaces "$OPENAI_EMBEDDING_API_KEY")"
OPENAI_EMBEDDING_MODEL="${OPENAI_EMBEDDING_MODEL:-text-embedding-3-small}"

if is_placeholder_ref "$OPENAI_API_BASE"; then OPENAI_API_BASE=""; fi
if is_placeholder_ref "$OPENAI_API_KEY"; then OPENAI_API_KEY=""; fi
if is_placeholder_ref "$OPENAI_EMBEDDING_API_BASE"; then OPENAI_EMBEDDING_API_BASE=""; fi
if is_placeholder_ref "$OPENAI_EMBEDDING_API_KEY"; then OPENAI_EMBEDDING_API_KEY=""; fi
if is_placeholder_ref "$OPENAI_EMBEDDING_MODEL"; then OPENAI_EMBEDDING_MODEL=""; fi

OPENAI_EMBEDDING_API_BASE="${OPENAI_EMBEDDING_API_BASE:-$OPENAI_API_BASE}"
OPENAI_EMBEDDING_API_KEY="${OPENAI_EMBEDDING_API_KEY:-$OPENAI_API_KEY}"

BATCH_SIZE="${BATCH_SIZE:-40}"
MAX_ROWS="${MAX_ROWS:-1200}"
SLEEP_MS="${SLEEP_MS:-80}"
ROLE_FILTER="${ROLE_FILTER:-user}" # user | assistant | all
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-8}"
MAX_TIME="${MAX_TIME:-25}"
DRY_RUN="${DRY_RUN:-0}" # 1 = no PATCH writes

SUPABASE_KEY="$SUPABASE_SERVICE_ROLE_KEY"
if [ -z "$SUPABASE_KEY" ]; then
  SUPABASE_KEY="$SUPABASE_ANON_KEY"
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ] || [ -z "$OPENAI_EMBEDDING_API_BASE" ] || [ -z "$OPENAI_EMBEDDING_API_KEY" ]; then
  echo "ERROR: missing SUPABASE_URL/SUPABASE key/OPENAI_EMBEDDING_API_BASE/OPENAI_EMBEDDING_API_KEY (from env or Secrets.xcconfig)"
  exit 2
fi

if ! is_positive_int "$BATCH_SIZE"; then
  echo "ERROR: BATCH_SIZE must be a positive integer"
  exit 2
fi
if ! is_positive_int "$MAX_ROWS"; then
  echo "ERROR: MAX_ROWS must be a positive integer"
  exit 2
fi
if ! is_positive_int "$SLEEP_MS"; then
  echo "ERROR: SLEEP_MS must be a positive integer"
  exit 2
fi
if ! is_positive_int "$CONNECT_TIMEOUT"; then
  echo "ERROR: CONNECT_TIMEOUT must be a positive integer"
  exit 2
fi
if ! is_positive_int "$MAX_TIME"; then
  echo "ERROR: MAX_TIME must be a positive integer"
  exit 2
fi
if [ "$DRY_RUN" != "0" ] && [ "$DRY_RUN" != "1" ]; then
  echo "ERROR: DRY_RUN must be 0 or 1"
  exit 2
fi
if [ "$DRY_RUN" = "0" ] && [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
  echo "ERROR: DRY_RUN=0 requires SUPABASE_SERVICE_ROLE_KEY; anon key cannot backfill rows under RLS."
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for this script"
  exit 2
fi

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR=".analysis/backfill/ai_memory_embeddings_${TS}"
mkdir -p "$OUTDIR"
RAW_TSV="$OUTDIR/raw.tsv"
SUMMARY_TXT="$OUTDIR/summary.txt"

echo -e "id\trole\tstatus\tembed_http\tembed_time_s\tpatch_http\tpatch_time_s\tnote" > "$RAW_TSV"

echo "backfill_outdir=$OUTDIR"
echo "batch_size=$BATCH_SIZE max_rows=$MAX_ROWS role_filter=$ROLE_FILTER model=$OPENAI_EMBEDDING_MODEL dry_run=$DRY_RUN"

processed=0
patched=0
skipped=0
failed=0
batch_no=0
no_progress_batches=0

while [ "$processed" -lt "$MAX_ROWS" ]; do
  batch_no=$((batch_no + 1))

  query="select=id,content_text,role&embedding=is.null&order=created_at.asc&limit=${BATCH_SIZE}"
  if [ "$ROLE_FILTER" != "all" ]; then
    query="${query}&role=eq.${ROLE_FILTER}"
  fi

  rows_file="$OUTDIR/batch_${batch_no}.rows.json"
  rows_err="$OUTDIR/batch_${batch_no}.rows.err"
  rows_meta=$(curl --http1.1 --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" -sS \
    -o "$rows_file" -w "%{http_code}\t%{time_total}" \
    -X GET "${SUPABASE_URL%/}/rest/v1/ai_memory?${query}" \
    -H "apikey: $SUPABASE_KEY" \
    -H "Authorization: Bearer $SUPABASE_KEY" \
    -H "Accept: application/json" \
    2>"$rows_err" || true)

  rows_http=$(echo "$rows_meta" | awk -F'\t' '{print $1}')
  if [ -z "$rows_http" ]; then rows_http="000"; fi
  if [ "$rows_http" != "200" ]; then
    echo "ERROR: fetch batch failed http=$rows_http err=$(tr '\n' ' ' < "$rows_err")"
    break
  fi

  if ! jq -e 'type == "array"' "$rows_file" >/dev/null 2>&1; then
    echo "ERROR: invalid batch payload, not an array"
    break
  fi

  batch_count=$(jq 'length' "$rows_file")
  if [ "$batch_count" -eq 0 ]; then
    echo "No more rows with null embedding."
    break
  fi

  echo "Batch #$batch_no rows=$batch_count"
  batch_patched=0

  while IFS= read -r row; do
    if [ "$processed" -ge "$MAX_ROWS" ]; then
      break 2
    fi
    processed=$((processed + 1))

    id=$(echo "$row" | jq -r '.id // empty')
    role=$(echo "$row" | jq -r '.role // empty')
    content=$(echo "$row" | jq -r '.content_text // empty')

    if [ -z "$id" ] || [ -z "$content" ]; then
      skipped=$((skipped + 1))
      echo -e "${id}\t${role}\tskipped\t-\t-\t-\t-\tempty id/content" >> "$RAW_TSV"
      continue
    fi

    embed_req=$(jq -n --arg model "$OPENAI_EMBEDDING_MODEL" --arg input "$content" '{model:$model,input:$input}')
    embed_file="$OUTDIR/${id}_embed.json"
    embed_err="$OUTDIR/${id}_embed.err"
    embed_meta=$(curl --http1.1 --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" -sS \
      -o "$embed_file" -w "%{http_code}\t%{time_total}" \
      -X POST "${OPENAI_EMBEDDING_API_BASE%/}/embeddings" \
      -H "Authorization: Bearer $OPENAI_EMBEDDING_API_KEY" \
      -H "Content-Type: application/json" \
      --data "$embed_req" \
      2>"$embed_err" || true)

    embed_http=$(echo "$embed_meta" | awk -F'\t' '{print $1}')
    embed_time=$(echo "$embed_meta" | awk -F'\t' '{print $2}')
    [ -z "$embed_http" ] && embed_http="000"
    [ -z "$embed_time" ] && embed_time="$MAX_TIME"

    if [ "$embed_http" != "200" ]; then
      failed=$((failed + 1))
      note=$(tr '\n' ' ' < "$embed_err" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      [ -z "$note" ] && note=$(jq -r '.error.message // "embedding failed"' "$embed_file" 2>/dev/null || echo "embedding failed")
      echo -e "${id}\t${role}\tfailed\t${embed_http}\t${embed_time}\t-\t-\t${note}" >> "$RAW_TSV"
      sleep_ms "$SLEEP_MS"
      continue
    fi

    embedding_json=$(jq -c '.data[0].embedding // empty' "$embed_file" 2>/dev/null || true)
    if [ -z "$embedding_json" ] || [ "$embedding_json" = "null" ]; then
      failed=$((failed + 1))
      note=$(jq -r '.error.message // "missing embedding vector"' "$embed_file" 2>/dev/null || echo "missing embedding vector")
      echo -e "${id}\t${role}\tfailed\t${embed_http}\t${embed_time}\t-\t-\t${note}" >> "$RAW_TSV"
      sleep_ms "$SLEEP_MS"
      continue
    fi

    patch_payload="{\"embedding\":${embedding_json}}"
    if [ "$DRY_RUN" = "1" ]; then
      patched=$((patched + 1))
      batch_patched=$((batch_patched + 1))
      echo -e "${id}\t${role}\twould_patch\t${embed_http}\t${embed_time}\t-\t-\tdry_run" >> "$RAW_TSV"
      sleep_ms "$SLEEP_MS"
      continue
    fi

    patch_file="$OUTDIR/${id}_patch.json"
    patch_err="$OUTDIR/${id}_patch.err"
    patch_meta=$(curl --http1.1 --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" -sS \
      -o "$patch_file" -w "%{http_code}\t%{time_total}" \
      -X PATCH "${SUPABASE_URL%/}/rest/v1/ai_memory?id=eq.${id}" \
      -H "apikey: $SUPABASE_KEY" \
      -H "Authorization: Bearer $SUPABASE_KEY" \
      -H "Content-Type: application/json" \
      -H "Prefer: return=minimal" \
      --data "$patch_payload" \
      2>"$patch_err" || true)

    patch_http=$(echo "$patch_meta" | awk -F'\t' '{print $1}')
    patch_time=$(echo "$patch_meta" | awk -F'\t' '{print $2}')
    [ -z "$patch_http" ] && patch_http="000"
    [ -z "$patch_time" ] && patch_time="$MAX_TIME"

    if [[ "$patch_http" =~ ^2 ]]; then
      patched=$((patched + 1))
      batch_patched=$((batch_patched + 1))
      echo -e "${id}\t${role}\tpatched\t${embed_http}\t${embed_time}\t${patch_http}\t${patch_time}\t-" >> "$RAW_TSV"
    else
      failed=$((failed + 1))
      note=$(tr '\n' ' ' < "$patch_err" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      [ -z "$note" ] && note=$(jq -r '.message // .error.message // "patch failed"' "$patch_file" 2>/dev/null || echo "patch failed")
      echo -e "${id}\t${role}\tfailed\t${embed_http}\t${embed_time}\t${patch_http}\t${patch_time}\t${note}" >> "$RAW_TSV"
    fi

    sleep_ms "$SLEEP_MS"
  done < <(jq -c '.[]' "$rows_file")

  if [ "$batch_patched" -eq 0 ]; then
    no_progress_batches=$((no_progress_batches + 1))
    if [ "$no_progress_batches" -ge 3 ]; then
      echo "Stop: no patch progress for 3 consecutive batches."
      break
    fi
  else
    no_progress_batches=0
  fi
done

{
  echo "processed=$processed"
  echo "patched=$patched"
  echo "skipped=$skipped"
  echo "failed=$failed"
  echo "raw=$RAW_TSV"
} | tee "$SUMMARY_TXT"

echo "summary=$SUMMARY_TXT"
