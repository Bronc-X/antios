#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

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

normalize_lang() {
  local raw="${1:-}"
  local lower
  lower=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$lower" in
    zh|zh-cn|zh-hans|zh-hant|zh-tw|zh-hk|cn) echo "zh" ;;
    en|en-us|en-gb) echo "en" ;;
    *) echo "$lower" ;;
  esac
}

BASE="$(extract_secret OPENAI_API_BASE)"
KEY="$(extract_secret OPENAI_API_KEY | tr -d '[:space:]')"
PRIMARY_MODEL="$(extract_secret OPENAI_MODEL)"
FALLBACK_CHAIN_RAW="$(extract_secret OPENAI_MODEL_FALLBACK_CHAIN)"
EXTRA_MODELS_RAW="${QPI_EXTRA_MODELS:-$(extract_secret QPI_EXTRA_MODELS)}"
MIN_PASS_MODELS_RAW="$(extract_secret QPI_MIN_PASS_MODELS)"
MIN_QUALITY_SCORE_RAW="$(extract_secret MIN_QUALITY_SCORE)"
GATE_MODE_RAW="${QPI_GATE_MODE:-$(extract_secret QPI_GATE_MODE)}"
USER_LANGUAGE_RAW="$(extract_secret QPI_USER_LANGUAGE)"
PROFILE_RAW="$(extract_secret QPI_PROFILE)"

MIN_PASS_MODELS="${QPI_MIN_PASS_MODELS:-${MIN_PASS_MODELS_RAW:-1}}"
if ! [[ "$MIN_PASS_MODELS" =~ ^[0-9]+$ ]] || [ "$MIN_PASS_MODELS" -lt 1 ]; then
  MIN_PASS_MODELS=1
fi

MIN_QUALITY_SCORE="${MIN_QUALITY_SCORE:-${QPI_MIN_QUALITY_SCORE:-${MIN_QUALITY_SCORE_RAW:-3.0}}}"
if ! [[ "$MIN_QUALITY_SCORE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  MIN_QUALITY_SCORE="3.0"
fi

if [[ "$BASE" =~ ^\$\(.+\)$ ]]; then BASE=""; fi
if [[ "$KEY" =~ ^\$\(.+\)$ ]]; then KEY=""; fi
if [[ "$PRIMARY_MODEL" =~ ^\$\(.+\)$ ]]; then PRIMARY_MODEL=""; fi
if [[ "$FALLBACK_CHAIN_RAW" =~ ^\$\(.+\)$ ]]; then FALLBACK_CHAIN_RAW=""; fi
if [[ "$EXTRA_MODELS_RAW" =~ ^\$\(.+\)$ ]]; then EXTRA_MODELS_RAW=""; fi
if [[ "$GATE_MODE_RAW" =~ ^\$\(.+\)$ ]]; then GATE_MODE_RAW=""; fi
if [[ "$USER_LANGUAGE_RAW" =~ ^\$\(.+\)$ ]]; then USER_LANGUAGE_RAW=""; fi
if [[ "$PROFILE_RAW" =~ ^\$\(.+\)$ ]]; then PROFILE_RAW=""; fi

QPI_GATE_MODE=$(echo "${GATE_MODE_RAW:-warn}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
case "$QPI_GATE_MODE" in
  block|warn) ;;
  *) QPI_GATE_MODE="warn" ;;
esac

QPI_USER_LANGUAGE="$(normalize_lang "${QPI_USER_LANGUAGE:-${USER_LANGUAGE_RAW:-zh}}")"
[ -z "$QPI_USER_LANGUAGE" ] && QPI_USER_LANGUAGE="zh"

QPI_PROFILE=$(echo "${QPI_PROFILE:-${PROFILE_RAW:-anti_anxiety}}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
[ -z "$QPI_PROFILE" ] && QPI_PROFILE="anti_anxiety"

if [ -z "${BASE:-}" ] || [ -z "${KEY:-}" ]; then
  echo "ERROR: missing OPENAI_API_BASE or OPENAI_API_KEY in Secrets.private.xcconfig / Secrets.xcconfig"
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

# Default candidate pool for fallback only.
DEFAULT_CANDIDATE_MODELS=(
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

CANDIDATE_MODELS=()
append_unique_model() {
  local raw="${1:-}"
  local model
  model=$(echo "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$model" ] || return
  local existing
  for existing in ${CANDIDATE_MODELS[*]-}; do
    [ "$existing" = "$model" ] && return
  done
  CANDIDATE_MODELS+=("$model")
}

append_unique_model "$PRIMARY_MODEL"
if [ -n "$FALLBACK_CHAIN_RAW" ]; then
  IFS=',' read -r -a fallback_models <<< "$FALLBACK_CHAIN_RAW"
  for model in "${fallback_models[@]}"; do
    append_unique_model "$model"
  done
fi
if [ -n "$EXTRA_MODELS_RAW" ]; then
  IFS=',' read -r -a extra_models <<< "$EXTRA_MODELS_RAW"
  for model in "${extra_models[@]}"; do
    append_unique_model "$model"
  done
fi

if [ -z "${CANDIDATE_MODELS[*]-}" ]; then
  CANDIDATE_MODELS=("${DEFAULT_CANDIDATE_MODELS[@]}")
fi

echo "candidate_models=${CANDIDATE_MODELS[*]}"
echo "qpi_profile=$QPI_PROFILE"
echo "qpi_user_language=$QPI_USER_LANGUAGE"
echo "qpi_gate_mode=$QPI_GATE_MODE"
echo "min_quality_score=$MIN_QUALITY_SCORE"

if [ "$QPI_PROFILE" = "legacy_math" ]; then
  QUALITY_PROMPT='只输出一行JSON，键必须为 t1 t2 t3 t4 t5。题目：t1=347*29；t2=banana去重并按字母排序；t3=2026-02-16是否星期一（true/false）；t4=小于10的质数数组；t5=[3,1,4,1,5]的中位数。不要解释。'
else
  QUALITY_PROMPT="只输出一行JSON，不要Markdown。场景：用户“最近睡眠差、心慌、担心工作失控”。返回键 scientific_explanation,action_suggestions,follow_up_question,language。要求：scientific_explanation 1句且含机制或证据词；action_suggestions 恰好2条且每条都能10分钟内执行；follow_up_question 1句且含0-10分；language='${QPI_USER_LANGUAGE}'。"
fi

PING_SLO_SECONDS="${PING_SLO_SECONDS:-5.0}"
QUALITY_SLO_SECONDS="${QUALITY_SLO_SECONDS:-6.5}"
QPI_SLO_EPSILON_SEC="${QPI_SLO_EPSILON_SEC:-0.15}"
MIN_CONNECT_OK_RATE="${MIN_CONNECT_OK_RATE:-1.0}"
QPI_PING_MAX_TOKENS="${QPI_PING_MAX_TOKENS:-32}"
QPI_QUALITY_MAX_TOKENS="${QPI_QUALITY_MAX_TOKENS:-300}"

printf "model\trun\tprobe\thttp\ttime_s\tquality_score\n" > "$OUTDIR/raw.tsv"

run_chat() {
  local model="$1"
  local prompt="$2"
  local outfile="$3"
  local max_tokens="${4:-220}"
  local payload
  payload=$(jq -n --arg model "$model" --arg prompt "$prompt" --argjson max_tokens "$max_tokens" '{model:$model,messages:[{role:"user",content:$prompt}],temperature:0,max_tokens:$max_tokens}')

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
    # Fallback 1: capture multiline JSON block (handles fenced code blocks).
    parsed=$(printf "%s\n" "$content" | sed -n '/{/,/}/p' | sed '/^[[:space:]]*```/d')
    if [ -z "$parsed" ] || ! echo "$parsed" | jq -e '.' >/dev/null 2>&1; then
      # Fallback 2: single-line inline JSON extraction.
      parsed=$(echo "$content" | sed -n 's/.*\({.*}\).*/\1/p' | head -n1)
    fi
  fi

  if [ -z "$parsed" ] || ! echo "$parsed" | jq -e '.' >/dev/null 2>&1; then
    echo "0"
    return
  fi

  if [ "$QPI_PROFILE" = "legacy_math" ]; then
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
    return
  fi

  local score=0
  local science actions_json actions_len follow_up answer_lang norm_answer_lang actions_text
  local valid_action_count cjk_count latin_count min_cjk_for_zh
  science=$(echo "$parsed" | jq -r '.scientific_explanation // .science // .mechanism // empty' 2>/dev/null || true)
  actions_json=$(echo "$parsed" | jq -c '.action_suggestions // .actions // []' 2>/dev/null || echo "[]")
  actions_len=$(echo "$actions_json" | jq -r 'if type=="array" then length else 0 end' 2>/dev/null || echo "0")
  follow_up=$(echo "$parsed" | jq -r '.follow_up_question // .followup_question // .follow_up // empty' 2>/dev/null || true)
  answer_lang=$(echo "$parsed" | jq -r '.language // .lang // empty' 2>/dev/null || true)
  norm_answer_lang="$(normalize_lang "$answer_lang")"

  if [ "${#science}" -ge 12 ] && echo "$science" | grep -Eiq '机制|证据|研究|神经|生理|行为|认知|睡眠|evidence|study|research|mechanism|nervous|cortisol|sleep|cognitive'; then
    score=$((score+1))
  fi

  if [ "$actions_len" -ge 2 ] && [ "$actions_len" -le 4 ]; then
    valid_action_count=$(echo "$actions_json" | jq '[.[] | select((type=="string") and (length>=6) and (length<=120))] | length' 2>/dev/null || echo "0")
    if [ "$valid_action_count" -ge 2 ]; then
      score=$((score+1))
    fi
  fi

  if [ "${#follow_up}" -ge 8 ] \
    && echo "$follow_up" | grep -Eq '[？\?]' \
    && echo "$follow_up" | grep -Eiq '0-10|0~10|0到10|0 到 10|分|分钟|小时|次|天|times|minutes|hours|days|score|scale|frequency'; then
    score=$((score+1))
  fi

  actions_text=$(echo "$actions_json" | jq -r 'if type=="array" then join(" ") else "" end' 2>/dev/null || true)
  cjk_count=$(printf "%s" "$science $actions_text $follow_up" | tr -cd '一-龥' | wc -m | tr -d '[:space:]')
  latin_count=$(printf "%s" "$science $actions_text $follow_up" | tr -cd 'A-Za-z' | wc -m | tr -d '[:space:]')
  cjk_count="${cjk_count:-0}"
  latin_count="${latin_count:-0}"

  if [ "$norm_answer_lang" = "$QPI_USER_LANGUAGE" ]; then
    if [ "$QPI_USER_LANGUAGE" = "zh" ]; then
      min_cjk_for_zh=$((latin_count / 2))
      if [ "$cjk_count" -ge 12 ] && [ "$cjk_count" -ge "$min_cjk_for_zh" ]; then
        score=$((score+1))
      fi
    elif [ "$QPI_USER_LANGUAGE" = "en" ]; then
      if [ "$latin_count" -ge 30 ] && [ "$cjk_count" -le 8 ]; then
        score=$((score+1))
      fi
    else
      score=$((score+1))
    fi
  fi

  echo "$score"
}

for model in "${CANDIDATE_MODELS[@]}"; do
  for run in 1 2; do
    safe=$(echo "$model" | sed 's#[^A-Za-z0-9._-]#_#g')

    m1=$(run_chat "$model" "ping" "$OUTDIR/${safe}_r${run}_ping" "$QPI_PING_MAX_TOKENS")
    h1=$(echo "$m1" | awk -F'\t' '{print $1}')
    t1=$(echo "$m1" | awk -F'\t' '{print $2}')
    [ -z "$h1" ] && h1="000"
    [ -z "$t1" ] && t1="10"
    printf "%s\t%s\tping\t%s\t%s\t0\n" "$model" "$run" "$h1" "$t1" >> "$OUTDIR/raw.tsv"

    m2=$(run_chat "$model" "$QUALITY_PROMPT" "$OUTDIR/${safe}_r${run}_quality" "$QPI_QUALITY_MAX_TOKENS")
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

awk -F'\t' \
-v min_conn="$MIN_CONNECT_OK_RATE" \
-v ping_slo="$PING_SLO_SECONDS" \
-v quality_slo="$QUALITY_SLO_SECONDS" \
-v slo_eps="$QPI_SLO_EPSILON_SEC" \
-v min_qs="$MIN_QUALITY_SCORE" '
NR==1{next}
{
  m=$1; p=$3; h=$4; t=$5+0; q=$6+0;
  if(p=="ping"){pc[m]++; pt[m]+=t; if(h==200) pok[m]++}
  if(p=="quality"){qc[m]++; qt[m]+=t; if(h==200) qok[m]++; qs[m]+=q}
}
END{
  for(m in pc){
    por=(pc[m]?pok[m]/pc[m]:0);
    qor=(qc[m]?qok[m]/qc[m]:0);
    ap=(pc[m]?pt[m]/pc[m]:99);
    aq=(qc[m]?qt[m]/qc[m]:99);
    aqs=(qc[m]?qs[m]/qc[m]:0);
    pass=(por>=min_conn && qor>=min_conn && ap<=ping_slo && aq<=(quality_slo+slo_eps) && aqs>=min_qs) ? "YES" : "NO";
    printf "%s\t%.2f\t%.2f\t%.3f\t%.3f\t%.2f\t%s\n",m,por,qor,ap,aq,aqs,pass;
  }
}
' "$OUTDIR/raw.tsv" | sort -t$'\t' -k7,7r -k6,6nr > "$OUTDIR/summary_body.tsv"

{
  printf "model\tping_ok_rate\tquality_ok_rate\tavg_ping_s\tavg_quality_s\tavg_quality_score\tpass\n"
  cat "$OUTDIR/summary_body.tsv"
} > "$OUTDIR/summary.tsv"

PASS_COUNT=$(awk -F'\t' '$1!="model" && $7=="YES"{c++} END{print c+0}' "$OUTDIR/summary.tsv")
PASS_MODELS_FILE="$OUTDIR/pass_models.tsv"
TOP5_FILE="$OUTDIR/active_top5.txt"

awk -F'\t' '$1!="model" && $7=="YES"{print $0}' "$OUTDIR/summary.tsv" > "$PASS_MODELS_FILE"

if [ "$PASS_COUNT" -ge 1 ]; then
  awk -F'\t' '
  {
    if($1!="model" && $7=="YES"){
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
echo "required_pass_models=$MIN_PASS_MODELS"
echo "gate_mode=$QPI_GATE_MODE"
echo "quality_slo_seconds=$QUALITY_SLO_SECONDS"
echo "qpi_slo_epsilon_sec=$QPI_SLO_EPSILON_SEC"
if [ -f "$TOP5_FILE" ]; then
  echo "active_top5:"
  nl -ba "$TOP5_FILE"
fi

if [ "$PASS_COUNT" -lt "$MIN_PASS_MODELS" ]; then
  if [ "$QPI_GATE_MODE" = "warn" ]; then
    echo "QPI_GUARD=WARN"
    exit 0
  fi
  echo "QPI_GUARD=FAIL"
  exit 1
fi

echo "QPI_GUARD=PASS"
exit 0
