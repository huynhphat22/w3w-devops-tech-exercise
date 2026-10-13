#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${1:-dev.greeter.local}"
BOOM_COUNT="${2:-30}"
MAX_WAIT="${3:-60}"

if [[ "${TARGET_HOST}" == prod* ]]; then
  TARGET_NAMESPACE="prod"
else
  TARGET_NAMESPACE="dev"
fi

echo "=========================================================="
echo " Extension B: Alert Demonstration (/boom)"
echo "=========================================================="

# Helper function to parse alerts from Prometheus JSON API response
parse_alert() {
  local json_input="$1"
  local target_ns="$2"

  if command -v python3 &>/dev/null; then
    python3 -c "
import sys, json
raw = sys.stdin.read()
if not raw.strip():
    print('none')
    sys.exit(0)
try:
    data = json.loads(raw)
    alerts = [a for a in data.get('data', {}).get('alerts', [])
              if a.get('labels', {}).get('alertname') == 'GreeterHighHttp5xxErrorRate'
              and a.get('labels', {}).get('namespace') == sys.argv[1]]
    if alerts:
        a = alerts[0]
        state = a.get('state', '')
        try:
            val = f'{float(a.get(\"value\", 0.0)):.1f}'
        except Exception:
            val = str(a.get('value', '0.0'))
        print(state)
        print(val)
        print(json.dumps(a, indent=2))
    else:
        print('none')
except Exception:
    print('none')
" "$target_ns" <<< "$json_input"
  elif command -v python &>/dev/null; then
    python -c "
import sys, json
raw = sys.stdin.read()
if not raw.strip():
    print('none')
    sys.exit(0)
try:
    data = json.loads(raw)
    alerts = [a for a in data.get('data', {}).get('alerts', [])
              if a.get('labels', {}).get('alertname') == 'GreeterHighHttp5xxErrorRate'
              and a.get('labels', {}).get('namespace') == sys.argv[1]]
    if alerts:
        a = alerts[0]
        state = a.get('state', '')
        try:
            val = f'{float(a.get(\"value\", 0.0)):.1f}'
        except Exception:
            val = str(a.get('value', '0.0'))
        print(state)
        print(val)
        print(json.dumps(a, indent=2))
    else:
        print('none')
except Exception:
    print('none')
" "$target_ns" <<< "$json_input"
  elif command -v jq &>/dev/null; then
    local match
    match=$(jq -c --arg ns "$target_ns" '.data.alerts[] | select(.labels.alertname=="GreeterHighHttp5xxErrorRate" and .labels.namespace==$ns)' <<< "$json_input" 2>/dev/null | head -n1)
    if [ -n "$match" ]; then
      local st vl
      st=$(jq -r '.state' <<< "$match")
      vl=$(jq -r '.value // "0"' <<< "$match")
      echo "$st"
      echo "$vl"
      jq '.' <<< "$match"
    else
      echo "none"
    fi
  else
    if echo "$json_input" | grep -q "\"alertname\":\"GreeterHighHttp5xxErrorRate\"" && echo "$json_input" | grep -q "\"namespace\":\"$target_ns\""; then
      local st
      st=$(echo "$json_input" | grep -o '"state":"[^"]*"' | head -n1 | cut -d'"' -f4)
      echo "$st"
      echo "unknown"
      echo "$json_input"
    else
      echo "none"
    fi
  fi
}

# 1. Check Initial State
echo -e "\n[Step 1] Checking baseline alert state in Prometheus..."
INITIAL_JSON=$(curl -s -m 5 -H "Host: prometheus.local" "http://127.0.0.1:8088/api/v1/alerts" || echo "{}")
PARSED_INITIAL=$(parse_alert "${INITIAL_JSON}" "${TARGET_NAMESPACE}")
INITIAL_STATE=$(echo "${PARSED_INITIAL}" | sed -n '1p')

if [ "${INITIAL_STATE}" != "none" ] && [ -n "${INITIAL_STATE}" ]; then
  echo "Alert already active in namespace '${TARGET_NAMESPACE}': ${INITIAL_STATE}"
else
  echo "Baseline confirmed: Alert 'GreeterHighHttp5xxErrorRate' in namespace '${TARGET_NAMESPACE}' is INACTIVE."
fi

# 2. Trigger Outage via /boom
echo -e "\n[Step 2] Sending ${BOOM_COUNT} simulated failure requests to /boom (Host: ${TARGET_HOST})..."
for i in $(seq 1 "${BOOM_COUNT}"); do
  curl -s -m 2 -o /dev/null -H "Host: ${TARGET_HOST}" "http://127.0.0.1:8088/boom" || true
  sleep 0.1
done
echo "Dispatched ${BOOM_COUNT} failure requests to /boom."

# 3. Monitor Alert Transition
echo -e "\n[Step 3] Monitoring Prometheus alert state (waiting for pending -> firing)..."
START_TIME=$(date +%s)
FIRED=false

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  if [ "${ELAPSED}" -ge "${MAX_WAIT}" ]; then
    break
  fi

  ALERTS_JSON=$(curl -s -m 5 -H "Host: prometheus.local" "http://127.0.0.1:8088/api/v1/alerts" || echo "{}")
  PARSED=$(parse_alert "${ALERTS_JSON}" "${TARGET_NAMESPACE}")
  STATE=$(echo "${PARSED}" | sed -n '1p')
  VALUE=$(echo "${PARSED}" | sed -n '2p')
  DETAILS=$(echo "${PARSED}" | sed '1,2d')

  if [ "${STATE}" != "none" ] && [ -n "${STATE}" ]; then
    STATE_UPPER=$(echo "${STATE}" | tr '[:lower:]' '[:upper:]')
    printf "[%02ds] Alert state: %s | Namespace: %s | Observed Error Rate: %s%%\n" "${ELAPSED}" "${STATE_UPPER}" "${TARGET_NAMESPACE}" "${VALUE}"
    if [ "${STATE}" = "firing" ]; then
      FIRED=true
      break
    fi
  else
    printf "[%02ds] Waiting for metrics evaluation...\n" "${ELAPSED}"
  fi

  # Background trickle request to sustain the rate window
  curl -s -m 2 -o /dev/null -H "Host: ${TARGET_HOST}" "http://127.0.0.1:8088/boom" || true
  sleep 5
done

echo -e "\n=========================================================="
if [ "${FIRED}" = true ]; then
  echo " SUCCESS: Alert 'GreeterHighHttp5xxErrorRate' successfully reached FIRING state!"
  echo "Alert Details:"
  echo "${DETAILS}"
  echo "=========================================================="
  exit 0
else
  echo "Timeout reached without alert transitioning to FIRING." >&2
  echo "=========================================================="
  exit 1
fi
