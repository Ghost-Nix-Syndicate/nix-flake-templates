{ kx, namespace, pkgs, ... }:
kx.helm.release {
  name = "grafana";
  chart = "grafana";
  repository = "https://grafana.github.io/helm-charts";
  namespace = namespace;
  values = {
    adminPassword = "admin";
    persistence.enabled = false;
    service.type = "NodePort";
    service.nodePort = 30000;
    dashboardsProvider.enabled = true;
    dashboards = {
      "tempo-overview.json" = builtins.readFile ./dashboards/tempo-overview.json;
    };
    datasources."datasources.yaml" = {
      apiVersion = 1;
      datasources = [
        { name = "Prometheus"; type = "prometheus"; url = "http://prometheus-server"; }
        { name = "Loki"; type = "loki"; url = "http://loki:3100"; }
        { name = "Tempo"; type = "tempo"; url = "http://tempo:3200"; }
      ];
    };
  };
}
