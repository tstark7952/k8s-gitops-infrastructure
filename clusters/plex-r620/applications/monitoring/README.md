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

TLS certificates are automatically managed by **cert-manager** using the ACME protocol with **Step-CA**.

### Configuration

- **ClusterIssuer**: `step-ca-acme-external` (configured to use HTTP-01 solver with Traefik)
- **Certificate**: Automatically created via `cert-manager.io/cluster-issuer` annotation on Ingress.
- **Renewal**: Automatic (30 days before expiry)

### Troubleshooting

If certificate renewal fails:
1. Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
2. Check Certificate resource status: `kubectl get certificate grafana-tls -n monitoring -o wide`
3. Check CertificateRequest and Order resources.



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
