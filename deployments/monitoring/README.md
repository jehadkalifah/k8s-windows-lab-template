# Monitoring — Stage 2 Component

Installs `kube-prometheus-stack 88.5.4`, including
Prometheus, Alertmanager, Grafana, kube-state-metrics and node-exporter.

Install:

```powershell
.\scripts\deploy.ps1 monitoring
```

Grafana:

```powershell
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Login: `admin / admin-lab`.

Prometheus:

```powershell
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```
