#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${1:-dev.greeter.local}"
BOOM_COUNT="${2:-30}"
MAX_WAIT="${3:-60}"

echo "=========================================================="
echo " Extension B: Alert Demonstration (/boom)"
echo "=========================================================="

echo -e "\n[Step 1] Checking baseline alert state in Prometheus..."
INITIAL_ALERTS=$(curl -s -H "Host: prometheus.local" "http://127.0.0.1:8088/api/v1/alerts")
echo "Baseline confirmed."

echo -e "\n[Step 2] Sending ${BOOM_COUNT} failure requests to /boom (Host: ${TARGET_HOST})..."
for i in $(seq 1 "${BOOM_COUNT}"); do
  curl -s -o /dev/null -H "Host: ${TARGET_HOST}" "http://127.0.0.1:8088/boom" || true
  sleep 0.1
done
echo "Dispatched ${BOOM_COUNT} failure requests to /boom."

echo -e "\n[Step 3] Monitoring Prometheus alert state (waiting for pending -> firing)..."
START_TIME=$(date +%s)
while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  if [ "${ELAPSED}" -ge "${MAX_WAIT}" ]; then
    echo "Timeout waiting for alert to reach FIRING state."
    exit 1
  fi

  ALERTS_JSON=$(curl -s -H "Host: prometheus.local" "http://127.0.0.1:8088/api/v1/alerts")
  if echo "${ALERTS_JSON}" | grep -q '"alertname":"GreeterHighHttp5xxErrorRate"'; then
    STATE=$(echo "${ALERTS_JSON}" | grep -o '"state":"[^"]*"' | head -n1 | cut -d'"' -f4)
    echo "[${ELAPSED}s] Alert state: ${STATE}"
    if [ "${STATE}" = "firing" ]; then
      echo -e "\n=========================================================="
      echo " SUCCESS: Alert 'GreeterHighHttp5xxErrorRate' reached FIRING state!"
      echo "${ALERTS_JSON}"
      echo "=========================================================="
      exit 0
    fi
  else
    echo "[${ELAPSED}s] Waiting for metrics evaluation..."
  fi

  curl -s -o /dev/null -H "Host: ${TARGET_HOST}" "http://127.0.0.1:8088/boom" || true
  sleep 5
done
