{ kx, namespace, ... }:
kx.k8s.api.v1.Service {
  metadata = {
    name = "otel-collector";
    namespace = namespace;
    labels.app = "otel-collector";
  };
  spec = {
    selector.app = "otel-collector";
    ports = [ { port = 8888; name = "metrics"; } ];
  };
}
