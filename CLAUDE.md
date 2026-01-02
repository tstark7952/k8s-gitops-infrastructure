# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **production GitOps repository** managing a K3s Kubernetes cluster with security-first principles. All infrastructure is declarative and managed through ArgoCD. Changes to manifests in Git automatically sync to the cluster.

**Critical**: This repository manages **production workloads**. Always verify changes won't delete or break existing production services (e.g., Unifi Network Controller, Step-CA).

## GitOps Architecture

### App-of-Apps Pattern
The repository uses ArgoCD's "App-of-Apps" pattern:

```
root Application (clusters/plex-r620/argocd/root-app.yaml)
  ├── Watches: clusters/plex-r620/**
  ├── Auto-syncs: true (selfHeal enabled)
  └── Manages all child Applications
```

**Key files:**
- `clusters/plex-r620/argocd/root-app.yaml` - Root application that watches entire cluster directory
- `clusters/plex-r620/argocd/argocd-app-*.yaml` - Individual application definitions (e.g., `argocd-app-unifi.yaml`)

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
1. **Always read existing manifests first** before modifying production apps
2. Edit YAML files in Git
3. Pre-commit hooks validate automatically
4. Commit and push to GitHub
5. ArgoCD auto-syncs changes to cluster (via selfHeal)

### Checking Sync Status
```bash
# View all applications
kubectl get applications -n argocd

# Check specific app
kubectl get application <app-name> -n argocd

# Watch sync progress
kubectl get application <app-name> -n argocd -w

# Trigger manual sync (if needed)
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

**Install**: `pre-commit install`
**Run manually**: `pre-commit run --all-files`

### Kyverno Policies (Admission Control)
Located in `clusters/plex-r620/security/kyverno/`:
- `pod-security-baseline.yaml` - PSS baseline controls
- `disallow-latest-tag.yaml` - Require specific image versions
- `require-non-root.yaml` - Enforce runAsNonRoot
- `require-readonly-rootfs.yaml` - Enforce read-only root filesystems
- `require-resource-limits.yaml` - Require CPU/memory limits

**Bypassing policies**: Create `PolicyException` resources (see `applications/unifi/policy-exceptions.yaml` example)

### Node Affinity Issues
PersistentVolumes use local-path provisioner with node affinity. If hostname changes:
```bash
# Add hostname label to node
kubectl label node <node-name> kubernetes.io/hostname=<new-hostname> --overwrite
```

## Production Applications

### Unifi Network Controller
**Location**: `clusters/plex-r620/applications/unifi/`
**Status**: PRODUCTION - manages network infrastructure
**Database**: MongoDB with persistent data in PVC `unifi-data`
**Access**: https://unifi.homelab.local (192.168.100.100:8443)

**Important**:
- Uses existing PVCs: `unifi-data`, `unifi-db`
- Requires Kyverno PolicyExceptions (runs as root, needs writable filesystem)
- Image version MUST match database version (currently 10.0.162)
- DO NOT delete PVCs or you'll lose production configuration

**Files**:
- `deployment.yaml` - Controller + MongoDB deployments
- `service.yaml` - LoadBalancer on MetalLB IP 192.168.100.100
- `ingress.yaml` - Traefik ingress with TLS
- `policy-exceptions.yaml` - Kyverno exceptions for Unifi's requirements
- `secret.yaml` - MongoDB credentials

### ArgoCD
**Access**: https://argo.homelab.local (192.168.100.103:8443)
**Credentials**: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`

### Certificate Management
- **Step-CA**: Internal CA issuing certificates
- **cert-manager**: Kubernetes certificate controller
- **Manual certs**: Some apps use manually generated certs from Step-CA (stored as TLS secrets)

**Certificate chain**: Leaf → R620 Homelab Intermediate CA → R620 Homelab Root CA

## Common Tasks

### Deploy New Application
1. Create directory: `clusters/plex-r620/applications/<app-name>/`
2. Add manifests: deployment, service, ingress, etc.
3. Create ArgoCD Application: `clusters/plex-r620/argocd/argocd-app-<app-name>.yaml`
4. Commit and push - ArgoCD auto-discovers via root app

### Update Application
1. Edit manifest in `clusters/plex-r620/applications/<app-name>/`
2. Commit and push
3. Monitor: `kubectl get application <app-name> -n argocd -w`

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
# Generate cert
kubectl exec -n step-ca step-ca-0 -- step certificate create \
  <hostname> /tmp/<name>.crt /tmp/<name>.key \
  --profile leaf --not-after 2160h --kty RSA --size 2048 \
  --ca /home/step/certs/intermediate-ca.crt \
  --ca-key /home/step/secrets/intermediate-ca.key \
  --no-password --insecure

# Copy from pod
kubectl cp step-ca/step-ca-0:/tmp/<name>.crt /tmp/<name>.crt
kubectl cp step-ca/step-ca-0:/tmp/<name>.key /tmp/<name>.key
kubectl cp step-ca/step-ca-0:/home/step/certs/intermediate-ca.crt /tmp/intermediate-ca.crt

# Create full chain
cat /tmp/<name>.crt /tmp/intermediate-ca.crt > /tmp/<name>-fullchain.crt

# Create secret
kubectl create secret tls <secret-name> -n <namespace> \
  --cert=/tmp/<name>-fullchain.crt --key=/tmp/<name>.key
```

### Add DNS Entry to CoreDNS
```bash
# Patch CoreDNS NodeHosts
kubectl patch configmap coredns -n kube-system --type merge \
  -p '{"data":{"NodeHosts":"<existing entries>\n192.168.100.X <hostname>\n"}}'

# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system
```

## Cluster Details

**Environment**: K3s on single node (plex)
**Node hostname**: `plex` (labeled as `kubernetes.io/hostname=plex`)
**MetalLB IP Pool**: 192.168.100.100-150
**Traefik Ingress**: 192.168.100.102
**Storage**: local-path provisioner (node-affinity locked)

## Important Patterns

### Service Annotations
MetalLB IP allocation belongs in `metadata.annotations`, NOT `spec.annotations`:
```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    metallb.universe.tf/loadBalancerIPs: 192.168.100.X  # CORRECT
spec:
  type: LoadBalancer
  # NOT here
```

### Image Versions
Always use specific versions, never `:latest`:
```yaml
image: lscr.io/linuxserver/unifi-network-application:10.0.162  # CORRECT
image: lscr.io/linuxserver/unifi-network-application:latest    # REJECTED by pre-commit
```

### Security Contexts
Most workloads require:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: <uid>
  fsGroup: <gid>
  readOnlyRootFilesystem: true  # When possible
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

If an app can't meet these, create a PolicyException.

## Troubleshooting

### Application Stuck "OutOfSync"
1. Check sync status: `kubectl get application <app> -n argocd -o jsonpath='{.status.sync.status}'`
2. View diff: `kubectl get application <app> -n argocd -o jsonpath='{.status.operationState.message}'`
3. Force sync: `kubectl patch application <app> -n argocd --type merge -p '{"operation":{"sync":{"prune":true,"syncStrategy":{"apply":{"force":true}}}}}'`

### Pod Stuck Pending
Common causes:
- PVC node affinity mismatch (check PV nodeAffinity)
- Kyverno policy violations (check events: `kubectl describe pod <pod>`)
- Resource constraints (check node resources)

### Kyverno Policy Violations
View violations: `kubectl get policyreport -A`
Create exception if legitimate: see PolicyException pattern above

## Git Workflow

### Commit Messages
Follow conventional commits:
```
feat: add new application
fix: correct service annotation placement
chore: update image version
docs: update CLAUDE.md
```

All commits include co-authorship footer (added by pre-commit):
```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

### Branch Protection
- Main branch requires push access
- Pre-commit hooks enforce quality
- Changes sync automatically via ArgoCD selfHeal

## External Dependencies

**GitHub Repository**: https://github.com/tstark7952/k8s-gitops-infrastructure.git
**ArgoCD watches**: `main` branch, path `clusters/plex-r620`

## Bootstrap Process

To bootstrap a new cluster:
```bash
./scripts/bootstrap-cluster.sh
```

This script:
1. Installs ArgoCD
2. Deploys root Application
3. Waits for ArgoCD to sync all apps
4. Deploys security tooling (Kyverno, Falco, Trivy)
