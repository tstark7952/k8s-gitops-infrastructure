# Security Policy

## Reporting Security Issues

**DO NOT** create public GitHub issues for security vulnerabilities.

Instead, please report security issues to: security@yourdomain.com

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will respond within 48 hours.

## Security Principles

### Defense in Depth
We implement multiple layers of security controls:

1. **Pre-commit**: Local validation and secret scanning
2. **CI/CD**: Comprehensive security scanning and policy enforcement
3. **Admission Control**: Runtime policy validation (Kyverno)
4. **Runtime**: Threat detection and monitoring (Falco)

### Zero Trust
- All changes must be verified and signed
- No implicit trust based on network location
- Continuous authentication and authorization
- Least privilege access at all layers

### Shift-Left Security
- Security is integrated from the beginning
- Issues are caught in development, not production
- Automated security gates prevent insecure deployments

## Security Controls

### 1. Git Security

#### Required: Signed Commits
All commits MUST be signed with GPG or SSH keys.

**Setup GPG Signing:**
```bash
# Generate GPG key
gpg --full-generate-key

# Configure Git
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true

# Verify
git log --show-signature
```

#### Required: Branch Protection
- `main` branch is protected
- Requires pull request reviews (minimum 2 approvers)
- Status checks must pass before merge
- Force push disabled
- Deletion disabled

### 2. Secret Management

#### Never Commit Secrets
- Use External Secrets Operator
- Reference secrets from HashiCorp Vault or cloud providers
- Secrets in Git will trigger automated revocation

#### Secret Scanning
- Pre-commit hooks scan for secrets
- CI/CD pipeline scans with TruffleHog and Gitleaks
- Baseline maintained in `.secrets.baseline`

#### Rotating Secrets
- All secrets must be rotatable
- Maximum secret lifetime: 90 days
- Automated rotation for supported systems

### 3. Container Security

#### Image Requirements
- ✅ Must use specific version tags (no `:latest`)
- ✅ Prefer SHA256 digests over tags
- ✅ Images must be from approved registries
- ✅ Images must be signed (Cosign)
- ✅ Must pass vulnerability scanning (Trivy)

#### Registry Allowlist
Approved registries:
- `docker.io` (for official images only)
- `ghcr.io`
- `registry.k8s.io`
- `gcr.io`
- `quay.io`
- Your private registry

#### Vulnerability Thresholds
- **CRITICAL**: ❌ Blocked - Must fix before deployment
- **HIGH**: ⚠️  Requires justification and tracking
- **MEDIUM**: ℹ️  Tracked, fix within 30 days
- **LOW**: ℹ️  Informational

### 4. Pod Security Standards

All application namespaces enforce **Baseline** profile minimum.

Production workloads should use **Restricted** profile:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10000
    fsGroup: 10000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: app:1.0@sha256:...
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
    resources:
      limits:
        memory: "256Mi"
        cpu: "500m"
      requests:
        memory: "128Mi"
        cpu: "250m"
```

### 5. Network Security

#### Default Deny
All namespaces (except system) must have default-deny network policies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

#### Explicit Allow
Only explicitly allowed traffic should be permitted.

#### Service Mesh
Consider implementing Istio or Linkerd for mTLS between services.

### 6. RBAC (Role-Based Access Control)

#### Principles
- **Least Privilege**: Grant minimum permissions necessary
- **Separation of Duties**: No single user has full control
- **Time-Bound Access**: Temporary elevated access when needed
- **Regular Audits**: Quarterly RBAC reviews

#### Forbidden Patterns
❌ Wildcard verbs: `verbs: ["*"]`
❌ Wildcard resources: `resources: ["*"]`
❌ Wildcard API groups: `apiGroups: ["*"]`
❌ cluster-admin bindings (except break-glass)

### 7. Audit Logging

#### Required Logging
- All API server requests
- Authentication attempts
- RBAC authorization decisions
- Admission webhook decisions
- Changes to RBAC policies
- Secret access

#### Retention
- Logs retained for 90 days minimum
- Security-relevant logs: 1 year
- Compliance logs: As required by policy

### 8. Incident Response

#### Severity Levels

**Critical (P0)**: Active exploitation, data breach, cluster compromise
- Response time: Immediate
- Notification: Security team + management
- Communication: Hourly updates

**High (P1)**: Vulnerable to exploitation, privilege escalation possible
- Response time: 4 hours
- Notification: Security team
- Communication: Daily updates

**Medium (P2)**: Security weakness, no immediate exploitation
- Response time: 24 hours
- Notification: Security team
- Communication: Weekly updates

**Low (P3)**: Security improvement opportunity
- Response time: 1 week
- Notification: Team lead
- Communication: Tracked in backlog

#### Incident Response Procedure

1. **Detect**: Automated alerts (Falco, Trivy, Kyverno)
2. **Triage**: Assess severity and impact
3. **Contain**: Isolate affected resources
4. **Eradicate**: Remove threat and patch vulnerability
5. **Recover**: Restore normal operations
6. **Lessons Learned**: Post-incident review

#### Break-Glass Procedure

For emergency access:
1. Create break-glass PR with justification
2. Get approval from 2 security team members
3. Merge and deploy
4. Create incident ticket
5. Conduct post-incident review within 48 hours
6. Revert break-glass changes

### 9. Compliance

#### CIS Kubernetes Benchmark
- Automated weekly scans via kube-bench
- Non-compliance findings tracked and remediated
- Compliance reports generated monthly

#### NIST 800-190
Container security framework compliance:
- Image lifecycle security
- Registry security
- Orchestrator security
- Container runtime security
- Host OS security

#### SOC 2 / ISO 27001
Security controls mapped to frameworks:
- Access control
- Change management
- Incident response
- Logging and monitoring

### 10. Supply Chain Security (SLSA)

Target: **SLSA Level 3**

Requirements:
- ✅ Build from source in isolated environment
- ✅ Signed provenance
- ✅ Non-falsifiable provenance
- ✅ Dependency verification
- ✅ SBOM generation

#### Provenance Attestation
All artifacts must include:
- Build system identity
- Source repository and commit
- Build parameters
- Dependencies with hashes
- Digital signature

## Security Training

All contributors must complete:
- Secure coding practices
- Kubernetes security fundamentals
- Secret management
- Incident response procedures

Annual refresher required.

## Third-Party Dependencies

### Dependency Management
- All dependencies pinned to specific versions
- SCA scanning on all dependencies
- Automated PR for security updates
- Review and update dependencies quarterly

### Vendor Assessment
Third-party services must pass security review:
- SOC 2 Type II compliance
- Data handling practices
- Incident response capabilities
- SLA commitments

## Contact

Security Team: security@yourdomain.com
PGP Key: [Link to public key]

## Acknowledgments

We appreciate responsible disclosure. Contributors to our security will be acknowledged (with permission) in our security hall of fame.
