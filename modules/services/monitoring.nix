# Monitoring stack: Prometheus scrapes the host's node exporter, Grafana serves dashboards.
# Grafana is reachable only over Tailscale: the LAN firewall keeps the ports closed and
# tailscale0 is a trusted interface. The admin password is generated once on the host
# (the owner reads it with: sudo cat /var/lib/grafana-admin-password) and is never in git.
{ config, ... }:

let
  grafanaPort = 3000;
  passwordFile = "/var/lib/grafana-admin-password";
in
{
  # Random password generated once on the host, readable only by the grafana user.
  systemd.services.grafana-admin-password = {
    description = "Generate the Grafana admin password if missing";
    before = [ "grafana.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -s ${passwordFile} ]; then
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 > ${passwordFile}
        chown grafana:grafana ${passwordFile}
        chmod 0400 ${passwordFile}
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
