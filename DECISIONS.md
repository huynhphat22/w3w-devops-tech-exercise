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

## 2. Cluster & Orchestration Assumptions

### Ambiguities & Assumptions
- **Configuration Mechanism:** The application reads configuration exclusively from environment variables (`GREETING_NAME`, `PORT`, `VERSION`, `WARMUP_SECONDS`, `SHUTDOWN_DELAY_SECONDS`, `DRAIN_TIMEOUT_SECONDS`). Environment variables in Kubernetes will be passed via `ConfigMap` and Deployment specs, allowing per-environment customization without image rebuilds.
- **Grace Period Sizing:** Because the application enforces a 10s shutdown delay (`SHUTDOWN_DELAY_SECONDS`) plus up to a 20s drain period (`DRAIN_TIMEOUT_SECONDS`), Kubernetes `terminationGracePeriodSeconds` must be set to $\ge 35\text{s}$ (e.g. 45s) to prevent the kubelet from prematurely sending `SIGKILL`.
