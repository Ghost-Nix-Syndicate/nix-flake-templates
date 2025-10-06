{
  description = "Modular Nix-based OpenTelemetry Observability Stack for k3d";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    kubenix.url = "github:hall/kubenix";
  };

  outputs = { self, nixpkgs, flake-utils, kubenix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        kx = kubenix.lib { inherit pkgs; };

        namespace = "observability";

        # Import all module definitions
        grafana = import ./modules/grafana.nix { inherit kx namespace pkgs; };
        prometheus = import ./modules/prometheus.nix { inherit kx namespace; };
        loki = import ./modules/loki.nix { inherit kx namespace; };
        tempo = import ./modules/tempo.nix { inherit kx namespace; };
        otelCollector = import ./modules/otel-collector.nix { inherit kx namespace; };
        otelAgent = import ./modules/otel-agent.nix { inherit kx namespace; };
        serviceMonitors = import ./modules/service-monitors.nix { inherit kx namespace; };

        manifests = kx.build.resources [
          grafana
          prometheus
          loki
          tempo
          otelCollector
          otelAgent
          serviceMonitors
        ];

        manifestsYaml = pkgs.writeText "observability.yaml"
          (builtins.toJSON manifests);
      in {
        packages.manifests = manifestsYaml;

        devShells.default = pkgs.mkShell {
          name = "observability-devshell";
          buildInputs = [
            pkgs.k3d
            pkgs.kubectl
            pkgs.helm
            pkgs.k9s
            pkgs.yq
            pkgs.opentelemetry-collector-contrib
          ];
          shellHook = ''
            echo "🚀 Use 'nix run .#deploy' to start the observability stack."
            echo "🧹 Use 'nix run .#destroy' to tear it down."
          '';
        };

        apps.deploy = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "deploy" ''
            set -e
            if ! k3d cluster list | grep -q observability; then
              echo "Creating k3d cluster..."
              k3d cluster create observability --servers 1 --agents 2 --port "30000:30000@loadbalancer"
            fi

            kubectl create namespace ${namespace} --dry-run=client -o yaml | kubectl apply -f -
            echo "📦 Deploying OpenTelemetry stack..."
            cat ${manifestsYaml} | yq -P | kubectl apply -f -
            echo "✅ Deployed! Grafana available at http://localhost:30000 (admin / admin)"
          '';
        };

        apps.destroy = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "destroy" ''
            set -e
            echo "🧹 Removing observability stack..."
            kubectl delete ns ${namespace} --ignore-not-found
            echo "💥 Deleting k3d cluster..."
            k3d cluster delete observability || true
          '';
        };
      });
}
