# Development Guide

## Repository Overview

Production GitOps repository managing a K3s Kubernetes cluster. All infrastructure is declarative and managed through ArgoCD. Changes to manifests in Git automatically sync to the cluster.

**Critical**: This repository manages production workloads. Always verify changes won't delete or break existing services (Unifi Network Controller, Step-CA).

## GitOps Architecture

### App-of-Apps Pattern

```
root Application (clusters/plex-r620/argocd/root-app.yaml)
  ├── Watches: clusters/plex-r620/**
  ├── Auto-syncs: true (selfHeal enabled)
  └── Manages all child Applications
```

Key files:
- `clusters/plex-r620/argocd/root-app.yaml` — root application watching entire cluster directory
- `clusters/plex-r620/argocd/argocd-app-*.yaml` — individual application definitions

### Directory Structure

```
clusters/plex-r620/
├── argocd/              # ArgoCD installation + app definitions
├── security/            # Security policies (Kyverno, Falco, Trivy)
│   ├── kyverno/        # Admission control policies
│   ├── falco/          # Runtime threat detection
│   └── trivy-operator/ # Vulnerability scanning
├── networking/          # Network policies, ingress configs
└── applications/        # Application workloads
    ├── unifi/          # Unifi Network Controller (PRODUCTION)
    ├── step-ca/        # Internal Certificate Authority
    └── cert-manager/   # Certificate management
```

## Core Workflow

### Making Changes

1. Read existing manifests before modifying production apps
2. Edit YAML files in Git
3. Pre-commit hooks validate automatically
4. Commit and push — ArgoCD auto-syncs via selfHeal

### Checking Sync Status

```bash
kubectl get applications -n argocd
kubectl get application <app-name> -n argocd
kubectl get application <app-name> -n argocd -w

# Manual sync
kubectl patch application <app-name> -n argocd --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"prune":true}}}'
```

## Security Architecture

### Pre-Commit Hooks

Run automatically on `git commit`:
- YAML/JSON syntax validation
- Secret scanning (detect-private-key)
- Image tag validation (no `:latest`)
- Security context checks (runAsNonRoot, readOnlyRootFilesystem)
- Privileged container detection

```bash
pre-commit install       # install hooks
pre-commit run --all-files  # run manually
```

### Kyverno Policies

Located in `clusters/plex-r620/security/kyverno/`:
- `pod-security-baseline.yaml` — PSS baseline controls
- `disallow-latest-tag.yaml` — require specific image versions
- `require-non-root.yaml` — enforce runAsNonRoot
- `require-readonly-rootfs.yaml` — enforce read-only root filesystems
- `require-resource-limits.yaml` — require CPU/memory limits

To bypass: create `PolicyException` resources (see `applications/unifi/policy-exceptions.yaml`).

## Production Applications

### Unifi Network Controller

**Location**: `clusters/plex-r620/applications/unifi/`
**Status**: PRODUCTION — manages network infrastructure
**Access**: https://unifi.homelab.local (192.168.100.100:8443)

- PVCs: `unifi-data`, `unifi-db` — do not delete
- Requires Kyverno PolicyExceptions (runs as root, needs writable filesystem)
- Image version must match database version

### ArgoCD

**Access**: https://argo.homelab.local (192.168.100.103:8443)

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### Certificate Management

- **Step-CA**: internal CA issuing certificates
- **cert-manager**: Kubernetes certificate controller
- Chain: Leaf → R620 Homelab Intermediate CA → R620 Homelab Root CA

## Common Tasks

### Deploy New Application

1. Create `clusters/plex-r620/applications/<app-name>/`
2. Add manifests: deployment, service, ingress, etc.
3. Create `clusters/plex-r620/argocd/argocd-app-<app-name>.yaml`
4. Commit and push — ArgoCD auto-discovers via root app

### Create Kyverno PolicyException

```yaml
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: <app>-exceptions
  namespace: <namespace>
spec:
  exceptions:
  - policyName: <policy-name>
    ruleNames:
    - <rule-name>
  match:
    any:
    - resources:
        kinds: [Deployment, Pod]
        namespaces: [<namespace>]
        names: ["<app-name>*"]
```

### Generate TLS Certificate from Step-CA

```bash
kubectl exec -n step-ca step-ca-0 -- step certificate create \
  <hostname> /tmp/<name>.crt /tmp/<name>.key \
  --profile leaf --not-after 2160h --kty RSA --size 2048 \
  --ca /home/step/certs/intermediate-ca.crt \
  --ca-key /home/step/secrets/intermediate-ca.key \
  --no-password --insecure

kubectl cp step-ca/step-ca-0:/tmp/<name>.crt /tmp/<name>.crt
kubectl cp step-ca/step-ca-0:/tmp/<name>.key /tmp/<name>.key
kubectl cp step-ca/step-ca-0:/home/step/certs/intermediate-ca.crt /tmp/intermediate-ca.crt

cat /tmp/<name>.crt /tmp/intermediate-ca.crt > /tmp/<name>-fullchain.crt

kubectl create secret tls <secret-name> -n <namespace> \
  --cert=/tmp/<name>-fullchain.crt --key=/tmp/<name>.key
```

### Add DNS Entry to CoreDNS

```bash
kubectl patch configmap coredns -n kube-system --type merge \
  -p '{"data":{"NodeHosts":"<existing entries>\n192.168.100.X <hostname>\n"}}'
kubectl rollout restart deployment coredns -n kube-system
```

## Cluster Details

| Property | Value |
|---|---|
| Distribution | K3s, single node |
| Node hostname | `plex` |
| MetalLB pool | 192.168.100.100–150 |
| Traefik ingress | 192.168.100.102 |
| Storage | local-path provisioner |

## Key Patterns

### MetalLB Annotations

```yaml
metadata:
  annotations:
    metallb.universe.tf/loadBalancerIPs: 192.168.100.X  # correct — in metadata
spec:
  type: LoadBalancer
  # NOT in spec
```

### Image Versions

Always pin versions, never `:latest` (rejected by pre-commit hook).

### Security Contexts

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: <uid>
  fsGroup: <gid>
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

### Node Affinity / PV Issues

If hostname changes:
```bash
kubectl label node <node-name> kubernetes.io/hostname=<new-hostname> --overwrite
```

## Commit Style

Lowercase imperative, no period:

```
fix null deref in session teardown
add retry logic with exponential backoff
bump unifi to 10.1.85
```

## Troubleshooting

### App Stuck OutOfSync

```bash
kubectl get application <app> -n argocd -o jsonpath='{.status.sync.status}'
kubectl get application <app> -n argocd -o jsonpath='{.status.operationState.message}'
kubectl patch application <app> -n argocd --type merge \
  -p '{"operation":{"sync":{"prune":true,"syncStrategy":{"apply":{"force":true}}}}}'
```

### Pod Stuck Pending

Common causes:
- PVC node affinity mismatch — check PV nodeAffinity
- Kyverno policy violation — `kubectl describe pod <pod>`
- Resource constraints — check node capacity

### Kyverno Violations

```bash
kubectl get policyreport -A
```

## Bootstrap

```bash
./scripts/bootstrap-cluster.sh
```

Installs ArgoCD, deploys root Application, waits for sync, deploys security tooling.
