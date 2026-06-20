# Why Senior DevOps Engineers Don't Run Stateful Apps in Kubernetes

> **TL;DR** — Kubernetes was designed for stateless, ephemeral workloads. Stateful applications like databases and identity providers have fundamentally different operational needs. Running them in K8s adds complexity without meaningful benefit, and introduces real risk to your most critical data.

---

## What "Stateful" Means

A **stateless** app (expense-api, expense-ui) can be killed and restarted on any node at any time — it holds no data locally, so losing a pod loses nothing.

A **stateful** app (PostgreSQL, Keycloak) owns persistent data. Losing a pod incorrectly, a botched upgrade, or a storage race condition can corrupt or permanently destroy that data.

---

## The Core Problems With Stateful Apps in K8s

### 1. Storage Is Complex and Risky

Kubernetes volumes (PVCs) add layers between your app and the disk:

```
App → Container → CSI Driver → Cloud Block Storage → Disk
```

Each layer is a potential failure point:
- **Multi-attach errors** — two pods accidentally mounting the same `ReadWriteOnce` volume → data corruption
- **Detach/attach latency** — during node failures, Kubernetes waits up to 6 minutes before forcibly detaching a volume; your DB is down that entire time
- **Storage class mismatches** — wrong IOPS tier silently kills database performance

On a dedicated VM, you have:
```
App → Disk
```

### 2. StatefulSets Are Not Databases

StatefulSets give pods stable hostnames and ordered startup — that's it. They do **not** provide:

- Automatic failover
- Replication management
- Backup orchestration
- Point-in-time recovery
- Connection pooling
- Schema migration safety

You have to build all of this yourself on top of K8s. Managed databases (DigitalOcean Managed PG, RDS, Cloud SQL) and dedicated VMs with Docker give you most of this out of the box.

### 3. Node Maintenance Breaks Everything

When Kubernetes drains a node (upgrades, scaling, spot instance reclaim):

**Stateless pod** → evicted → rescheduled on new node in ~5 seconds → traffic resumes.

**Stateful pod (DB)** →
1. Pod evicted
2. Kubernetes waits for volume to detach (30s–6min)
3. Pod rescheduled on new node
4. Volume reattaches
5. Database cold-starts, runs recovery
6. Ready → 2–10 minutes of downtime

### 4. Kubernetes Upgrades Are Now High-Risk

Every K8s cluster upgrade (e.g., 1.29 → 1.30) involves:
- Rolling node replacements
- Pod evictions across every node
- Potential CSI driver version changes

For stateless apps: zero-downtime rolling upgrade.
For a database pod: see point 3 above — guaranteed downtime window per upgrade.

### 5. Backup and Restore Is Your Problem

K8s has no native backup for PVC data. You need:
- Velero or Kasten for volume snapshots
- Custom CronJobs for `pg_dump`
- Tested restore procedures

On a managed DB service or a VM with Docker:
- Automated daily backups included
- Point-in-time restore via console
- Tested by the provider, not you

### 6. Resource Contention With Your Apps

Running PostgreSQL on the same cluster as your application workloads means:
- A traffic spike in expense-api can starve the database of CPU/memory
- `OOMKiller` can terminate your DB pod mid-transaction
- Node pressure eviction can kill your DB without warning

K8s `PriorityClasses` help but don't fully solve this. A dedicated VM has no competition.

---

## What Senior Engineers Do Instead

### Databases → Managed Cloud Service

| Provider | Service |
|----------|---------|
| DigitalOcean | Managed PostgreSQL |
| AWS | RDS / Aurora |
| GCP | Cloud SQL |
| Azure | Azure Database for PostgreSQL |

**Why:**
- Automated failover (seconds, not minutes)
- Daily backups + point-in-time restore
- Read replicas with one click
- No operational overhead on your K8s cluster

### Identity Providers (Keycloak) → Dedicated VM + Docker

```
┌─────────────────────────────┐
│  VM  (2 vCPU / 4 GB RAM)   │
│                             │
│  docker-compose.yml         │
│  ├── keycloak:26            │
│  └── postgres:16            │
│                             │
│  Daily: pg_dump → S3/R2     │
│  Nginx reverse proxy + TLS  │
└─────────────────────────────┘
```

**Why Keycloak specifically:**
- Keycloak is **session-critical** — if it goes down, no user can log in to any app
- It manages realm config, client secrets, user data — all stateful
- Its JGroups clustering (multi-pod HA) requires persistent shared caches — complex in K8s
- A single well-configured VM with Docker is simpler, faster, and more predictable

### Queues / Caches (Redis, RabbitMQ) → Same Rule

| App | Recommendation |
|-----|---------------|
| Redis (cache) | ElastiCache / DigitalOcean Managed Redis |
| Redis (persistent) | Dedicated VM |
| RabbitMQ | CloudAMQP or dedicated VM |
| Kafka | Confluent Cloud or dedicated VM |

---

## The Rule of Thumb

> **If losing the pod for 5 minutes causes data loss or auth failures across your entire platform — it does not belong in Kubernetes.**

| Workload | In K8s? | Why |
|----------|---------|-----|
| expense-api | ✅ Yes | Stateless, scales horizontally |
| expense-ui | ✅ Yes | Stateless, scales horizontally |
| ingress-nginx | ✅ Yes | Stateless proxy |
| cert-manager | ✅ Yes | Stateless controller |
| PostgreSQL (dev) | ⚠️ Dev only | Acceptable for dev, not prod |
| PostgreSQL (prod) | ❌ No | Use managed service |
| Keycloak (prod) | ❌ No | Dedicated VM + Docker |

---

## For This Project (limmengty/k8s-expense-demo)

### Current State (demo/learning)

Running Keycloak and PostgreSQL in K8s is fine **for learning purposes**. It teaches you:
- StatefulSets and PVCs
- Kubernetes storage classes
- Multi-service deployments

### Production Migration Path

```
Phase 1 (now)       Phase 2 (staging)      Phase 3 (prod)
─────────────────   ────────────────────   ─────────────────────
K8s everything   →  Migrate DB to DO PG →  Migrate Keycloak to VM
(learning)          (managed service)      (Docker Compose + Nginx)
```

**Production architecture target:**

```
                    ┌──────────────────────────────┐
                    │  DOKS Cluster                │
                    │  ┌────────┐  ┌────────────┐  │
Internet ──> nginx ──> │ api   │  │  ui        │  │
                    │  └───┬───┘  └─────┬──────┘  │
                    └──────┼────────────┼──────────┘
                           │            │
              ┌────────────▼──┐    ┌────▼─────────────┐
              │ DO Managed PG │    │ VM: Keycloak      │
              │ (automated    │    │ (Docker Compose + │
              │  backups, HA) │    │  Nginx + certbot) │
              └───────────────┘    └──────────────────┘
```

---

## Summary

Kubernetes excels at running many copies of stateless services reliably. It was not designed to be a database platform. Every layer of abstraction K8s adds between your stateful app and its storage is a new failure mode.

Senior engineers don't avoid stateful apps in K8s because they "can't" run them — they avoid it because the operational burden, failure modes, and recovery complexity are not worth it when better-suited alternatives exist.

**Use the right tool for the job:**
- K8s for stateless, scalable workloads
- Managed services or dedicated VMs for stateful, data-critical workloads
