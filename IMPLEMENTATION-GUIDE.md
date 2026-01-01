# GitOps DevSecOps Implementation Guide

This guide walks you through implementing the complete DevSecOps pipeline for your K3s cluster.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: Local Setup](#phase-1-local-setup)
3. [Phase 2: GitHub Repository Setup](#phase-2-github-repository-setup)
4. [Phase 3: Bootstrap Cluster](#phase-3-bootstrap-cluster)
5. [Phase 4: Configure ArgoCD](#phase-4-configure-argocd)
6. [Phase 5: Migrate Existing Workloads](#phase-5-migrate-existing-workloads)
7. [Phase 6: Enable Security Gates](#phase-6-enable-security-gates)
8. [Validation & Testing](#validation--testing)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

Install the following on your workstation:

```bash
# Package manager (macOS)
brew install argocd kubectl kustomize helm jq yq

# Pre-commit framework
brew install pre-commit

# Security tools
brew install trivy cosign syft

# Optional but recommended
brew install kubeval kyverno gpg
```

### Access Requirements

- ✅ Kubernetes cluster admin access
- ✅ GitHub account with repo creation permissions
- ✅ GPG key for commit signing
- ✅ kubectl configured to access your cluster

### Cluster Requirements

- ✅ Kubernetes 1.24+ (you have 1.28.5 ✓)
- ✅ CNI with NetworkPolicy support (you have Calico ✓)
- ✅ Storage provisioner (you have local-path ✓)
- ✅ LoadBalancer support (you have MetalLB ✓)

---

## Phase 1: Local Setup

### Step 1.1: Configure GPG Signing

```bash
# Generate GPG key (if you don't have one)
gpg --full-generate-key
# Choose: RSA and RSA, 4096 bits, no expiration
# Enter your name and email

# Get your key ID
gpg --list-secret-keys --keyid-format=long
# Copy the key ID (after 'rsa4096/')

# Configure Git
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true

# Export public key to GitHub
gpg --armor --export YOUR_KEY_ID
# Copy output and add to GitHub: Settings > SSH and GPG keys
```

### Step 1.2: Clone This Repository

```bash
# Clone the repository
git clone https://github.com/your-org/k8s-gitops-infrastructure.git
cd k8s-gitops-infrastructure

# Install pre-commit hooks
pre-commit install

# Test pre-commit hooks
pre-commit run --all-files
```

### Step 1.3: Configure Repository for Your Cluster

```bash
# Update ArgoCD application manifests with your Git repo URL
find clusters/plex-r620/argocd -name "*.yaml" -exec \
  sed -i '' 's|https://github.com/your-org/|https://github.com/YOUR_ORG/|g' {} \;

# Commit changes
git add .
git commit -s -m "chore: configure repository URLs"
git push origin main
```

---

## Phase 2: GitHub Repository Setup

### Step 2.1: Create Repository

```bash
# Create new private repository on GitHub
gh repo create k8s-gitops-infrastructure --private --source=. --remote=origin --push
```

### Step 2.2: Configure Branch Protection

Go to: `Settings > Branches > Add rule` for `main`:

- ✅ Require pull request reviews (2 approvers)
- ✅ Require status checks to pass
  - Select: `YAML Validation`, `Secret Scanning`, `IaC Security`
- ✅ Require signed commits
- ✅ Include administrators
- ✅ Restrict force pushes
- ✅ Restrict deletions

### Step 2.3: Configure GitHub Actions Secrets

Add these secrets: `Settings > Secrets and variables > Actions`

```bash
# Get kubeconfig (base64 encoded)
cat ~/.kube/config | base64

# Add to GitHub as KUBECONFIG_DATA
```

Required secrets:
- `KUBECONFIG_DATA`: Base64-encoded kubeconfig
- `ARGOCD_SERVER`: ArgoCD server URL (set after bootstrap)
- `ARGOCD_AUTH_TOKEN`: ArgoCD auth token (set after bootstrap)

Optional (for advanced features):
- `GITGUARDIAN_API_KEY`: For GitGuardian scanning
- `SLACK_WEBHOOK_URL`: For deployment notifications

### Step 2.4: Enable GitHub Security Features

1. Go to `Settings > Security > Code security and analysis`
2. Enable:
   - ✅ Dependency graph
   - ✅ Dependabot alerts
   - ✅ Dependabot security updates
   - ✅ Secret scanning
   - ✅ Push protection

---

## Phase 3: Bootstrap Cluster

### Step 3.1: Fix Immediate Security Issues

```bash
# CRITICAL: Fix kubeconfig permissions
chmod 600 ~/.kube/config

# Verify
ls -la ~/.kube/config
# Should show: -rw-------
```

### Step 3.2: Run Bootstrap Script

```bash
# Review the script first
cat scripts/bootstrap-cluster.sh

# Run bootstrap (takes ~10 minutes)
./scripts/bootstrap-cluster.sh
```

This installs:
- ✅ ArgoCD (GitOps controller)
- ✅ Kyverno (Policy engine)
- ✅ Falco (Runtime security)
- ✅ Trivy Operator (Vulnerability scanning)
- ✅ External Secrets Operator (Secret management)
- ✅ Baseline security policies

### Step 3.3: Verify Bootstrap

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Expected new namespaces:
# - argocd
# - kyverno
# - falco
# - trivy-system
# - external-secrets-system

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo ""

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access ArgoCD: `https://localhost:8080`
- Username: `admin`
- Password: (from command above)

---

## Phase 4: Configure ArgoCD

### Step 4.1: Change Admin Password

```bash
# Login via CLI
argocd login localhost:8080 --insecure

# Change password
argocd account update-password

# Or via UI: User Info > Update Password
```

### Step 4.2: Configure Git Repository

```bash
# Add Git repository to ArgoCD
argocd repo add https://github.com/your-org/k8s-gitops-infrastructure.git \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_GITHUB_TOKEN \
  --name k8s-gitops

# Verify
argocd repo list
```

### Step 4.3: Create ArgoCD Auth Token for CI/CD

```bash
# Create token
argocd account generate-token --account admin

# Add to GitHub Secrets as ARGOCD_AUTH_TOKEN
# Settings > Secrets > Actions > New repository secret
# Name: ARGOCD_AUTH_TOKEN
# Value: (token from above)
```

### Step 4.4: Deploy Applications

```bash
# Apply all ArgoCD applications
kubectl apply -f clusters/plex-r620/argocd/

# Watch sync status
argocd app list
argocd app sync --all
```

---

## Phase 5: Migrate Existing Workloads

### Step 5.1: Export Current Manifests

For each application (unifi, step-ca, cert-manager):

```bash
# Export unifi deployment
kubectl get deployment unifi-controller -n unifi -o yaml > \
  clusters/plex-r620/applications/unifi/deployment.yaml

kubectl get service -n unifi -o yaml > \
  clusters/plex-r620/applications/unifi/service.yaml

kubectl get configmap -n unifi -o yaml > \
  clusters/plex-r620/applications/unifi/configmap.yaml

# Note: Do NOT export secrets directly
# Migrate secrets to External Secrets Operator or Vault
```

### Step 5.2: Clean Up Exported Manifests

Remove auto-generated fields:

```bash
# Use yq to clean manifests
for file in clusters/plex-r620/applications/unifi/*.yaml; do
  yq eval 'del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid, .status)' -i "$file"
done
```

### Step 5.3: Add Security Context

Edit each deployment to add:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10000
    fsGroup: 10000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
```

### Step 5.4: Add Network Policies

Create `clusters/plex-r620/applications/unifi/network-policy.yaml`:

```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: unifi
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: unifi
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: unifi-ingress
  namespace: unifi
spec:
  podSelector:
    matchLabels:
      app: unifi-controller
  policyTypes:
  - Ingress
  ingress:
  - from: []  # Configure based on your requirements
    ports:
    - protocol: TCP
      port: 8443
    - protocol: TCP
      port: 8080
```

### Step 5.5: Commit and Deploy

```bash
# Add all manifests
git add clusters/plex-r620/applications/

# Pre-commit hooks will run automatically
git commit -s -m "feat: migrate unifi to GitOps management"

# Push to trigger CI/CD
git push origin main

# Watch ArgoCD sync
argocd app sync unifi
argocd app get unifi --refresh
```

---

## Phase 6: Enable Security Gates

### Step 6.1: Enable Policy Enforcement

Change Kyverno from `audit` to `enforce`:

```bash
# Update all policies to enforce mode
kubectl patch clusterpolicy disallow-latest-tag \
  -p '{"spec":{"validationFailureAction":"enforce"}}' --type=merge

kubectl patch clusterpolicy require-non-root-user \
  -p '{"spec":{"validationFailureAction":"enforce"}}' --type=merge

# Verify
kubectl get clusterpolicy
```

### Step 6.2: Enable Automated Scanning

The CI/CD pipeline is already configured. Verify:

```bash
# Push a test change
echo "# Test" >> README.md
git add README.md
git commit -s -m "test: verify CI/CD pipeline"
git push origin main

# Watch GitHub Actions
# https://github.com/your-org/k8s-gitops-infrastructure/actions
```

Expected to pass:
- ✅ YAML Validation
- ✅ Secret Scanning
- ✅ IaC Security Scan
- ✅ Policy Validation
- ✅ RBAC Validation
- ✅ Container Image Scan

### Step 6.3: Configure Production Approval

For the `validate-deploy` workflow:

1. Go to: `Settings > Environments`
2. Create environment: `production`
3. Add protection rules:
   - Required reviewers: 2 (select team members)
   - Wait timer: 0 minutes
4. Save

Now all deployments to `main` require manual approval.

---

## Validation & Testing

### Test 1: Secret Detection

```bash
# This should FAIL pre-commit
echo "password: mysecret123" >> test.yaml
git add test.yaml
git commit -m "test: secret detection"
# Expected: ❌ TruffleHog should block commit

# Clean up
git reset HEAD test.yaml
rm test.yaml
```

### Test 2: Policy Enforcement

```bash
# Create deployment with latest tag (should fail)
cat << EOF > test-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test
spec:
  template:
    spec:
      containers:
      - name: test
        image: nginx:latest
EOF

kubectl apply -f test-deploy.yaml -n default
# Expected: ❌ Kyverno blocks deployment

rm test-deploy.yaml
```

### Test 3: Network Policy

```bash
# Deploy test pod in unifi namespace
kubectl run test -n unifi --image=busybox --rm -it -- /bin/sh

# Inside pod, try external access
wget -O- https://google.com
# Expected: Should timeout (default deny egress)

# Try DNS
nslookup google.com
# Expected: Should work (DNS allowed)
```

### Test 4: Vulnerability Scanning

```bash
# Check Trivy reports
kubectl get vulnerabilityreports --all-namespaces

# View specific report
kubectl get vulnerabilityreports -n unifi -o yaml | less
```

### Test 5: Runtime Security

```bash
# View Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50

# Trigger test alert (spawn shell in container)
kubectl exec -n unifi deployment/unifi-controller -- /bin/sh
# Check Falco logs for alert
```

---

## Troubleshooting

### ArgoCD Application OutOfSync

```bash
# Check sync status
argocd app get APP_NAME

# Force sync
argocd app sync APP_NAME --force

# View sync errors
kubectl describe application APP_NAME -n argocd
```

### Kyverno Policy Violations

```bash
# View policy reports
kubectl get policyreport --all-namespaces

# View specific violations
kubectl get policyreport -n NAMESPACE -o yaml

# Temporarily disable policy (for debugging)
kubectl patch clusterpolicy POLICY_NAME \
  -p '{"spec":{"validationFailureAction":"audit"}}' --type=merge
```

### Container Fails Security Context

```bash
# Check pod events
kubectl describe pod POD_NAME -n NAMESPACE

# Common issues:
# 1. App writes to root filesystem
#    Solution: Add emptyDir volume mount
# 2. App runs as root
#    Solution: Update Dockerfile to use non-root user
# 3. App needs specific capabilities
#    Solution: Add minimum required capabilities
```

### Pre-commit Hooks Slow

```bash
# Skip hooks temporarily (NOT recommended for production)
git commit --no-verify -m "message"

# Or disable specific hooks
SKIP=trivy-scan git commit -m "message"
```

### CI/CD Pipeline Fails

Check GitHub Actions logs:
```bash
# Via CLI
gh run list
gh run view RUN_ID --log

# Or visit:
# https://github.com/your-org/k8s-gitops-infrastructure/actions
```

Common fixes:
- Update KUBECONFIG_DATA secret
- Verify ARGOCD_AUTH_TOKEN is valid
- Check if cluster is reachable from GitHub Actions

---

## Next Steps

1. **Configure SSO**: Set up OIDC/SAML for ArgoCD
2. **Set up Monitoring**: Deploy Prometheus + Grafana
3. **Configure Alerting**: Set up alerts for security events
4. **Implement Backup**: Set up Velero for cluster backups
5. **Documentation**: Document runbooks for common operations
6. **Training**: Train team on GitOps workflow

---

## Reference Documentation

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kyverno Policies](https://kyverno.io/policies/)
- [Falco Rules](https://falco.org/docs/rules/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Kubernetes Top 10](https://owasp.org/www-project-kubernetes-top-ten/)

---

## Support

For issues or questions:
- Create GitHub issue in this repository
- Contact: platform-team@yourdomain.com
- Security issues: security@yourdomain.com (see SECURITY.md)
