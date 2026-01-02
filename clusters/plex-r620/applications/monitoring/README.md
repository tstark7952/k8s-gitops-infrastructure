# Monitoring Stack

Prometheus + Grafana monitoring stack for cluster observability.

## Components

- **Prometheus**: Metrics collection and time-series database
- **Grafana**: Visualization and dashboards
- **node-exporter**: Host/node metrics (CPU, memory, disk, network)
- **kube-state-metrics**: Kubernetes object state metrics

## Access

- **Grafana UI**: https://grafana.homelab.local (192.168.100.102)
- **Credentials**: admin/admin-change-me-in-production

## TLS Certificate Management

Grafana uses a manually generated certificate from Step-CA due to ACME HTTP-01 challenges not working with in-cluster Step-CA (hairpin NAT issue - Step-CA cannot reach MetalLB external IPs from inside the cluster).

### Certificate Details

- **Issuer**: R620 Homelab Intermediate CA
- **Validity**: 90 days
- **Current expiry**: Check with `kubectl get secret grafana-tls -n monitoring -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate`

### Certificate Renewal Process

When the certificate needs renewal (30 days before expiry):

```bash
# 1. Generate new certificate from Step-CA
kubectl exec step-ca-0 -n step-ca -- step certificate create \
  grafana.homelab.local /tmp/grafana-new.crt /tmp/grafana-new.key \
  --profile leaf --not-after 2160h --kty RSA --size 2048 \
  --ca /home/step/certs/intermediate-ca.crt \
  --ca-key /home/step/secrets/intermediate-ca.key \
  --no-password --insecure

# 2. Copy certificates from pod
kubectl cp step-ca/step-ca-0:/tmp/grafana-new.crt /tmp/grafana.crt
kubectl cp step-ca/step-ca-0:/tmp/grafana-new.key /tmp/grafana.key
kubectl cp step-ca/step-ca-0:/home/step/certs/intermediate-ca.crt /tmp/intermediate-ca.crt

# 3. Create full chain
cat /tmp/grafana.crt /tmp/intermediate-ca.crt > /tmp/grafana-fullchain.crt

# 4. Delete old secret
kubectl delete secret grafana-tls -n monitoring

# 5. Create new secret
kubectl create secret tls grafana-tls -n monitoring \
  --cert=/tmp/grafana-fullchain.crt --key=/tmp/grafana.key

# 6. Restart Grafana to pick up new certificate
kubectl rollout restart deployment grafana -n monitoring

# 7. Cleanup
rm /tmp/grafana.crt /tmp/grafana.key /tmp/intermediate-ca.crt /tmp/grafana-fullchain.crt
kubectl exec step-ca-0 -n step-ca -- rm /tmp/grafana-new.crt /tmp/grafana-new.key
```

### Why Not Automated?

We attempted automated certificate management with cert-manager and the step-ca-acme ClusterIssuer, but encountered the following issue:

**Problem**: Step-CA runs inside the cluster and validates ACME HTTP-01 challenges by connecting to `grafana.homelab.local`. This hostname resolves to the MetalLB external IP (192.168.100.102), but pods inside the cluster cannot connect to MetalLB external IPs due to the "hairpin NAT" limitation.

**Error**: `Connection refused` when Step-CA tries to reach `http://grafana.homelab.local/.well-known/acme-challenge/<token>`

**Alternatives considered**:
- DNS-01 challenge: Requires DNS provider API integration (not configured)
- Hairpin mode: Requires complex network reconfiguration
- step-issuer: Previously attempted, had connectivity issues

**Decision**: Manual certificate management with documented renewal process provides reliable operation with minimal operational overhead (quarterly renewal).

## Dashboards

Recommended Grafana dashboards (import via UI):
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / Compute Resources / Node (Pods)
- Node Exporter Full

Note: Dashboards imported via Grafana UI are stored in the Grafana database and are NOT version-controlled in Git. For full GitOps management, export dashboards as JSON and add to ConfigMaps.

## Storage

- Prometheus: 20Gi PVC with 15-day retention
- Grafana: 10Gi PVC for dashboards and configuration

## Metrics Exporters

### node-exporter
- **Type**: DaemonSet (runs on all nodes)
- **Purpose**: Collects host-level metrics (CPU, memory, disk, network)
- **Port**: 9100
- **Security exception**: Requires `hostNetwork` and `hostPID` to access node metrics
- **PolicyException**: `node-exporter-exceptions` allows necessary host access

### kube-state-metrics
- **Type**: Deployment
- **Purpose**: Exposes Kubernetes object state as metrics
- **Port**: 8080 (metrics), 8081 (telemetry)
- **RBAC**: ClusterRole with read access to cluster resources

Both exporters are automatically discovered by Prometheus via `prometheus.io/scrape: "true"` annotations.
