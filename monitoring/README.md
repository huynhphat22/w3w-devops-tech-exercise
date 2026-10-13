# Observability & Alerting Stack (Extension B)

This directory provides a lightweight, self-contained **Prometheus** observability and alerting stack deployed to the local Kubernetes cluster to fulfill **Extension B**.

---

## Architecture Overview

```
                      +---------------------------------------+
                      |       Prometheus Pod (port 9090)      |
                      |   - Auto-scrapes annotated pods       |
                      |   - Evaluates SLO alert rules (5s)    |
                      +-------------------+-------------------+
                                          |
                     Kubernetes SD via ServiceAccount & RBAC
                                          |
                 +------------------------+------------------------+
                 |                                                 |
                 v                                                 v
   +---------------------------+                     +---------------------------+
   |   dev.greeter.local       |                     |   prod.greeter.local      |
   |   (namespace: dev)        |                     |   (namespace: prod)       |
   |   Replicas: 2             |                     |   Replicas: 3             |
   |   GET /metrics (port 8080)|                     |   GET /metrics (port 8080)|
   +---------------------------+                     +---------------------------+
```

### Components

* **`namespace.yaml`**: Dedicated `monitoring` namespace for platform observability isolation.
* **`rbac.yaml`**: `ServiceAccount`, `ClusterRole`, and `ClusterRoleBinding` granting Prometheus read-only access to discover Pods, Services, and Endpoints across all namespaces.
* **`configmap.yaml`**:
  * `prometheus.yml`: Configures 5-second scraping and relabeling rules targeting pods with annotations:
    * `prometheus.io/scrape: "true"`
    * `prometheus.io/port: "8080"`
    * `prometheus.io/path: "/metrics"`
  * `alerts.yml`: Encapsulates the SLO burn rate alerting rule (`GreeterHighHttp5xxErrorRate`).
* **`deployment.yaml`**: Minimal single-replica Prometheus deployment (`prom/prometheus:v2.54.1`) configured with memory requests (64Mi) and limits (256Mi).
* **`service.yaml`**: Internal `ClusterIP` service exposing Prometheus web interface on port 9090.
* **`ingress.yaml`**: External Ingress route mapped to `Host: prometheus.local`.

---

## The Alerting Rule: What Would Actually Wake Us Up?

```yaml
- alert: GreeterHighHttp5xxErrorRate
  expr: |
    (
      sum by (namespace) (rate(greeter_http_requests_total{status=~"5.."}[1m]))
      /
      sum by (namespace) (rate(greeter_http_requests_total[1m]))
    ) * 100 > 10
  for: 30s
  labels:
    severity: critical
    slo: "99.9-availability"
    burn_rate: "100x"
  annotations:
    summary: "High HTTP 5xx error rate in namespace {{ $labels.namespace }}"
    description: "Namespace {{ $labels.namespace }} is experiencing an HTTP 5xx error rate of {{ $value | printf \"%.2f\" }}% (>10%, 100x SLO burn rate)."
    runbook_url: "https://runbooks.internal/greeter/slo-burn-5xx"
```

### SLO & Burn Rate Rationale

* **Target SLO:** 99.9% Availability over a rolling 30-day window (allowed error budget = 0.1%).
* **Burn Rate:** A 10% error rate corresponds to a **100x burn rate** ($0.10 / 0.001$).
* **Impact:** At 100x burn rate, the service burns **100% of its monthly error budget in 7.2 hours**, and **14% in 1 hour**. This justifies waking an on-call engineer at any hour of the day.
* **Ratio-based (not count-based):** Evaluates the percentage of 5xx errors relative to total requests. Avoids alerting on low-volume blips while accurately detecting outages during peak traffic.

---

## Deployment & Verification

### 1. Deploy Monitoring Stack

```bash
kubectl apply -f monitoring/
kubectl wait --namespace monitoring --for=condition=available deployment/prometheus --timeout=60s
```

### 2. Verify Scrape Targets

```powershell
# PowerShell:
.\monitoring\check-targets.ps1

# Bash / curl:
curl -s -H "Host: prometheus.local" http://localhost:8088/api/v1/targets
```
All pods across both `dev` and `prod` should report `health: "up"`.

### 3. Automated Alert Demonstration (Extension B)

Run the automated verification script:

```powershell
# Windows PowerShell:
.\monitoring\verify-alert.ps1

# Linux / macOS / Git Bash:
./monitoring/verify-alert.sh
```

**Demonstration Output:**
1. Validates that the alert is initially **INACTIVE** (`0 firing`).
2. Sends synthetic failing traffic to `http://localhost:8088/boom`.
3. Observes the alert entering `PENDING` state after ~10 seconds.
4. Confirms the alert transitions to `FIRING` state after `30s` with complete alert metadata and error rate percentage.
