{ kx, namespace, ... }:
kx.helm.release {
  name = "tempo";
  chart = "tempo";
  repository = "https://grafana.github.io/helm-charts";
  namespace = namespace;
}
