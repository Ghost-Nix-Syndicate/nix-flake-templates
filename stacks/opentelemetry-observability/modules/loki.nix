{ kx, namespace, ... }:
kx.helm.release {
  name = "loki";
  chart = "loki";
  repository = "https://grafana.github.io/helm-charts";
  namespace = namespace;
}
