{
  description = "Full observability stack (OTEL + Jaeger + Prometheus + Grafana) for k3s";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    kubenix.url = "github:hall/kubenix";
  };

  outputs = { self, nixpkgs, flake-utils, kubenix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        kx = kubenix;

        # K8s manifests
        collectorConfig = ./collector-config.yaml;
        k8s = {
          otelCollector = kx.deployment { ... };
          jaeger = kx.deployment { ... };
          prometheus = kx.deployment { ... };
          grafana = kx.deployment { ... };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.k3s pkgs.kubectl pkgs.helm pkgs.curl ];

          shellHook = ''
            export KUBECONFIG=/tmp/k3s.yaml
            if ! pgrep -x k3s >/dev/null; then
              echo "🚀 Starting k3s..."
              sudo k3s server --write-kubeconfig=$KUBECONFIG &
              sleep 5
            fi
            echo "📡 Dev k3s cluster ready"
          '';
        };

        k8s = k8s;

        defaultApp = pkgs.writeShellScriptBin "deploy" ''
          echo "📦 Deploying observability stack..."
          ${kubenix.kubectl} apply -f <(kubenix.writeYaml ${k8s.otelCollector})
          ${kubenix.kubectl} apply -f <(kubenix.writeYaml ${k8s.jaeger})
          ${kubenix.kubectl} apply -f <(kubenix.writeYaml ${k8s.prometheus})
          ${kubenix.kubectl} apply -f <(kubenix.writeYaml ${k8s.grafana})
          echo "✅ Stack deployed"
        '';

        destroyApp = pkgs.writeShellScriptBin "destroy" ''
          echo "🧹 Destroying observability stack..."
          ${kubenix.kubectl} delete deployment otel-collector || true
          ${kubenix.kubectl} delete deployment jaeger-all-in-one || true
          ${kubenix.kubectl} delete deployment prometheus || true
          ${kubenix.kubectl} delete deployment grafana || true
          echo "✅ Stack destroyed"
        '';
      }
    );
}
