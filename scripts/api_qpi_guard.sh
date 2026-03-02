#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

BASE=$(awk -F' = ' '/^OPENAI_API_BASE/{print $2}' Secrets.xcconfig | sed 's#\\/#/#g')
KEY=$(awk -F' = ' '/^OPENAI_API_KEY/{print $2}' Secrets.xcconfig | tr -d '[:space:]')

if [ -z "${BASE:-}" ] || [ -z "${KEY:-}" ]; then
  echo "ERROR: missing OPENAI_API_BASE or OPENAI_API_KEY in Secrets.xcconfig"
  exit 2
fi

HEADER_FILE=$(mktemp)
chmod 600 "$HEADER_FILE"
cat > "$HEADER_FILE" <<EOF
Authorization: Bearer $KEY
Content-Type: application/json
EOF
trap 'rm -f "$HEADER_FILE"' EXIT

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR=".analysis/api-diagnostics/qpi_guard_${TS}"
mkdir -p "$OUTDIR"

# Quality-first candidate pool from latest benchmark in current provider group.
# Guard selects the best 5 passing models at runtime.
CANDIDATE_MODELS=(
  "claude-opus-4-6"
  "claude-opus-4-5-20251101"
  "claude-sonnet-4-5-20250929"
  "claude-haiku-4-5-20251001"
  "claude-3-7-sonnet-20250219"
  "claude-3-5-sonnet-20241022"
  "claude-opus-4-20250514"
  "qwen3-coder-480b-a35b-instruct"
  "qwen-max-latest"
  "qwen3-max"
  "deepseek-v3.2"
  "deepseek-v3.1"
  "kimi-k2.5"
)

QUALITY_PROMPT='只输出一行JSON，键必须为 t1 t2 t3 t4 t5。题目：t1=347*29；t2=banana去重并按字母排序；t3=2026-02-16是否星期一（true/false）；t4=小于10的质数数组；t5=[3,1,4,1,5]的中位数。不要解释。'

PING_SLO_SECONDS=5.0
QUALITY_SLO_SECONDS=6.0
MIN_QUALITY_SCORE=4.0
MIN_CONNECT_OK_RATE=1.0

printf "model\trun\tprobe\thttp\ttime_s\tquality_score\n" > "$OUTDIR/raw.tsv"

run_chat() {
  local model="$1"
  local prompt="$2"
  local outfile="$3"
  local payload
  payload=$(jq -n --arg model "$model" --arg prompt "$prompt" '{model:$model,messages:[{role:"user",content:$prompt}],temperature:0,max_tokens:220}')

  curl --http1.1 --connect-timeout 4 --max-time 10 -sS -o "$outfile.json" -w "%{http_code}\t%{time_total}" \
    -X POST "$BASE/chat/completions" \
    -H "@$HEADER_FILE" \
    --data "$payload" \
    2>"$outfile.err" || true
}

quality_score_from_json() {
  local content="$1"
  local parsed=""
  if echo "$content" | jq -e '.' >/dev/null 2>&1; then
    parsed="$content"
  else
    parsed=$(echo "$content" | sed -n 's/.*\({.*}\).*/\1/p' | head -n1)
  fi

  if [ -z "$parsed" ] || ! echo "$parsed" | jq -e '.' >/dev/null 2>&1; then
    echo "0"
    return
  fi

  local s=0
  local v1 v2 v3 v4 v5
  v1=$(echo "$parsed" | jq -r '.t1 // empty' 2>/dev/null || true)
  v2=$(echo "$parsed" | jq -r '.t2 // empty' 2>/dev/null || true)
  v3=$(echo "$parsed" | jq -r '.t3 // empty' 2>/dev/null || true)
  v4=$(echo "$parsed" | jq -c '.t4 // empty' 2>/dev/null || true)
  v5=$(echo "$parsed" | jq -r '.t5 // empty' 2>/dev/null || true)

  [ "$v1" = "10063" ] && s=$((s+1))
  [ "$v2" = "abn" ] && s=$((s+1))
  [ "$v3" = "true" ] && s=$((s+1))
  [ "$v4" = "[2,3,5,7]" ] && s=$((s+1))
  [ "$v5" = "3" ] && s=$((s+1))
  echo "$s"
}

for model in "${CANDIDATE_MODELS[@]}"; do
  for run in 1 2; do
    safe=$(echo "$model" | sed 's#[^A-Za-z0-9._-]#_#g')

    m1=$(run_chat "$model" "ping" "$OUTDIR/${safe}_r${run}_ping")
    h1=$(echo "$m1" | awk -F'\t' '{print $1}')
    t1=$(echo "$m1" | awk -F'\t' '{print $2}')
    [ -z "$h1" ] && h1="000"
    [ -z "$t1" ] && t1="10"
    printf "%s\t%s\tping\t%s\t%s\t0\n" "$model" "$run" "$h1" "$t1" >> "$OUTDIR/raw.tsv"

    m2=$(run_chat "$model" "$QUALITY_PROMPT" "$OUTDIR/${safe}_r${run}_quality")
    h2=$(echo "$m2" | awk -F'\t' '{print $1}')
    t2=$(echo "$m2" | awk -F'\t' '{print $2}')
    [ -z "$h2" ] && h2="000"
    [ -z "$t2" ] && t2="10"

    qs=0
    if [ "$h2" = "200" ]; then
      content=$(jq -r '.choices[0].message.content // empty' "$OUTDIR/${safe}_r${run}_quality.json" 2>/dev/null || true)
      if [ -n "$content" ]; then
        qs=$(quality_score_from_json "$content")
      fi
    fi

    printf "%s\t%s\tquality\t%s\t%s\t%s\n" "$model" "$run" "$h2" "$t2" "$qs" >> "$OUTDIR/raw.tsv"
  done
done

awk -F'\t' '
NR==1{next}
{
  m=$1; p=$3; h=$4; t=$5+0; q=$6+0;
  if(p=="ping"){pc[m]++; pt[m]+=t; if(h==200) pok[m]++}
  if(p=="quality"){qc[m]++; qt[m]+=t; if(h==200) qok[m]++; qs[m]+=q}
}
END{
  print "model\tping_ok_rate\tquality_ok_rate\tavg_ping_s\tavg_quality_s\tavg_quality_score\tpass";
  for(m in pc){
    por=(pc[m]?pok[m]/pc[m]:0);
    qor=(qc[m]?qok[m]/qc[m]:0);
    ap=(pc[m]?pt[m]/pc[m]:99);
    aq=(qc[m]?qt[m]/qc[m]:99);
    aqs=(qc[m]?qs[m]/qc[m]:0);
    pass=(por>=1.0 && qor>=1.0 && ap<=5.0 && aq<=6.0 && aqs>=4.0) ? "YES" : "NO";
    printf "%s\t%.2f\t%.2f\t%.3f\t%.3f\t%.2f\t%s\n",m,por,qor,ap,aq,aqs,pass;
  }
}
' "$OUTDIR/raw.tsv" | sort -t$'\t' -k7,7r -k6,6nr > "$OUTDIR/summary.tsv"

PASS_COUNT=$(awk -F'\t' 'NR>1 && $7=="YES"{c++} END{print c+0}' "$OUTDIR/summary.tsv")
PASS_MODELS_FILE="$OUTDIR/pass_models.tsv"
TOP5_FILE="$OUTDIR/active_top5.txt"

awk -F'\t' 'NR==1{next} $7=="YES"{print $0}' "$OUTDIR/summary.tsv" > "$PASS_MODELS_FILE"

if [ "$PASS_COUNT" -ge 5 ]; then
  awk -F'\t' '
  {
    if(NR==1){next}
    if($7=="YES"){
      # Sort by quality score desc, quality latency asc, ping latency asc.
      printf "%s\t%.2f\t%.3f\t%.3f\n", $1, $6+0, $5+0, $4+0
    }
  }
  ' "$OUTDIR/summary.tsv" \
  | sort -t$'\t' -k2,2nr -k3,3n -k4,4n \
  | head -n 5 \
  | cut -f1 > "$TOP5_FILE"

  cp "$TOP5_FILE" ".analysis/api-diagnostics/ACTIVE_TOP5_MODELS.txt"
fi

echo "QPI report: $OUTDIR/summary.tsv"
cat "$OUTDIR/summary.tsv"
echo "pass_models=$PASS_COUNT"
if [ -f "$TOP5_FILE" ]; then
  echo "active_top5:"
  nl -ba "$TOP5_FILE"
fi

if [ "$PASS_COUNT" -lt 5 ]; then
  echo "QPI_GUARD=FAIL"
  exit 1
fi

echo "QPI_GUARD=PASS"
exit 0
