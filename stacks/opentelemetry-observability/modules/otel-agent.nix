{ kx, namespace, ... }:
kx.helm.release {
  name = "otel-agent";
  chart = "opentelemetry-collector";
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts";
  namespace = namespace;
  values = {
    mode = "daemonset";
    config = {
      receivers.hostmetrics.collection_interval = "30s";
      exporters.otlp.endpoint = "otel-collector:4317";
      service.pipelines.metrics = {
        receivers = [ "hostmetrics" ];
        exporters = [ "otlp" ];
      };
    };
  };
}
