# ckan-cloud monitoring

## Kubernetes cluster monitoring

Rancher > Global > Catalogs > Enable Helm Stable catalog

Rancher > ckan-cloud > system > catalog apps > launch > prometheus-operator

Get the Grafana user/password:

```
kubectl -n monitoring get secret kube-prometheus-grafana -o yaml
```

