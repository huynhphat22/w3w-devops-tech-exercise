#!/usr/bin/env bash
set -euo pipefail

RULES_JSON=$(curl -s -m 5 -H "Host: prometheus.local" "http://127.0.0.1:8088/api/v1/rules" || echo "{}")

if command -v python3 &>/dev/null; then
  python3 -c "
import sys, json
raw = sys.stdin.read()
data = json.loads(raw) if raw.strip() else {}
groups = data.get('data', {}).get('groups', [])
print(f'=== Rule Groups: {len(groups)} ===')
for g in groups:
    print(f\"Group: {g.get('name')} | File: {g.get('file')}\")
    for r in g.get('rules', []):
        print(f\"  Rule: {r.get('name')} | State: {r.get('state')} | Query: {r.get('query')}\")
" <<< "${RULES_JSON}"
elif command -v jq &>/dev/null; then
  echo "=== Rule Groups ==="
  jq -r '.data.groups[] | "Group: \(.name) | File: \(.file)", (.rules[] | "  Rule: \(.name) | State: \(.state) | Query: \(.query)")' <<< "${RULES_JSON}"
else
  echo "${RULES_JSON}"
fi

echo ""
ALERTS_JSON=$(curl -s -m 5 -H "Host: prometheus.local" "http://127.0.0.1:8088/api/v1/alerts" || echo "{}")

if command -v python3 &>/dev/null; then
  python3 -c "
import sys, json
raw = sys.stdin.read()
data = json.loads(raw) if raw.strip() else {}
alerts = data.get('data', {}).get('alerts', [])
print(f'=== Active Alerts: {len(alerts)} ===')
for a in alerts:
    print(f\"Alert: {a.get('labels', {}).get('alertname')} | State: {a.get('state')} | Value: {a.get('value')} | ActiveSince: {a.get('activeAt')}\")
" <<< "${ALERTS_JSON}"
elif command -v jq &>/dev/null; then
  echo "=== Active Alerts ==="
  jq -r '.data.alerts[] | "Alert: \(.labels.alertname) | State: \(.state) | Value: \(.value) | ActiveSince: \(.activeAt)"' <<< "${ALERTS_JSON}"
else
  echo "${ALERTS_JSON}"
fi
