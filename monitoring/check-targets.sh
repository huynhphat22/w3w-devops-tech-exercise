#!/usr/bin/env bash
set -euo pipefail

TARGETS_JSON=$(curl -s -m 5 -H "Host: prometheus.local" "http://127.0.0.1:8088/api/v1/targets" || echo "{}")

if command -v python3 &>/dev/null; then
  python3 -c "
import sys, json
raw = sys.stdin.read()
data = json.loads(raw) if raw.strip() else {}
targets = data.get('data', {}).get('activeTargets', [])
print(f'=== Active Targets: {len(targets)} ===')
for t in targets:
    labels = t.get('labels', {})
    print(f\"Target: {t.get('scrapeUrl')} | Health: {t.get('health')} | Namespace: {labels.get('namespace')} | Pod: {labels.get('pod')} | Error: {t.get('lastError')}\")
" <<< "${TARGETS_JSON}"
elif command -v jq &>/dev/null; then
  echo "=== Active Targets ==="
  jq -r '.data.activeTargets[] | "Target: \(.scrapeUrl) | Health: \(.health) | Namespace: \(.labels.namespace) | Pod: \(.labels.pod) | Error: \(.lastError)"' <<< "${TARGETS_JSON}"
else
  echo "${TARGETS_JSON}"
fi
