#!/bin/bash
# Bootstrap Script for GitOps Kubernetes Cluster
# This script sets up ArgoCD and core security tooling

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  K8s GitOps DevSecOps Bootstrap${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# ==============================================================================
# Pre-flight Checks
# ==============================================================================
echo -e "${YELLOW}Running pre-flight checks...${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found - please install kubectl${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Cluster connectivity verified${NC}"

# Check if this is K3s
if kubectl get nodes -o json | jq -r '.items[0].status.nodeInfo.containerRuntimeVersion' | grep -q "k3s"; then
    echo -e "${GREEN}✅ K3s cluster detected${NC}"
    K3S_CLUSTER=true
fi

# ==============================================================================
# Install ArgoCD
# ==============================================================================
echo ""
echo -e "${BLUE}[1/7] Installing ArgoCD...${NC}"

# Create argocd namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD (with security hardening)
kubectl apply -n argocd -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  # Enforce TLS
  server.insecure: "false"
  # SSO configuration (configure based on your identity provider)
  # url: https://argocd.yourdomain.com
  # Enable RBAC
  policy.default: role:readonly
  # Audit logging
  server.log.level: "info"
  server.log.format: "json"
EOF

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo -e "${YELLOW}Waiting for ArgoCD to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

echo -e "${GREEN}✅ ArgoCD installed${NC}"

# ==============================================================================
# Install Kyverno (Policy Engine)
# ==============================================================================
echo ""
echo -e "${BLUE}[2/7] Installing Kyverno...${NC}"

kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo update

helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=1 \
  --set resources.limits.memory=512Mi \
  --set resources.requests.memory=256Mi \
  --wait

echo -e "${GREEN}✅ Kyverno installed${NC}"

# ==============================================================================
# Install Falco (Runtime Security)
# ==============================================================================
echo ""
echo -e "${BLUE}[3/7] Installing Falco...${NC}"

kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -

helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo update

helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set tty=true \
  --set ebpf.enabled=true \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true \
  --wait

echo -e "${GREEN}✅ Falco installed${NC}"

# ==============================================================================
# Install Trivy Operator (Vulnerability Scanning)
# ==============================================================================
echo ""
echo -e "${BLUE}[4/7] Installing Trivy Operator...${NC}"

kubectl create namespace trivy-system --dry-run=client -o yaml | kubectl apply -f -

helm repo add aqua https://aquasecurity.github.io/helm-charts/ 2>/dev/null || true
helm repo update

helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set="trivy.ignoreUnfixed=true" \
  --set="operator.scanJobTimeout=10m" \
  --wait

echo -e "${GREEN}✅ Trivy Operator installed${NC}"

# ==============================================================================
# Install External Secrets Operator
# ==============================================================================
echo ""
echo -e "${BLUE}[5/7] Installing External Secrets Operator...${NC}"

kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --wait

echo -e "${GREEN}✅ External Secrets Operator installed${NC}"

# ==============================================================================
# Apply Baseline Security Policies
# ==============================================================================
echo ""
echo -e "${BLUE}[6/7] Applying baseline security policies...${NC}"

# Create baseline Kyverno policies
kubectl apply -f - <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
  annotations:
    policies.kyverno.io/title: Disallow Latest Tag
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >-
      Disallow use of the 'latest' image tag to ensure reproducibility.
spec:
  validationFailureAction: audit
  background: true
  rules:
  - name: require-image-tag
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Using 'latest' tag is not allowed."
      pattern:
        spec:
          containers:
          - image: "!*:latest"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-non-root-user
  annotations:
    policies.kyverno.io/title: Require Non-Root User
    policies.kyverno.io/category: Pod Security Standards (Restricted)
    policies.kyverno.io/severity: high
spec:
  validationFailureAction: audit
  background: true
  rules:
  - name: check-runAsNonRoot
    match:
      any:
      - resources:
          kinds:
          - Pod
    exclude:
      any:
      - resources:
          namespaces:
          - kube-system
          - calico-system
          - tigera-operator
    validate:
      message: "Containers must run as non-root user."
      pattern:
        spec:
          securityContext:
            runAsNonRoot: true
          containers:
          - securityContext:
              runAsNonRoot: true
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
  annotations:
    policies.kyverno.io/title: Disallow Privileged Containers
    policies.kyverno.io/severity: high
spec:
  validationFailureAction: enforce
  background: true
  rules:
  - name: privileged-containers
    match:
      any:
      - resources:
          kinds:
          - Pod
    exclude:
      any:
      - resources:
          namespaces:
          - kube-system
          - calico-system
          - tigera-operator
          - falco
    validate:
      message: "Privileged containers are not allowed."
      pattern:
        spec:
          containers:
          - =(securityContext):
              =(privileged): false
EOF

echo -e "${GREEN}✅ Baseline policies applied${NC}"

# ==============================================================================
# Configure Pod Security Standards
# ==============================================================================
echo ""
echo -e "${BLUE}[7/7] Configuring Pod Security Standards...${NC}"

# Label namespaces with Pod Security Standards
for ns in default unifi step-ca cert-manager; do
    kubectl label namespace "$ns" \
      pod-security.kubernetes.io/enforce=baseline \
      pod-security.kubernetes.io/audit=restricted \
      pod-security.kubernetes.io/warn=restricted \
      --overwrite 2>/dev/null || echo "Namespace $ns doesn't exist yet"
done

echo -e "${GREEN}✅ Pod Security Standards configured${NC}"

# ==============================================================================
# Get ArgoCD Initial Admin Password
# ==============================================================================
echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${GREEN}✅ Bootstrap Complete!${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""
echo -e "${YELLOW}ArgoCD Initial Setup:${NC}"
echo ""
echo "1. Get admin password:"
echo -e "   ${GREEN}kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d${NC}"
echo ""
echo "2. Port-forward ArgoCD UI:"
echo -e "   ${GREEN}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
echo ""
echo "3. Access ArgoCD:"
echo -e "   ${GREEN}https://localhost:8080${NC}"
echo "   Username: admin"
echo "   Password: (from step 1)"
echo ""
echo -e "${YELLOW}Security Tooling Access:${NC}"
echo ""
echo "• Falco UI:"
echo -e "  ${GREEN}kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802${NC}"
echo -e "  http://localhost:2802"
echo ""
echo "• Trivy Vulnerability Reports:"
echo -e "  ${GREEN}kubectl get vulnerabilityreports --all-namespaces${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Change ArgoCD admin password"
echo "2. Configure SSO (OIDC/SAML)"
echo "3. Deploy ArgoCD applications from Git"
echo "4. Review Kyverno policy reports:"
echo -e "   ${GREEN}kubectl get policyreport --all-namespaces${NC}"
echo "5. Set up Git commit signing:"
echo -e "   ${GREEN}git config --global commit.gpgsign true${NC}"
echo ""
