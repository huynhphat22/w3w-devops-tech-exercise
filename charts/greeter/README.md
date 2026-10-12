# Greeter Helm Chart

This directory contains the hand-crafted Helm chart for the `greeter` HTTP service, fulfilling **Core Task 3**.

> **Note on Scaffolding:** This chart was written entirely by hand without `helm create` boilerplate. Every resource and value is minimal and strictly justified line-by-line below.

---

## Resource Justification

| Resource | File | Justification & Design Intent |
|---|---|---|
| **Deployment** | `templates/deployment.yaml` | Manages the application lifecycle. Configured with: <br>• **2 Replicas by default** to survive single-node failures.<br>• **RollingUpdate** with `maxUnavailable: 0` for zero-downtime deployments.<br>• **Topology Spread Constraints** (`kubernetes.io/hostname`) to spread pods across separate worker nodes.<br>• **`terminationGracePeriodSeconds: 45`** to accommodate `SHUTDOWN_DELAY_SECONDS` (10s) + `DRAIN_TIMEOUT_SECONDS` (20s) with safety buffer.<br>• **Probes:** Liveness on `/healthz` (persists through warmup) and Readiness on `/readyz` (fails during warmup and drain, probed every 2s for fast route eviction).<br>• **Security Context:** `runAsNonRoot`, `readOnlyRootFilesystem`, and dropped Linux capabilities. |
| **Service** | `templates/service.yaml` | `ClusterIP` exposing port `80` routing to targetPort `8080`. Acts as the internal stable virtual IP for the pod replicas. |
| **Ingress** | `templates/ingress.yaml` | **Exposes the service outside the cluster.** Directs HTTP traffic arriving on the cluster load balancer (e.g., `http://localhost/`) to the internal Service. |
| **ConfigMap** | `templates/configmap.yaml` | Decouples operational settings (`GREETING_NAME`, `PORT`, `VERSION`, timeouts) from the deployment spec. Changing values in `values.yaml` dynamically updates the ConfigMap. Combined with the pod template `checksum/config` annotation, updates trigger automated rolling restarts. |
| **PodDisruptionBudget** | `templates/pdb.yaml` | Enforces `minAvailable: 1`. Ensures that voluntary disruptions (such as node drains during maintenance or Extension D tests) never take down all replicas simultaneously. |

---

## Configuration & Environment Customization

An operator can customize the greeting name and operational settings without rebuilding the container image:

```bash
# Example: Deploying with custom greeting
helm install greeter ./charts/greeter \
  --set greetingName="ProductionOperator" \
  --set replicaCount=3
```

---

## Verifying External Access

When deployed on a cluster with an ingress controller (such as `k3d` with Traefik or `kind` with Ingress-NGINX mapped to host port 80):

```bash
# Root endpoint
curl http://localhost/

# Health & readiness
curl http://localhost/healthz
curl http://localhost/readyz

# Prometheus metrics
curl http://localhost/metrics
```
