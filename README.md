# K8s GitOps Infrastructure - DevSecOps Pipeline

**Security-First GitOps Management for Kubernetes Cluster**

This repository manages your K3s cluster using GitOps principles with security controls at every layer.

## 🎯 Security Principles

- **Shift-Left Security**: Issues caught in development, not production
- **Defense in Depth**: Multiple security layers (pre-commit → CI/CD → admission control → runtime)
- **Zero Trust**: All changes verified, signed, and audited
- **Supply Chain Security**: SLSA Level 3 compliance
- **Continuous Compliance**: Automated CIS benchmark validation

## 📁 Repository Structure

```
k8s-gitops-infrastructure/
├── .github/
│   ├── workflows/
│   │   ├── security-scan.yml          # Multi-tool security scanning
│   │   ├── validate-deploy.yml        # Validation and deployment
│   │   └── compliance-audit.yml       # CIS benchmark checks
│   └── CODEOWNERS                      # Required reviewers
│
├── clusters/
│   └── plex-r620/                     # Cluster-specific configs
│       ├── argocd/                     # ArgoCD installation
│       ├── security/                   # Security tooling
│       │   ├── kyverno/
│       │   ├── falco/
│       │   ├── trivy-operator/
│       │   └── external-secrets/
│       ├── networking/                 # Network policies
│       ├── monitoring/                 # Observability stack
│       └── applications/               # Application workloads
│           ├── unifi/
│           ├── step-ca/
│           └── cert-manager/
│
├── base/                               # Reusable base manifests
│   ├── security-policies/
│   ├── network-policies/
│   └── rbac/
│
├── scripts/
│   ├── bootstrap-cluster.sh           # Initial cluster setup
│   ├── pre-commit-checks.sh           # Local validation
│   └── generate-sbom.sh               # SBOM generation
│
├── policies/
│   ├── kyverno/                        # Kyverno ClusterPolicies
│   ├── opa/                            # OPA Rego policies
│   └── network-policies/               # Default network policies
│
├── .pre-commit-config.yaml            # Pre-commit hooks
├── .secrets.baseline                   # detect-secrets baseline
├── SECURITY.md                         # Security policy
└── README.md
```

## 🔒 Security Gates

### Stage 1: Pre-Commit (Developer Workstation)
- ✅ YAML/JSON syntax validation
- ✅ Secret scanning (detect-secrets)
- ✅ IaC security scanning (Trivy)
- ✅ Policy validation (Kyverno CLI)
- ✅ Kubernetes manifest validation (kubeval)

### Stage 2: CI/CD (GitHub Actions)
- ✅ Comprehensive IaC scanning (Trivy, Checkov, KICS)
- ✅ Secret scanning (TruffleHog, GitGuardian)
- ✅ Policy enforcement (Kyverno, OPA)
- ✅ RBAC validation
- ✅ Dry-run deployment testing
- ✅ SBOM generation
- ✅ Manifest signing

### Stage 3: Admission Control (Cluster)
- ✅ Kyverno policy enforcement
- ✅ Pod Security Standards
- ✅ Image signature verification
- ✅ Resource quotas and limits

### Stage 4: Runtime (Continuous)
- ✅ Falco runtime threat detection
- ✅ Trivy Operator vulnerability scanning
- ✅ Network policy enforcement
- ✅ Audit logging

## 🚀 Quick Start

### Prerequisites
```bash
# Install required tools
brew install argocd kubectl kustomize helm
brew install pre-commit trivy cosign
brew install kubeval kyverno
```

### 1. Bootstrap the Cluster

```bash
# Clone repository
git clone <your-repo-url>
cd k8s-gitops-infrastructure

# Install pre-commit hooks
pre-commit install

# Bootstrap ArgoCD and security tooling
./scripts/bootstrap-cluster.sh
```

### 2. Deploy Changes via GitOps

```bash
# Make changes to manifests
vim clusters/plex-r620/applications/unifi/deployment.yaml

# Pre-commit hooks run automatically
git add .
git commit -m "feat: update unifi deployment"

# Push triggers CI/CD pipeline
git push origin main
```

### 3. Monitor Deployment

```bash
# Watch ArgoCD sync
argocd app get unifi --watch

# Check Kyverno policy reports
kubectl get policyreport -A

# View Trivy vulnerability reports
kubectl get vulnerabilityreports -A

# Monitor Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

## 🔐 Security Workflow

### For All Changes:
1. **Create feature branch** from `main`
2. **Make changes** to manifests
3. **Pre-commit hooks validate** locally
4. **Push to GitHub** → triggers CI/CD
5. **Review security scan results** in PR
6. **Manual approval required** for production
7. **ArgoCD syncs** after merge to main
8. **Kyverno validates** at admission
9. **Falco monitors** at runtime

### Emergency Changes:
- Break-glass procedure documented in `SECURITY.md`
- All emergency changes require post-incident review
- Automated compliance reporting

## 📊 Compliance & Auditing

### CIS Kubernetes Benchmark
- Automated weekly scans via `kube-bench`
- Results published to security dashboard
- Non-compliance triggers alerts

### Audit Trail
- All Git commits signed with GPG
- GitHub Actions logs retained 90 days
- Kubernetes audit logs shipped to SIEM
- ArgoCD deployment history preserved

### Vulnerability Management
- Trivy scans all images on schedule
- CVEs prioritized using CVSS + EPSS + CISA KEV
- Automated PR creation for updates

## 🛠️ Tools & Technologies

| Category | Tool | Purpose |
|----------|------|---------|
| GitOps | ArgoCD | Continuous deployment |
| Policy | Kyverno | Admission control |
| Scanning | Trivy | Vulnerability & IaC scanning |
| Scanning | Checkov | Multi-cloud IaC analysis |
| Runtime | Falco | Threat detection |
| Secrets | External Secrets Operator | Secret management |
| Monitoring | Prometheus + Grafana | Observability |
| Compliance | kube-bench | CIS benchmarks |
| SBOM | Syft | Software bill of materials |
| Signing | Cosign | Image/manifest signing |

## 🎓 Best Practices

1. **Never commit directly to `main`** - Always use PRs
2. **All commits must be signed** - GPG or SSH signing required
3. **Two-person rule** - CODEOWNERS enforces reviews
4. **Least privilege** - RBAC follows principle of least privilege
5. **Secrets in Vault** - Never in Git, always external
6. **Immutable infrastructure** - Changes via Git, not kubectl
7. **Test in staging first** - Production changes require approval

## 📞 Support

- **Security Issues**: See `SECURITY.md`
- **Documentation**: `/docs` directory
- **Runbooks**: `/runbooks` directory

## 📜 License

Internal use only - Proprietary
# Test change
