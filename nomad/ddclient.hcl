job "ddclient" {
  datacenters = ["dc1"]
  type        = "service"

  group "ddns" {
    count = 1

    task "ddclient" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/ddclient:latest"
        volumes = [
          "local/ddclient.conf:/config/ddclient.conf"
        ]
      }

      template {
        destination = "local/ddclient.conf"
        change_mode = "noop"
        data        = <<EOH
daemon=300
syslog=yes
ssl=yes
pid=/var/run/ddclient.pid

usev4=webv4
webv4=api.ipify.org

# Cloudflare Configuration
protocol=cloudflare
zone={{ key "ddclient/cloudflare/zone" }}
login=token
password={{ key "ddclient/cloudflare/api/token" }}
{{ key "ddclient/cloudflare/domains" }}
EOH
      }
      resources {
        memory = 50
      }
    }
  }
}
