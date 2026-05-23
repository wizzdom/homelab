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
daemon=300 # check every 300 seconds
ssl=yes
use=web

protocol=cloudflare, zone={{ key "ddclient/cloudflare/zone" }}, ttl=1, \
login={{ key "ddclient/cloudflare/api/login" }}, password={{ key "cloudflare/api/key" }}
{{ key "ddclient/cloudflare/domains" }}

EOH
      }
      resources {
        memory = 50
      }
    }
  }
}
