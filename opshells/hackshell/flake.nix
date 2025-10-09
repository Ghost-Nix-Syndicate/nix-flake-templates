
{
  description = "Next.js dev shell with full OpenTelemetry & Observability stack (Jaeger + OTEL + Grafana + Prometheus + Loki/Promtail + Dashboards)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        ##########################
        # Embedded OTEL config
        ##########################
        otelConfig = pkgs.writeText "otel-collector-config.yaml" ''
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: "0.0.0.0:4317"
                http:
                  endpoint: "0.0.0.0:4318"
                  cors:
                    allowed_origins: ["http://localhost:*", "http://127.0.0.1:*"]
                    allowed_headers: ["*"]
                    max_age: 7200
                    debug: true

          processors:
            batch:
              timeout: 5s
              send_batch_size: 512
            memory_limiter:
              check_interval: 1s
              limit_mib: 400
              spike_limit_mib: 100
            resource:
              attributes:
                - key: service.name
                  action: upsert
                  value: otel-collector

          exporters:
            jaeger:
              endpoint: http://jaeger:14268/api/traces
              tls:
                insecure: true
            prometheus:
              endpoint: 0.0.0.0:8889
              namespace: otel
              const_labels:
                environment: dev
            logging:
              loglevel: info

          service:
            telemetry:
              logs:
                level: info
            pipelines:
              traces:
                receivers: [otlp]
                processors: [memory_limiter, batch, resource]
                exporters: [jaeger, logging]
              metrics:
                receivers: [otlp]
                processors: [memory_limiter, batch]
                exporters: [prometheus, logging]
        '';

        ##########################
        # Promtail config
        ##########################
        promtailConfig = pkgs.writeText "promtail-config.yaml" ''
          server:
            http_listen_port: 9080
            grpc_listen_port: 0

          positions:
            filename: /tmp/positions.yaml

          clients:
            - url: http://loki:3100/loki/api/v1/push

          scrape_configs:
            - job_name: system
              static_configs:
                - targets: [localhost]
                  labels:
                    job: docker-logs
                    __path__: /var/lib/docker/containers/*/*.log
        '';

        ##########################
        # Grafana provisioning
        ##########################
        grafanaProvisioning = pkgs.runCommand "grafana-provisioning" {} ''
          mkdir -p $out/datasources
          cat > $out/datasources/datasources.yaml <<EOF
          apiVersion: 1
          datasources:
            - name: Prometheus
              type: prometheus
              access: proxy
              url: http://prometheus:9090
              isDefault: true
            - name: Loki
              type: loki
              access: proxy
              url: http://loki:3100
            - name: Jaeger
              type: jaeger
              access: proxy
              url: http://jaeger:16686
              traceApi: /api/traces
          EOF

          mkdir -p $out/dashboards
          cat > $out/dashboards/dashboards.yaml <<EOF
          apiVersion: 1
          providers:
            - name: 'default'
              type: file
              disableDeletion: false
              editable: true
              options:
                path: /var/lib/grafana/dashboards
          EOF
        '';

        ##########################
        # Docker run helper
        ##########################
        mkDockerRun = { name, image, ports ? [ ], volumes ? [ ], args ? [ ], network ? "observability" }:
          pkgs.writeShellScriptBin name ''
            if ! docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
              docker network create ${network} >/dev/null || true
            fi
            if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
              echo "🚀 Starting ${name} container (${image})..."
              docker rm -f ${name} >/dev/null 2>&1 || true
              docker run -d --name ${name} \
                --network ${network} \
                ${lib.concatStringsSep " " (map (p: "-p ${p}") ports)} \
                ${lib.concatStringsSep " " (map (v: "-v ${v}") volumes)} \
                ${image} ${lib.concatStringsSep " " args}
            else
              echo "✅ ${name} already running."
            fi
          '';

        ##########################
        # Containers
        ##########################
        runJaeger = mkDockerRun {
          name = "run-jaeger";
          image = "jaegertracing/all-in-one:1.56";
          ports = [ "16686:16686" "14268:14268" ];
        };

        runOtel = mkDockerRun {
          name = "run-otel";
          image = "otel/opentelemetry-collector-contrib:latest";
          volumes = [ "${otelConfig}:/etc/otel/config.yaml" ];
          ports = [ "43180:4318" "43170:4317" "8889:8889" ];
          args = [ "--config" "/etc/otel/config.yaml" ];
        };

        runGrafana = mkDockerRun {
          name = "run-grafana";
          image = "grafana/grafana:latest";
          ports = [ "3001:3000" ];
          volumes = [ "${grafanaProvisioning}:/etc/grafana/provisioning:ro" ];
        };

        runPrometheus = mkDockerRun {
          name = "run-prometheus";
          image = "prom/prometheus:latest";
          ports = [ "9090:9090" ];
        };

        runLoki = mkDockerRun {
          name = "run-loki";
          image = "grafana/loki:latest";
          ports = [ "3100:3100" ];
        };

        runPromtail = mkDockerRun {
          name = "run-promtail";
          image = "grafana/promtail:latest";
          volumes = [ "${promtailConfig}:/etc/promtail/promtail-config.yaml" "/var/lib/docker/containers:/var/lib/docker/containers:ro" ];
          args = [ "-config.file=/etc/promtail/promtail-config.yaml" ];
        };

      in {
        devShells.default = pkgs.mkShell {
          name = "nextjs-dev-env";

          packages = [
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.docker
            pkgs.nmap
            pkgs.metasploit
            pkgs.postgresql
            pkgs.ruby
            pkgs.netcat
            pkgs.neo4j
            pkgs.nats-server
            pkgs.tcpdump
            pkgs.wireshark-cli
            pkgs.git
            pkgs.python3
            pkgs.nushell
            pkgs.carapace
            pkgs.carapace-bridge
            pkgs.xdg-utils  # for xdg-open
            runJaeger
            runOtel
            runGrafana
            runPrometheus
            runLoki
            runPromtail
          ];

          shellHook = ''
            # ------------------------------
            # Observability Stack Commands
            # ------------------------------
            function obs-up() {
              echo "🔧 Starting full observability stack..."
              ${runJaeger}/bin/run-jaeger
              ${runOtel}/bin/run-otel
              ${runGrafana}/bin/run-grafana
              ${runPrometheus}/bin/run-prometheus
              ${runLoki}/bin/run-loki
              ${runPromtail}/bin/run-promtail
              echo "✅ Observability stack started!"
            }

            function obs-down() {
              echo "🛑 Stopping all observability containers..."
              docker rm -f run-jaeger run-otel run-grafana run-prometheus run-loki run-promtail >/dev/null 2>&1 || true
              echo "✅ Observability stack stopped!"
            }

            # ------------------------------
            # Next.js + Storybook Commands
            # ------------------------------
            function app-install() {
              echo "📦 Installing dependencies with pnpm..."
              pnpm install
            }

            function app-dev() {
              echo "🚀 Starting Next.js dev server..."
              pnpm run dev
            }

            function app-storybook() {
              echo "📘 Starting Storybook on http://localhost:6006 ..."
              pnpm run storybook &
              STORYBOOK_PID=$!
              sleep 5
              xdg-open http://localhost:6006 >/dev/null 2>&1 || true
              wait $STORYBOOK_PID
            }

            # ------------------------------
            # Startup Info
            # ------------------------------
            echo "📦 Next.js Dev Environment with Full Observability Stack"
            echo "👉 Use 'obs-up' / 'obs-down' to manage observability stack"
            echo "👉 Use 'app-install' to install dependencies"
            echo "👉 Use 'app-dev' to run Next.js"
            echo "👉 Use 'app-storybook' to run Storybook (auto-opens browser)"
            echo ""
            echo "🌐 Jaeger UI:        http://localhost:16686"
            echo "🌐 Grafana UI:       http://localhost:3001"
            echo "🌐 Prometheus UI:    http://localhost:9090"
            echo "🌐 OTEL HTTP API:    http://localhost:43180"
            echo "🌐 OTEL gRPC:        grpc://localhost:43170"
            echo "🌐 Loki API:         http://localhost:3100"
            echo ""
            echo "💡 Grafana datasources and dashboards for OTEL, Prometheus, and Loki are auto-loaded."
            echo ""
            echo "Run your Next.js app with 'app-dev' after running 'app-install'."
          '';
        };
      });
}
