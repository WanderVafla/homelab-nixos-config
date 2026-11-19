# Monitoring stack: Prometheus scrapes the host's node exporter, Grafana serves dashboards.
# Grafana is reachable only over Tailscale: the LAN firewall keeps the ports closed and
# tailscale0 is a trusted interface. The admin password and the database encryption key are
# generated once on the host (the owner reads the password with:
# sudo cat /var/lib/grafana-admin-password) and are never in git.
{ config, ... }:

let
  grafanaPort = 3000;
  passwordFile = "/var/lib/grafana-admin-password";
  secretKeyFile = "/var/lib/grafana-secret-key";
in
{
  # Random admin password and DB encryption secret key, generated once on the host and
  # readable only by the grafana user. Rotating the secret key later would re-encrypt
  # nothing useful, so it is written once and left alone.
  systemd.services.grafana-secrets = {
    description = "Generate Grafana admin password and secret key if missing";
    before = [ "grafana.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -s ${passwordFile} ]; then
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 > ${passwordFile}
        chown grafana:grafana ${passwordFile}
        chmod 0400 ${passwordFile}
      fi
      if [ ! -s ${secretKeyFile} ]; then
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64 > ${secretKeyFile}
        chown grafana:grafana ${secretKeyFile}
        chmod 0400 ${secretKeyFile}
      fi
    '';
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
      port = 9100;
    };
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{ targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ]; }];
      }
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ "localhost:9090" ]; }];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = grafanaPort;
      };
      security = {
        admin_user = "vladyslav";
        admin_password = "$__file{${passwordFile}}";
        secret_key = "$__file{${secretKeyFile}}";
      };
      users.allow_sign_up = false;
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString config.services.prometheus.port}";
          isDefault = true;
          editable = false;
        }
      ];
    };
  };
}
