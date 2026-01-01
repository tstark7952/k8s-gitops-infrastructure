# Quick Start Guide

Get your GitOps DevSecOps pipeline running in 30 minutes.

## Prerequisites

```bash
# Install tools (macOS)
brew install argocd kubectl helm pre-commit trivy gpg
```

## Step 1: Fix Critical Security Issue (2 min)

```bash
# Fix kubeconfig permissions - CRITICAL!
chmod 600 ~/.kube/config
```

## Step 2: Set Up Git Signing (5 min)

```bash
# Generate GPG key
gpg --full-generate-key

# Configure Git
git config --global user.signingkey $(gpg --list-secret-keys --keyid-format=long | grep sec | awk '{print $2}' | cut -d'/' -f2)
git config --global commit.gpgsign true

# Export public key and add to GitHub
gpg --armor --export YOUR_EMAIL
# Copy output → GitHub Settings → SSH and GPG keys → New GPG key
```

## Step 3: Clone and Configure Repository (3 min)

```bash
# Clone
git clone https://github.com/your-org/k8s-gitops-infrastructure.git
cd k8s-gitops-infrastructure

# Install pre-commit hooks
pre-commit install

# Update repository URLs (replace YOUR_ORG)
find . -name "*.yaml" -type f -exec \
  sed -i '' 's/your-org/YOUR_ORG/g' {} \;

git add .
git commit -s -m "chore: configure repository"
git push
```

## Step 4: Bootstrap Cluster (10 min)

```bash
# Run bootstrap script
./scripts/bootstrap-cluster.sh

# Wait for all pods to be ready
kubectl get pods --all-namespaces -w
```

## Step 5: Access ArgoCD (2 min)

```bash
# Get password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo ""

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Open browser
open https://localhost:8080
# Login: admin / (password from above)
```

## Step 6: Configure GitHub (5 min)

### Add Secrets

```bash
# Get kubeconfig
cat ~/.kube/config | base64 | pbcopy
```

Go to: `Settings → Secrets → Actions → New`

Add:
- Name: `KUBECONFIG_DATA`
- Value: (paste from clipboard)

### Enable Branch Protection

Go to: `Settings → Branches → Add rule` for `main`

Required:
- ✅ Require PR reviews (2)
- ✅ Require status checks
- ✅ Require signed commits
- ✅ Restrict force push

## Step 7: Deploy Your First App (3 min)

```bash
# Apply ArgoCD application
kubectl apply -f clusters/plex-r620/argocd/argocd-app-unifi.yaml

# Watch sync
argocd app list
argocd app sync unifi
```

## Verification Checklist

```bash
# ✅ Security tools running
kubectl get pods -n kyverno
kubectl get pods -n falco
kubectl get pods -n trivy-system

# ✅ Policies active
kubectl get clusterpolicy

# ✅ Network policies
kubectl get networkpolicies --all-namespaces

# ✅ Vulnerability scanning
kubectl get vulnerabilityreports --all-namespaces

# ✅ ArgoCD applications
argocd app list
```

## What You Just Built

🎉 **Congratulations!** You now have:

### Security Gates

| Stage | Tools | Purpose |
|-------|-------|---------|
| **Pre-commit** | detect-secrets, trivy, yamllint | Catch issues before commit |
| **CI/CD** | Trivy, Checkov, TruffleHog, Kyverno | Automated security scanning |
| **Admission** | Kyverno, Pod Security | Block insecure deployments |
| **Runtime** | Falco, Trivy Operator | Continuous monitoring |

### Compliance

- ✅ CIS Kubernetes Benchmark baseline
- ✅ OWASP Kubernetes Top 10 controls
- ✅ NIST 800-190 container security
- ✅ Pod Security Standards enforced
- ✅ Network segmentation (default deny)
- ✅ SLSA Level 2 supply chain security

### GitOps Workflow

```
┌─────────────┐
│  Developer  │
└──────┬──────┘
       │ git commit (signed)
       ▼
┌─────────────────────┐
│  Pre-commit Hooks   │  ← Secret scan, YAML lint, Trivy
└──────┬──────────────┘
       │ git push
       ▼
┌─────────────────────┐
│  GitHub Actions     │  ← Full security pipeline
└──────┬──────────────┘
       │ merge to main
       ▼
┌─────────────────────┐
│  ArgoCD Sync        │  ← GitOps deployment
└──────┬──────────────┘
       │ apply
       ▼
┌─────────────────────┐
│  Kyverno Admission  │  ← Policy enforcement
└──────┬──────────────┘
       │ allowed
       ▼
┌─────────────────────┐
│  K8s Cluster        │
└──────┬──────────────┘
       │ runtime
       ▼
┌─────────────────────┐
│  Falco Monitoring   │  ← Threat detection
└─────────────────────┘
```

## Next Steps

1. **Migrate Workloads**: See `IMPLEMENTATION-GUIDE.md` Phase 5
2. **Enable Enforcement**: Change Kyverno policies from `audit` to `enforce`
3. **Configure Monitoring**: Deploy Prometheus + Grafana
4. **Set Up Alerts**: Configure Slack/email notifications
5. **Team Training**: Share `SECURITY.md` with team

## Common Commands

```bash
# View ArgoCD apps
argocd app list

# Sync app
argocd app sync APP_NAME

# Check policies
kubectl get clusterpolicy
kubectl get policyreport -A

# View Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Check vulnerabilities
kubectl get vulnerabilityreports -A

# Run security tests
pre-commit run --all-files
```

## Troubleshooting

### Pre-commit fails?
```bash
# Update hooks
pre-commit autoupdate

# Skip specific hook (debug only)
SKIP=trivy-scan git commit -m "message"
```

### ArgoCD won't sync?
```bash
# Check status
argocd app get APP_NAME

# Force sync
argocd app sync APP_NAME --force
```

### Policy blocks deployment?
```bash
# Check reports
kubectl get policyreport -n NAMESPACE -o yaml

# Temporarily audit (fix then re-enable)
kubectl patch clusterpolicy POLICY_NAME \
  -p '{"spec":{"validationFailureAction":"audit"}}' --type=merge
```

## Support

- 📖 Full docs: `IMPLEMENTATION-GUIDE.md`
- 🔒 Security: `SECURITY.md`
- 💬 Questions: Create GitHub issue
- 🚨 Security issues: security@yourdomain.com

---

**You're ready to go! 🚀**

Every change now flows through automated security checks, requires peer review, and is continuously monitored at runtime.
