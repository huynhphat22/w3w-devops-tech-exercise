# Terraform Deployment for Greeter Service

This directory provisions the `greeter` application onto Kubernetes using Terraform and the official `hashicorp/helm` provider, fulfilling **Core Task 4**.

---

## Architecture: Zero Duplication Multi-Environment Pattern

The configuration satisfies the requirement:
> *"There must be two environments — call them `dev` and `prod` — that differ in at least their greeting name and their replica count, without duplicating the whole configuration."*

### Reusable Child Module (`modules/greeter`)
A single, parameterized Terraform module encapsulates:
1. `kubernetes_namespace`: Creates dedicated, isolated namespaces (`dev` and `prod`).
2. `helm_release`: Deploys the hand-crafted Helm chart from `../../charts/greeter` using `yamlencode` to inject environment-specific overrides (`greetingName`, `replicaCount`, `ingress.host`).

### Root Configuration (`main.tf`)
The root module iterates over `var.environments` using `for_each`:

| Environment | Namespace | Replicas | Greeting Name | Ingress Host |
|---|---|---|---|---|
| **`dev`** | `dev` | **2** | `"Dev-Engineer"` | `dev.greeter.local` |
| **`prod`** | `prod` | **3** | `"Prod-Operations"` | `prod.greeter.local` |

---

## Usage

### Prerequisites
1. Ensure your Kubernetes cluster is active (`w3w-cluster`).
2. Ensure the container image is loaded into the cluster:
   ```bash
   k3d image import greeter:test -c w3w-cluster
   # OR for kind:
   kind load docker-image greeter:test --name w3w-cluster
   ```

### Option 1: Deploy Both Environments Simultaneously (Default)
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Option 2: Deploy Environments Individually via Var-Files
```bash
# Deploy dev only:
terraform apply -var-file="environments/dev.tfvars"

# Deploy prod only:
terraform apply -var-file="environments/prod.tfvars"
```

---

## Verifying Deployment

```bash
# Check namespaces & pods
kubectl get pods -n dev
kubectl get pods -n prod

# Test external access via host headers (using port 8088 configured in cluster/k3d.yaml)
curl -H "Host: dev.greeter.local" http://localhost:8088/
# Output: Hello Dev-Engineer, welcome to the what3words platform.

curl -H "Host: prod.greeter.local" http://localhost:8088/
# Output: Hello Prod-Operations, welcome to the what3words platform.
```

