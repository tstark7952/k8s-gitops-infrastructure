#!/bin/bash
# Pre-commit security validation checks for Kubernetes manifests
# Usage: pre-commit-checks.sh <check-type> [files...]

set -e

CHECK_TYPE="$1"
shift
FILES="$@"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}❌ ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}✅${NC} $1"
}

# ==============================================================================
# Kyverno Policy Validation
# ==============================================================================
check_kyverno() {
    if ! command -v kyverno &> /dev/null; then
        warning "Kyverno CLI not installed - skipping policy validation"
        warning "Install: https://kyverno.io/docs/kyverno-cli/"
        return 0
    fi

    local errors=0
    for file in $FILES; do
        if [[ ! -f "$file" ]] || [[ ! "$file" =~ \.yaml$ ]]; then
            continue
        fi

        # Skip policy files themselves
        if [[ "$file" == *"/policies/"* ]]; then
            continue
        fi

        echo "Validating $file against Kyverno policies..."
        if ! kyverno apply policies/kyverno/ --resource "$file" --policy-report 2>&1; then
            error "Kyverno policy validation failed for $file"
            errors=$((errors + 1))
        fi
    done

    if [ $errors -gt 0 ]; then
        error "$errors file(s) failed Kyverno validation"
        return 1
    fi

    success "Kyverno policy validation passed"
    return 0
}

# ==============================================================================
# Container Image Tag Validation
# ==============================================================================
check_image_tags() {
    local errors=0
    for file in $FILES; do
        if [[ ! -f "$file" ]] || [[ ! "$file" =~ \.yaml$ ]]; then
            continue
        fi

        # Check for 'latest' tag
        if grep -q "image:.*:latest" "$file"; then
            error "Found 'latest' tag in $file - use specific version tags"
            errors=$((errors + 1))
        fi

        # Check for missing tags (image without :tag)
        if grep "image:" "$file" | grep -v "@sha256:" | grep -vq ":"; then
            warning "Image without version tag found in $file"
        fi

        # Prefer SHA digests over tags
        if grep "image:" "$file" | grep -vq "@sha256:"; then
            warning "Consider using SHA256 digests instead of tags in $file"
        fi
    done

    if [ $errors -gt 0 ]; then
        error "Image tag validation failed"
        return 1
    fi

    success "Image tag validation passed"
    return 0
}

# ==============================================================================
# Image Registry Validation
# ==============================================================================
check_registries() {
    local errors=0
    local allowed_registries=(
        "docker.io"
        "ghcr.io"
        "registry.k8s.io"
        "gcr.io"
        "quay.io"
        "your-private-registry.com"  # Add your registries here
    )

    for file in $FILES; do
        if [[ ! -f "$file" ]] || [[ ! "$file" =~ \.yaml$ ]]; then
            continue
        fi

        # Extract image names
        images=$(grep -o "image: [^[:space:]]*" "$file" | awk '{print $2}' | tr -d '"' || true)

        for image in $images; do
            # Extract registry from image
            registry=$(echo "$image" | cut -d'/' -f1)

            # Check if registry is allowed
            allowed=false
            for allowed_reg in "${allowed_registries[@]}"; do
                if [[ "$registry" == *"$allowed_reg"* ]] || [[ "$image" != *"/"* ]]; then
                    allowed=true
                    break
                fi
            done

            if [ "$allowed" = false ]; then
                error "Unauthorized registry in $file: $image"
                error "Allowed registries: ${allowed_registries[*]}"
                errors=$((errors + 1))
            fi
        done
    done

    if [ $errors -gt 0 ]; then
        return 1
    fi

    success "Registry validation passed"
    return 0
}

# ==============================================================================
# Security Context Validation
# ==============================================================================
check_security_context() {
    local errors=0
    for file in $FILES; do
        if [[ ! -f "$file" ]] || [[ ! "$file" =~ \.yaml$ ]]; then
            continue
        fi

        # Skip system namespaces
        if [[ "$file" == *"kube-system"* ]] || [[ "$file" == *"calico-system"* ]]; then
            continue
        fi

        # Check if deployment/pod has security context
        if grep -q "kind: Deployment\|kind: StatefulSet\|kind: DaemonSet\|kind: Pod" "$file"; then
            if ! grep -q "securityContext:" "$file"; then
                warning "No securityContext defined in $file"
            fi

            if ! grep -q "runAsNonRoot: true" "$file"; then
                warning "runAsNonRoot not set to true in $file"
            fi

            if ! grep -q "readOnlyRootFilesystem: true" "$file"; then
                warning "readOnlyRootFilesystem not set to true in $file"
            fi

            if ! grep -q "allowPrivilegeEscalation: false" "$file"; then
                warning "allowPrivilegeEscalation not set to false in $file"
            fi
        fi
    done

    success "Security context validation completed"
    return 0
}

# ==============================================================================
# Privileged Container Check
# ==============================================================================
check_privileged() {
    local errors=0
    for file in $FILES; do
        if [[ ! -f "$file" ]] || [[ ! "$file" =~ \.yaml$ ]]; then
            continue
        fi

        # Skip system namespaces
        if [[ "$file" == *"kube-system"* ]] || [[ "$file" == *"calico-system"* ]] || [[ "$file" == *"tigera-operator"* ]]; then
            continue
        fi

        if grep -q "privileged: true" "$file"; then
            error "Privileged container found in $file"
            error "Privileged containers should only be used in system namespaces"
            errors=$((errors + 1))
        fi

        if grep -q "hostPID: true\|hostNetwork: true\|hostIPC: true" "$file"; then
            error "Host namespace usage found in $file"
            errors=$((errors + 1))
        fi
    done

    if [ $errors -gt 0 ]; then
        return 1
    fi

    success "Privileged container check passed"
    return 0
}

# ==============================================================================
# RBAC Least Privilege Check
# ==============================================================================
check_rbac() {
    local errors=0
    for file in $FILES; do
        if [[ ! -f "$file" ]] || [[ ! "$file" =~ \.yaml$ ]]; then
            continue
        fi

        # Check for overly permissive RBAC
        if grep -q "kind: ClusterRole\|kind: Role" "$file"; then
            if grep -q 'apiGroups: \["\*"\]' "$file"; then
                warning "Wildcard API groups found in $file - consider limiting scope"
            fi

            if grep -q 'resources: \["\*"\]' "$file"; then
                warning "Wildcard resources found in $file - consider limiting scope"
            fi

            if grep -q 'verbs: \["\*"\]' "$file"; then
                error "Wildcard verbs found in $file - this is too permissive"
                errors=$((errors + 1))
            fi
        fi

        # Check for cluster-admin bindings
        if grep -q "roleRef:.*cluster-admin" "$file"; then
            error "cluster-admin role binding found in $file"
            error "This grants full cluster access - ensure this is absolutely necessary"
            errors=$((errors + 1))
        fi
    done

    if [ $errors -gt 0 ]; then
        return 1
    fi

    success "RBAC validation passed"
    return 0
}

# ==============================================================================
# Network Policy Check
# ==============================================================================
check_network_policies() {
    # Check if namespaces have network policies
    local namespaces=$(find clusters/ -type d -name "*" | grep -v "kube-system" | xargs -I {} basename {})

    for ns_dir in clusters/*/applications/*/; do
        ns_name=$(basename "$ns_dir")

        # Skip system namespaces
        if [[ "$ns_name" == "kube-system" ]] || [[ "$ns_name" == "kube-public" ]]; then
            continue
        fi

        # Check if network policy exists
        if [ -d "$ns_dir" ]; then
            if ! find "$ns_dir" -name "*network*.yaml" -o -name "*netpol*.yaml" | grep -q .; then
                warning "No network policy found for namespace: $ns_name"
                warning "Consider implementing default-deny network policies"
            fi
        fi
    done

    success "Network policy check completed"
    return 0
}

# ==============================================================================
# Commit Signing Check
# ==============================================================================
check_commit_signing() {
    # Check if GPG signing is enabled
    if ! git config --get commit.gpgsign | grep -q "true"; then
        error "Git commit signing is not enabled"
        error "Enable with: git config --global commit.gpgsign true"
        error "Generate GPG key: gpg --full-generate-key"
        return 1
    fi

    success "Commit signing is enabled"
    return 0
}

# ==============================================================================
# Main Execution
# ==============================================================================
case "$CHECK_TYPE" in
    kyverno)
        check_kyverno
        ;;
    image-tags)
        check_image_tags
        ;;
    registries)
        check_registries
        ;;
    security-context)
        check_security_context
        ;;
    privileged)
        check_privileged
        ;;
    rbac)
        check_rbac
        ;;
    network-policies)
        check_network_policies
        ;;
    commit-signing)
        check_commit_signing
        ;;
    *)
        error "Unknown check type: $CHECK_TYPE"
        echo "Available checks:"
        echo "  - kyverno"
        echo "  - image-tags"
        echo "  - registries"
        echo "  - security-context"
        echo "  - privileged"
        echo "  - rbac"
        echo "  - network-policies"
        echo "  - commit-signing"
        exit 1
        ;;
esac
