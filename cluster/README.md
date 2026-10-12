# Multi-Node Kubernetes Cluster Setup

This directory contains the declarative configurations and automation scripts to provision a reproducible **multi-node Kubernetes cluster** locally, fulfilling **Core Task 2**.

---

## Topology

* **1 Control Plane Node:** Handles API Server, Scheduler, and Controller Manager.
* **2 Worker Nodes (`agents` / `workers`):**
  * `agent-0` / `worker-1`
  * `agent-1` / `worker-2`
* **Ingress / Load Balancer:**
  * Host port `80` mapped to cluster Ingress controller.
  * Host port `443` mapped to cluster HTTPS Ingress.

This topology guarantees that pods can be scheduled with pod anti-affinity across independent nodes to survive single-node failures (Core Task 3 & Extension D).

---

## Quickstart

### Option A: Using k3d (Recommended & Default)
Requires `k3d` (installed via Homebrew, Chocolatey, or official script):

```bash
# On Linux / macOS / Git Bash:
./cluster/up.sh

# On Windows PowerShell:
.\cluster\up.ps1
```

### Option B: Using kind
If `k3d` is not installed, the scripts automatically fall back to `kind`:

```bash
kind create cluster --config cluster/kind.yaml
```

---

## Loading Local Container Images

To test locally built images without pushing to an external registry:

* **k3d:**
  ```bash
  k3d image import greeter:test -c w3w-cluster
  ```

* **kind:**
  ```bash
  kind load docker-image greeter:test --name w3w-cluster
  ```

---

## Teardown

```bash
# On Linux / macOS / Git Bash:
./cluster/down.sh

# On Windows PowerShell:
.\cluster\down.ps1
```
