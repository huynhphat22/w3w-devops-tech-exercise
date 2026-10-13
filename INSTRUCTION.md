# End-to-End Setup & Reproduction Guide

This guide provides step-by-step instructions to reproduce and stand up the complete solution on a fresh machine (macOS, Linux, or Windows) from a clean clone.

---

## Prerequisites & Tooling

Ensure the following tools are installed on the host machine:

| Tool | Minimum Version | Installation Link / Command |
|---|---|---|
| **Docker Engine / Desktop** | 24.0+ | [docs.docker.com](https://docs.docker.com/get-docker/) (Ensure Docker daemon is running) |
| **k3d** | v5.0+ | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` or `choco install k3d` / `brew install k3d` |
| **kubectl** | v1.28+ | [kubernetes.io/docs/tasks/tools/](https://kubernetes.io/docs/tasks/tools/) |
| **Terraform** | v1.5+ | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| **Helm** *(optional for local linting)* | v3.12+ | [helm.sh/docs/intro/install/](https://helm.sh/docs/intro/install/) |
| **curl** | Any | Standard POSIX / Windows curl.exe |

---

## Step 1: Clone Repository & Build Container Image (Core Task 1)

Clone the repository and build the minimal multi-stage production container image:

```bash
git clone https://github.com/huynhphat22/w3w-devops-tech-exercise.git
cd w3w-devops-tech-exercise
git checkout solution

# Build the minimal scratch-based container image (~7.7 MB uncompressed)
docker build -t greeter:test .
```

---

## Step 2: Stand Up the Multi-Node Cluster (Core Task 2 & Extension B)

Run the automated cluster bootstrap script. This provisions a 3-node Kubernetes cluster (1 control plane + 2 dedicated workers), configures Traefik Ingress on port 8088, sideloads the local container images, and deploys the Prometheus monitoring stack out-of-the-box.

### On Windows PowerShell:
```powershell
.\cluster\up.ps1
```

### On Linux / macOS / Git Bash:
```bash
chmod +x ./cluster/up.sh
./cluster/up.sh
```

### What This Automatically Provisions:
1. **Cluster Topology:** 1 server (`k3d-w3w-cluster-server-0`) + 2 worker agents (`agent-0`, `agent-1`).
2. **Ingress Port Mapping:** Host port `8088` mapped to the cluster Traefik ingress controller (avoids Windows port 80 conflicts).
3. **Image Sideloading:** Injects both `greeter:test` and `ghcr.io/huynhphat22/w3w-devops-tech-exercise:latest` into the containerd cache.
4. **Ingress High Availability:** Scales the Traefik deployment to 2 replicas distributed across worker nodes.
5. **Platform Observability (Extension B):** Deploys the Prometheus server and alerting rules into the `monitoring` namespace.

### Verify Cluster Status:
```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl get pods -n monitoring
```
All nodes should be in `Ready` status, and the Prometheus pod should be `Running`.

---

## Step 3: Deploy Environments with Terraform (Core Task 4)

Deploy both `dev` and `prod` environments using Terraform.

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### What This Provisions:
* **Isolated Namespaces:** `dev` and `prod`.
* **Zero Duplication:** Reusable module `modules/greeter` deployed via `for_each = var.environments`.
* **`dev` Environment:** 2 pod replicas, greeting `"Dev-Engineer"`, routed via Ingress hostname `dev.greeter.local`.
* **`prod` Environment:** 3 pod replicas, greeting `"Prod-Operations"`, routed via Ingress hostname `prod.greeter.local`.
* **High Availability Constraints:** Pods are spread across worker nodes via `topologySpreadConstraints` and protected by `PodDisruptionBudget` (`minAvailable: 1`).

---

## Step 4: Verify Application Functionality (Core Task 3)

Verify external reachability and environment greetings via Ingress:

### Test dev Environment:
```bash
curl -H "Host: dev.greeter.local" http://127.0.0.1:8088/
# Expected: Hello Dev-Engineer, welcome to the what3words platform.
```

### Test prod Environment:
```bash
curl -H "Host: prod.greeter.local" http://127.0.0.1:8088/
# Expected: Hello Prod-Operations, welcome to the what3words platform.
```

### Test Health Probes & Metrics:
```bash
# Liveness probe (HTTP 200)
curl -H "Host: dev.greeter.local" http://127.0.0.1:8088/healthz

# Readiness probe (HTTP 200 once warmed up)
curl -H "Host: dev.greeter.local" http://127.0.0.1:8088/readyz

# Prometheus metrics endpoint
curl -H "Host: dev.greeter.local" http://127.0.0.1:8088/metrics
```

---

## Step 5: Verify Observability & Demonstrate Alert Firing (Extension B)

Prometheus discovers all application pods across `dev` and `prod` via Kubernetes service discovery and evaluates the SLO fast-burn alerting rule (`GreeterHighHttp5xxErrorRate`).

### 1. Verify Prometheus Active Targets:
```powershell
# Windows PowerShell:
.\monitoring\check-targets.ps1

# Linux / macOS / curl:
curl -s -H "Host: prometheus.local" http://127.0.0.1:8088/api/v1/targets
```
All application pods across `dev` and `prod` should report `health: "up"`.

### 2. Run the Automated Alert Demonstration:
Run the verification script to trigger `/boom` and observe the alert transition from `INACTIVE` -> `PENDING` -> `FIRING`:

```powershell
# Windows PowerShell:
.\monitoring\verify-alert.ps1

# Linux / macOS / Git Bash:
chmod +x ./monitoring/verify-alert.sh
./monitoring/verify-alert.sh
```

**What Happens:**
1. Confirms the alert is initially `INACTIVE` (`0 firing`).
2. Sends failure requests to `http://127.0.0.1:8088/boom` (which deterministically returns HTTP 500).
3. Detects the error rate exceeding the 10% threshold and transitions to `PENDING` after ~10s.
4. Holds for `30s` and transitions to `FIRING`, outputting full alert metadata, SLO labels, and runbook links.

---

## Step 6: Validate Single-Node Loss Resilience (Extension D)

Demonstrate that the service survives the total loss of a worker node without dropping a single request:

```bash
# 1. Drain worker agent-0
kubectl drain k3d-w3w-cluster-agent-0 --ignore-daemonsets --delete-emptydir-data --force --grace-period=30

# 2. Verify traffic continues without interruption on agent-1
curl -H "Host: dev.greeter.local" http://127.0.0.1:8088/
curl -H "Host: prod.greeter.local" http://127.0.0.1:8088/

# 3. Uncordon the node after testing
kubectl uncordon k3d-w3w-cluster-agent-0
```

---

## Step 7: CI Pipeline & Local Quality Gates (Extension A)

The GitHub Actions workflow lives in [`.github/workflows/ci.yml`](.github/workflows/ci.yml). To run the local equivalents of the CI quality gates:

```bash
# 1. Helm Lint & Template Validation:
helm lint charts/greeter
helm template greeter charts/greeter --values charts/greeter/values.yaml

# 2. Terraform Format & Validation:
cd terraform
terraform fmt -check
terraform validate
cd ..

# 3. Docker Build & Image Size Budget Check (< 20 MB):
docker build -t greeter:ci-test .
docker image inspect greeter:ci-test --format '{{.Size}}'
```

---

## Step 8: Teardown & Cleanup

To destroy all deployed resources and tear down the local cluster:

### Destroy Terraform Resources:
```bash
cd terraform
terraform destroy -auto-approve
cd ..
```

### Destroy Cluster:
```powershell
# Windows PowerShell:
.\cluster\down.ps1

# Linux / macOS / Git Bash:
./cluster/down.sh
```
