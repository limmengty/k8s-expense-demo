# K8s Deployment — expense-app

**DOKS · ArgoCD GitOps · Kustomize base+overlays**

---

## Quick Start

```bash
# 1. Connect to cluster
doctl kubernetes cluster kubeconfig save <cluster-id>

# 2. Install ArgoCD (one-time)
kubectl create namespace argocd
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/install.yaml

# 3. Bootstrap — ArgoCD manages everything from git (one-time)
kubectl apply -f argocd/bootstrap/root-app.yaml -n argocd

# 4. Create secrets before syncing (required)
# See "Secrets" section below — ArgoCD will fail to start pods without these.
```

---

## Structure

```
demok8s/
├── apps/
│   ├── expense-api/
│   │   ├── base/            # 13 K8s manifests (Deployment, Service, Ingress, etc.)
│   │   └── overlays/
│   │       ├── dev/         # → expense-api-dev namespace
│   │       ├── staging/    # → expense-api-staging namespace
│   │       └── prod/        # → expense-api-prod namespace, DO Managed PG
│   └── expense-ui/
│       ├── base/           # Next.js 16 standalone (port 3000)
│       └── overlays/        # dev / staging / prod
├── infrastructure/          # cert-manager, ingress-nginx, keycloak (Helm)
├── argocd/
│   ├── bootstrap/           # root-app.yaml — apply once
│   └── apps/               # ArgoCD Application manifests
└── scripts/
    ├── deploy.sh            # Updates image tag in overlay → git push
    └── rollback.sh         # argocd app rollback <app-name>
```

---

## Environments

| Env | API | UI | Keycloak |
|---|---|---|---|
| Dev | `dev-expense-api.limmengty.com` | `dev-expense.limmengty.com` | `dev-keycloak.limmengty.com` |
| Staging | `staging-expense-api.limmengty.com` | `staging-expense.limmengty.com` | `keycloak.limmengty.com` |
| Prod | `expense-api.limmengty.com` | `expense.limmengty.com` | `keycloak.limmengty.com` |

**Dev/Staging**: In-cluster PostgreSQL (5Gi PVC)  
**Prod**: DigitalOcean Managed PostgreSQL — set `REPLACE_WITH_DO_MANAGED_PG_HOST` in `apps/expense-api/overlays/prod/kustomization.yaml` before deploying.

---

## Secrets

Create all before first sync. ArgoCD won't create these.

```bash
# expense-api (repeat per namespace: expense-api-dev, expense-api-staging, expense-api-prod)
kubectl create secret generic expense-api-secret -n <namespace> \
  --from-literal=DB_PASSWORD='...' \
  --from-literal=KEYCLOAK_CLIENT_SECRET='...'

# expense-ui (repeat per namespace: expense-ui-dev, expense-ui-staging, expense-ui-prod)
kubectl create secret generic expense-ui-secret -n <namespace> \
  --from-literal=AUTH_SECRET='min-32-chars' \
  --from-literal=AUTH_KEYCLOAK_ID='expense-ui-<env>-client' \
  --from-literal=AUTH_KEYCLOAK_SECRET='...'

# Keycloak
kubectl create secret generic keycloak-secret -n keycloak --from-literal=admin-password='...'
kubectl create secret generic keycloak-db-secret -n keycloak --from-literal=postgres-password='...' --from-literal=password='...'

# cert-manager DNS challenge
kubectl create secret generic digitalocean-dns-token -n cert-manager --from-literal=token='<do-api-token>'
```

---

## Deploy

### Dev / Staging — automatic (GitOps)

Push to `develop` → CI builds image → updates `kustomization.yaml` → ArgoCD syncs automatically.

### Prod — manual gate

```bash
argocd app sync expense-api-prod
argocd app sync expense-ui-prod
```

---

## Rollback

```bash
./scripts/rollback.sh expense-api-prod      # one revision back
./scripts/rollback.sh expense-api-prod 42   # to revision 42

# Emergency (fastest, no git):
kubectl rollout undo deployment/expense-api -n expense-api-prod
kubectl rollout status deployment/expense-api -n expense-api-prod
```

---

## Sync & Verify

```bash
argocd app list                          # check all apps
argocd app get expense-api-prod           # details
argocd app get expense-api-prod --show-diff  # what will change

# Check pods
kubectl get pods -n expense-api-prod
kubectl get pods -n expense-ui-prod

# Health check
curl https://expense-api.limmengty.com/actuator/health
curl https://expense.limmengty.com
```

---

## Add a New Environment (e.g. uat)

```bash
# 1. Copy staging overlay
cp -r apps/expense-api/overlays/staging apps/expense-api/overlays/uat
# 2. Edit: namespace, hostnames, Keycloak issuer
# 3. Create ArgoCD Application (copy expense-api-staging.yaml → expense-api-uat.yaml)
# 4. Create secrets for new namespace
# 5. git add + commit + push → ArgoCD syncs automatically
```
