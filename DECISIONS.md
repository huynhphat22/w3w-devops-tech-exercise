# Architectural Decisions & Rationale

This document captures the technical reasoning, trade-offs, rejected alternatives, and assumptions made throughout this exercise.

---

## 1. Container Image & Build Architecture (Core Task 1)

### Decisions Made

1. **Base Image: `scratch` for runtime**
   - **Choice:** Multi-stage build using `golang:1.22-alpine` as builder and `FROM scratch` as the final runtime image.
   - **Rationale:** The application is written in Go and has zero external C library dependencies. Compiling with `CGO_ENABLED=0` produces a completely self-contained, statically linked binary. Using `scratch` gives us the absolute minimal attack surface: zero shell (`/bin/sh`), zero package managers (`apk`), and zero system binaries. The resulting image is **7.71 MB uncompressed** (2.36 MB compressed transfer size).
   - **Considered and Rejected:**
     - *`alpine:3.21` (~17–20 MB):* Rejected because it includes `musl`, `busybox`, `apk`, and a shell. For a service with no runtime file-system or shell requirements, keeping a shell inside a production container increases the lateral movement surface in the event of Remote Code Execution (RCE).
     - *`gcr.io/distroless/static-debian12:nonroot` (~14 MB):* Seriously considered. Distroless is a good enterprise default because it comes with `/etc/passwd`, non-root user `65532`, and CA certs pre-configured. However, `scratch` was selected because the brief explicitly called for "as minimal as possible", and copying CA certificates and user credentials from the Alpine builder yields identical security semantics with half the footprint.
   - **What we're least sure about & what would change our mind:**
     - In an enterprise environment where developers or SREs rely on in-container interactive debugging (e.g. inspecting network interfaces or checking DNS inside the pod network namespace), `scratch` makes `kubectl exec` impossible. If the cluster does not support Kubernetes Ephemeral Debug Containers (`kubectl debug`), or if in-container troubleshooting is mandatory by company policy, we would adopt `gcr.io/distroless/static:debug` or an Alpine-based image.

2. **Non-Root Execution (`USER 10001:10001`)**
   - **Choice:** Created user `appuser` (UID `10001`) and group `appuser` (GID `10001`) in the builder stage, and copied `/etc/passwd` and `/etc/group` to `scratch`.
   - **Rationale:** Principle of least privilege. Even if the orchestrator (Kubernetes) fails to enforce `runAsNonRoot: true` in its Pod Security Context, the container will never run as root (`UID 0`) by default. Numeric UID/GID is specified so that runtimes that do not consult `/etc/passwd` can enforce the restriction unambiguously.

3. **Compilation & Linker Flags (`CGO_ENABLED=0`, `-trimpath`, `-ldflags="-s -w"`)**
   - **Choice:**
     - `CGO_ENABLED=0`: Guarantees static compilation and instructs Go's `net` package to use the pure Go resolver instead of `cgo` libc NSS.
     - `-trimpath`: Removes file system paths from the compiled executable, enhancing build reproducibility and preventing information disclosure.
     - `-ldflags="-s -w"`: Strips DWARF debugging symbols and symbol tables, reducing the binary size by ~35%.
   - **Trade-off:** Stripping debug symbols means stack traces show function names and offsets, but lack full DWARF information for tools like Delve. For this service, runtime log outputs and Prometheus metrics provide adequate operational visibility.

4. **In-Build Test Execution (`RUN CGO_ENABLED=0 go test -v ./...`)**
   - **Choice:** Unit tests run inside the builder stage prior to compiling the final binary.
   - **Rationale:** Ensures that no image can be produced if any unit test fails.
   - **What we'd do differently in production:** In a production CI/CD system, tests would typically execute in a dedicated CI step to generate JUnit test reports, code coverage heatmaps, and linting reports before invoking Docker build. However, embedding it in the Dockerfile guarantees local developers cannot build broken artifacts even outside CI.

5. **Layer Caching Optimization & `.dockerignore`**
   - **Choice:** Separated dependency acquisition (`COPY app/go.mod ./` and `RUN go mod download`) from application source (`COPY app/ .`), and committed a strict `.dockerignore`.
   - **Rationale:** Keeps dependencies cached so that changes to `.go` code files do not trigger re-downloading modules. `.dockerignore` prevents repository documentation, `.git` metadata, and editor configs from busting Docker cache checksums.

6. **Direct Signal Handling (`ENTRYPOINT ["/greeter"]`)**
   - **Choice:** Exec-form entrypoint.
   - **Rationale:** Runs the binary directly as `PID 1` without a shell wrapper. This ensures OS signals (`SIGTERM` and `SIGINT`) delivered by Docker or Kubernetes are immediately received by Go's `signal.Notify` channel to drive the two-phase graceful shutdown protocol.

---

## 2. Local Kubernetes Cluster Architecture (Core Task 2)

### Decisions Made

1. **Cluster Orchestrator: `k3d` as Primary with `kind` as Fallback**
   - **Choice:** Declarative configuration files (`cluster/k3d.yaml` and `cluster/kind.yaml`) supported by idempotent automation scripts (`up.sh`, `up.ps1`, `down.sh`, `down.ps1`).
   - **Rationale:** 
     - *Speed & Resource Efficiency:* `k3d` runs lightweight k3s nodes inside Docker containers, spinning up a 3-node cluster in under 15 seconds with negligible memory footprint compared to full `kubeadm`-based distributions.
     - *Built-in Ingress Routing:* `k3d` includes a dedicated host-level load balancer container (`k3d-proxy`) routing traffic to Traefik on port 80/443 out-of-the-box, eliminating the need for MetalLB or tunnel daemons to expose workloads outside the cluster.
     - *Image Sideloading:* Supports direct image injection (`k3d image import greeter:test -c w3w-cluster`) without requiring an external container registry or internet connectivity.
   - **Considered and Rejected:**
     - *`minikube`:* Rejected due to heavier resource overhead, slower multi-node provisioning, and the requirement for external tunnel daemons (`minikube tunnel`) to expose ingress ports on non-Linux hosts.
     - *Imperative CLI commands:* Rejected. Creating clusters via raw CLI flags (`k3d cluster create ... --agents 2 ...`) makes configuration drift hard to track. A checked-in declarative YAML spec (`k3d.yaml` / `kind.yaml`) guarantees version-controlled reproducibility.
   - **What we're least sure about & what would change our mind:**
     - While `k3d`'s default Traefik ingress is convenient, some organizations strictly standardize on Ingress-NGINX. If the assessment expects Ingress-NGINX specifically, we can disable Traefik via `extraArgs: [--disable=traefik]` and install the NGINX ingress controller. Our fallback `kind.yaml` includes the Ingress-NGINX controller deployment.

2. **Node Topology: 1 Control Plane + 2 Dedicated Worker Nodes**
   - **Choice:** 1 server (`k3d-w3w-cluster-server-0`) and 2 worker agents (`agent-0`, `agent-1`).
   - **Rationale:** Strict fulfillment of the requirement ("at least two worker nodes"). Worker workloads (Core Task 3) can be spread across `agent-0` and `agent-1` using `podAntiAffinity` or `topologySpreadConstraints`. This topology enables node-drain chaos testing (Extension D) where one worker node is cordon/drained while traffic continuously flows to the surviving worker node without impacting the control plane.

3. **Cross-Platform Automation (Bash + PowerShell)**
   - **Choice:** Maintained dual automation scripts (`up.sh` and `up.ps1`).
   - **Rationale:** Assessors may evaluate the exercise on macOS, Linux, or Windows. Providing idiomatic PowerShell and POSIX bash scripts removes host friction.

---

## 3. Packaging the Service with Helm (Core Task 3)

### Decisions Made

1. **Packaging Tool: Hand-Crafted Helm Chart vs. Kustomize**
   - **Choice:** Helm chart written from scratch without `helm create` boilerplate (`charts/greeter/`).
   - **Rationale:** 
     - *Clean Integration with Terraform (Task 4):* The official `hashicorp/helm` provider (`helm_release`) allows seamless parameterization of environments (`dev` vs `prod`) via typed HCL variables without duplicating YAML trees.
     - *Rejecting Boilerplate:* We deliberately rejected the default `helm create` scaffold. It generates dozens of unused helper templates (`_helpers.tpl`), ServiceAccount definitions (the greeter app does not interact with the Kubernetes API), NOTES.txt, and auto-scaling definitions that obscure intent. Instead, we created a minimal, readable 5-resource chart (`Deployment`, `Service`, `Ingress`, `ConfigMap`, `PodDisruptionBudget`) where every single line is justified.
   - **Considered and Rejected:**
     - *Kustomize:* Kustomize is great for static overlays, but deploying Kustomize through Terraform is cumbersome (requiring third-party providers like `kustomization` or raw `kubectl_manifest` loops). Helm provides a unified release lifecycle (rollback, atomic deployments, status tracking).
   - **What we're least sure about & what would change our mind:**
     - For GitOps engines like Argo CD or Flux (Extension C), teams often prefer pure Kustomize to avoid Helm templating runtime errors. If our target deployment workflow mandates pure GitOps without Terraform, Kustomize would be a strong alternative.

2. **External Access: Ingress over NodePort / LoadBalancer**
   - **Choice:** `networking.k8s.io/v1` `Ingress` routing to a `ClusterIP` Service on port 80.
   - **Rationale:** 
     - `Ingress` exposes standard HTTP/HTTPS on ports 80/443 and natively leverages host port mappings established in Core Task 2.
     - Catch-all path routing (`/` Prefix) enables instant reachability at `http://localhost/` without requiring local `/etc/hosts` DNS alterations, while optionally supporting custom host headers (`greeter.local`).
   - **Considered and Rejected:**
     - *`NodePort`:* Rejected as primary. NodePort forces client traffic through arbitrary high ports (`30000-32767`), which does not reflect production ingress architecture.
     - *`LoadBalancer`:* In bare-metal or local Docker setups, `LoadBalancer` services stay in `<pending>` state unless coupled with an in-cluster load balancer implementation like MetalLB. Ingress works out of the box with k3d (Traefik) and kind (Ingress-NGINX).

3. **High Availability & Surviving Single-Node Loss**
   - **Choice:** 
     - Default `replicaCount: 2` (or 3 in prod).
     - `topologySpreadConstraints` with `topologyKey: kubernetes.io/hostname` and `maxSkew: 1`.
     - `PodDisruptionBudget` (`minAvailable: 1`).
     - `RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 1`.
   - **Rationale:** Spreading replicas across worker nodes ensures that if worker `agent-0` fails or is drained (Extension D), worker `agent-1` continues serving traffic without interruption. The PDB prevents voluntary drains from killing all replicas at once, while `maxUnavailable: 0` guarantees zero downtime during rollouts.

4. **Probe Timers and Shutdown Accommodation**
   - **Choice:**
     - **Liveness Probe:** `/healthz`, `initialDelaySeconds: 2`, `periodSeconds: 10`, `failureThreshold: 3`. Liveness passes throughout startup and warmup, ensuring pods are never killed prematurely while warming up.
     - **Readiness Probe:** `/readyz`, `initialDelaySeconds: 5`, `periodSeconds: 2`, `failureThreshold: 2`. Probed aggressively (every 2s) so that the cluster quickly catches the transition from warmup to ready, and rapidly evicts terminating pods from endpoints during the 10s shutdown delay.
     - **Termination Grace Period:** Configured to **45 seconds** in the pod spec.
   - **Rationale:** The application requires 10s (`SHUTDOWN_DELAY_SECONDS`) to fail readiness and hold traffic, followed by up to 20s (`DRAIN_TIMEOUT_SECONDS`) to drain in-flight requests. A 45s termination grace period provides a 15s margin before the kubelet issues `SIGKILL`.

5. **Decoupled Configuration & Automated Rollouts**
   - **Choice:** Environment variables are externalized in a `ConfigMap` referenced via `envFrom`. The Deployment template embeds `checksum/config` in its pod annotations.
   - **Rationale:** Operators can modify `greetingName`, timeouts, or port settings in `values.yaml` without touching container images. The SHA256 checksum annotation ensures that any ConfigMap change triggers an automatic, zero-downtime rolling restart of the pods.

---

## 4. Multi-Environment Deployment with Terraform (Core Task 4)

### Decisions Made

1. **Multi-Environment Architecture: Reusable Module with Map Iteration**
   - **Choice:** Created a reusable child module (`terraform/modules/greeter/`) instantiated via `for_each = var.environments` in the root configuration, supplemented by standalone var-files (`dev.tfvars` and `prod.tfvars`).
   - **Rationale:** 
     - *Zero Duplication:* Directly satisfies the brief's constraint (*"without duplicating the whole configuration"*). The underlying resources (`kubernetes_namespace`, `helm_release`) and Helm parameter mapping exist in exactly one place.
     - *Multi-Tenant Coexistence:* Deploys `dev` (2 replicas, `"Dev-Engineer"`, namespace `dev`) and `prod` (3 replicas, `"Prod-Operations"`, namespace `prod`) simultaneously into isolated namespaces with non-conflicting Ingress host headers (`dev.greeter.local` vs. `prod.greeter.local`).
   - **Considered and Rejected:**
     - *Directory Duplication (`environments/dev/` vs `environments/prod/`):* Rejected. Copy-pasting HCL code across folders causes configuration drift whenever variables, provider versions, or lifecycle hooks are updated.
     - *Terraform Workspaces:* Considered. While workspaces share configuration, local workspace switching is state-dependent (`terraform workspace select`) and prone to human error (accidentally applying dev changes to prod). Explicit namespaces and maps make environmental boundaries declarative and visible in a single plan.
     - *Terragrunt:* Industry standard for DRY multi-environment Terraform, but rejected to avoid introducing external binary requirements beyond standard `terraform`.
   - **What we're least sure about & what would change our mind:**
     - In large-scale enterprise environments, using Terraform for application-layer deployments is often considered an anti-pattern: it bloats the Terraform state file, slows down `plan` execution, and entangles cluster infrastructure lifecycle with application deployment velocity. If this service were part of a microservice ecosystem, we would limit Terraform to provisioning cluster infrastructure (namespaces, RBAC, ingress controllers) and delegate application deployments to a GitOps operator like Argo CD or Flux.

2. **Provider Integration: `hashicorp/helm` with `yamlencode`**
   - **Choice:** Used `helm_release` with `values = [yamlencode({ ... })]`.
   - **Rationale:** Strongly typed HCL objects are converted into YAML values dynamically. This avoids the fragility of dozens of repetitive `set` blocks and ensures that unset values naturally fall back to the Helm chart's hardened defaults.

---

## 5. Operational & Orchestration Assumptions

### Ambiguities & Assumptions
- **Configuration Mechanism:** The application reads configuration exclusively from environment variables (`GREETING_NAME`, `PORT`, `VERSION`, `WARMUP_SECONDS`, `SHUTDOWN_DELAY_SECONDS`, `DRAIN_TIMEOUT_SECONDS`). Environment variables in Kubernetes are passed via `ConfigMap` and Deployment specs, allowing per-environment customization without image rebuilds.
- **Grace Period Sizing:** Because the application enforces a 10s shutdown delay (`SHUTDOWN_DELAY_SECONDS`) plus up to a 20s drain period (`DRAIN_TIMEOUT_SECONDS`), Kubernetes `terminationGracePeriodSeconds` must be set to $\ge 35\text{s}$ (e.g. 45s) to prevent the kubelet from prematurely sending `SIGKILL`.



