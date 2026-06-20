# K8s Cluster Setup Guide — expense-app

**Target: DigitalOcean DOKS · ArgoCD GitOps**

---

## Prerequisites

Install these tools on your machine before starting.

```bash
# kubectl — Kubernetes CLI
# https://kubernetes.io/docs/tasks/tools/install-kubectl/

# doctl — DigitalOcean CLI (download from https://docs.digitalocean.com/reference/doctl/how-to/install/)
# or: brew install doctl

# kustomize — K8s manifest templating (required by deploy scripts)
# or: brew install kustomize

# argocd — ArgoCD CLI
# or: brew install argocd

# yamllint — YAML validation (optional, used by pre-commit-check.sh)
# or: pip install yamllint
```

---

## Step 1 — Create DOKS Cluster

### 1.1 Authenticate with DigitalOcean

```bash
doctl auth init
# Enter your DO API token when prompted
# Create one at: https://cloud.digitalocean.com/account/api/tokens
```

### 1.2 Create the cluster

```bash
doctl kubernetes cluster create expense-cluster \
  --region sgp \
  --version 1.30 \
  --size s-2vcpu-4gb \
  --count 2 \
  --node-pool name=default;size=s-2vcpu-4gb;count=2
```

> **Region**: Use `sgp` (Singapore) or `nyc` (New York) — pick closest to your users.  
> **Version**: 1.30 — DOKS supports up to latest stable. Check `doctl kubernetes get-versions`.  
> **Node size**: 2 vCPU / 4 GB is sufficient for dev/staging. Use 4 vCPU/8 GB for prod.

### 1.3 Save kubeconfig

```bash
doctl kubernetes cluster kubeconfig save expense-cluster
kubectl get nodes   # verify connection
```

Expected output:
```
NAME                        STATUS   ROLES    AGE   VERSION
expense-cluster-default-xxx Ready    <none>   2m    v1.30.x
expense-cluster-default-yyy Ready    <none>   2m    v1.30.x
```

---

## Step 2 — Install ArgoCD

### 2.1 Create namespace and apply ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/install.yaml
```

### 2.2 Wait for ArgoCD server to be ready

```bash
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
```

### 2.3 Get the initial admin password

```bash
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
echo "Password: $ARGOCD_PASSWORD"
```

### 2.4 Port-forward to access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
# Open: https://localhost:8080
# Login: admin / <password from step 2.3>
```

### 2.5 Install ArgoCD CLI and login

```bash
# macOS
brew install argocd

# Login via CLI (skip cert warning since we're using localhost port-forward)
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure
```

### 2.6 Change the admin password

```bash
argocd account update-password \
  --current-password "$ARGOCD_PASSWORD" \
  --new-password "your-secure-new-password"
```

---

## Step 3 — Clone the Repo and Configure

```bash
git clone https://github.com/limmengty/k8s-expense-demo.git
cd k8s-expense-demo/demok8s

# Verify all overlays build correctly
./scripts/pre-commit-check.sh
```

---

## Step 4 — Create Secrets (Required Before First Sync)

> ArgoCD will create all Deployments/Services/Ingresses, but **secrets must exist** or pods will fail to start with `ImagePullBackOff` or secret-related errors.

### 4.1 Create all namespaces

```bash
kubectl create namespace expense-api-dev
kubectl create namespace expense-api-staging
kubectl create namespace expense-api-prod
kubectl create namespace expense-ui-dev
kubectl create namespace expense-ui-staging
kubectl create namespace expense-ui-prod
kubectl create namespace keycloak
kubectl create namespace cert-manager
kubectl create namespace ingress-nginx
```

### 4.2 expense-api secrets

```bash
# === DEV ===
kubectl create secret generic expense-api-secret \
  -n expense-api-dev \
  --from-literal=DB_PASSWORD='DevDbPassword123!' \
  --from-literal=KEYCLOAK_CLIENT_SECRET='dev-keycloak-secret'

# === STAGING ===
kubectl create secret generic expense-api-secret \
  -n expense-api-staging \
  --from-literal=DB_PASSWORD='StagingDbPassword123!' \
  --from-literal=KEYCLOAK_CLIENT_SECRET='staging-keycloak-secret'

# === PROD ===
kubectl create secret generic expense-api-secret \
  -n expense-api-prod \
  --from-literal=DB_PASSWORD='ProdDbPassword123!' \
  --from-literal=KEYCLOAK_CLIENT_SECRET='prod-keycloak-secret'
```

### 4.3 expense-ui secrets

```bash
# === DEV ===
kubectl create secret generic expense-ui-secret \
  -n expense-ui-dev \
  --from-literal=AUTH_SECRET='dev-auth-secret-min-32-chars!!' \
  --from-literal=AUTH_KEYCLOAK_ID='expense-ui-dev-client' \
  --from-literal=AUTH_KEYCLOAK_SECRET='dev-keycloak-secret'

# === STAGING ===
kubectl create secret generic expense-ui-secret \
  -n expense-ui-staging \
  --from-literal=AUTH_SECRET='staging-auth-secret-min-32-chars!' \
  --from-literal=AUTH_KEYCLOAK_ID='expense-ui-staging-client' \
  --from-literal=AUTH_KEYCLOAK_SECRET='staging-keycloak-secret'

# === PROD ===
kubectl create secret generic expense-ui-secret \
  -n expense-ui-prod \
  --from-literal=AUTH_SECRET='prod-auth-secret-min-32-chars!!' \
  --from-literal=AUTH_KEYCLOAK_ID='expense-ui-prod-client' \
  --from-literal=AUTH_KEYCLOAK_SECRET='prod-keycloak-secret'
```

### 4.4 Keycloak secrets

```bash
kubectl create secret generic keycloak-secret \
  -n keycloak \
  --from-literal=admin-password='KeycloakAdmin123!'

kubectl create secret generic keycloak-db-secret \
  -n keycloak \
  --from-literal=postgres-password='KeycloakDbPassword123!' \
  --from-literal=password='KeycloakDbPassword123!'
```

### 4.5 cert-manager DNS token

```bash
# Create a DigitalOcean API token with "Read and Write" DNS permissions
# at: https://cloud.digitalocean.com/account/api/tokens

kubectl create secret generic digitalocean-dns-token \
  -n cert-manager \
  --from-literal=token='your-digitalocean-dns-api-token'
```

---

## Step 5 — Bootstrap ArgoCD (App of Apps)

This single command makes ArgoCD manage **all** Kubernetes resources from the git repo:

```bash
kubectl apply -f argocd/bootstrap/root-app.yaml -n argocd
```

### Verify root-app is synced

```bash
argocd app get root-app
# Expected: Sync Status = Synced, Health = Healthy
```

---

## Step 6 — Verify All Apps Are Synced

```bash
argocd app list
```

| App | Status | Sync |
|---|---|---|
| `root-app` | `Synced` | automated |
| `expense-api-dev` | `Synced` | automated |
| `expense-api-staging` | `Synced` | automated |
| `expense-ui-dev` | `Synced` | automated |
| `expense-ui-staging` | `Synced` | automated |
| `infra-cert-manager` | `Synced` | automated |
| `infra-ingress-nginx` | `Synced` | automated |
| `infra-keycloak` | `Synced` | automated |
| `expense-api-prod` | `OutOfSync` | **manual** |
| `expense-ui-prod` | `OutOfSync` | **manual** |

> **OutOfSync on prod is expected** — prod requires manual approval before deployment.

### Check pod status

```bash
kubectl get pods -n expense-api-dev
kubectl get pods -n expense-ui-dev
kubectl get pods -n keycloak

# All should show: Running (1/1 or 2/2), not CrashLoopBackOff
```

---

## Step 7 — Verify Ingress and TLS

### Wait for TLS certificates to be issued

cert-manager requests certificates from Let's Encrypt automatically via DNS-01 challenge.

```bash
kubectl get certificate -A --watch
# Wait for: READY=True on all certificates
# This can take 1-5 minutes after the first ingress sync
```

### Check ingress status

```bash
kubectl get ingress -n expense-api-dev
# Expected: ADDRESS populated (DO LoadBalancer IP), HOSTS show your domains
```

### Test the endpoints

```bash
curl -sf https://dev-expense-api.limmengty.com/actuator/health
# Expected: {"status":"UP"}

curl -sf https://dev-expense.limmengty.com
# Expected: HTML page (Next.js frontend)
```

---

## Step 8 — Production Setup (One-Time)

### 8.1 Provision DigitalOcean Managed PostgreSQL

```
Console → Databases → Create Database
  Engine: PostgreSQL 16
  Region: same as your DOKS cluster
  Size: 1 GB / 1 vCPU (start small)
 副本: None (dev) or 1 standby (prod)
```

Save the connection host (e.g. `db-xxx-0.g.db.ondigitalocean.com`) and port (`25060`).

### 8.2 Update prod overlay with real DB connection

Edit `apps/expense-api/overlays/prod/kustomization.yaml` and replace:

```yaml
# BEFORE (placeholder)
value: "jdbc:postgresql://REPLACE_WITH_DO_MANAGED_PG_HOST:25060/expense_db?sslmode=require"

# AFTER (real values from DO console)
value: "jdbc:postgresql://db-xxx-0.g.db.ondigitalocean.com:25060/expense_db?sslmode=require"
```

Commit and push:
```bash
git add apps/expense-api/overlays/prod/kustomization.yaml
git commit -m "fix(prod): use real DO Managed PG host"
git push
```

### 8.3 Sync prod apps manually

```bash
argocd app sync expense-api-prod
argocd app sync expense-ui-prod
argocd app wait expense-api-prod --sync --health --timeout 300
argocd app wait expense-ui-prod --sync --health --timeout 300
```

---

## Step 9 — Verify Production Deploy

```bash
# Check all prod pods
kubectl get pods -n expense-api-prod
kubectl get pods -n expense-ui-prod

# Health checks
curl -sf https://expense-api.limmengty.com/actuator/health
curl -sf https://expense.limmengty.com

# TLS certificates
kubectl get certificate -A
```

---

## Uninstall / Tear Down

```bash
# Remove ArgoCD and all managed resources (including argocd namespace itself)
argocd app delete root-app --cascade

# Or manually:
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/install.yaml

# Delete the DOKS cluster entirely
doctl kubernetes cluster delete expense-cluster
```
