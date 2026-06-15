job "fmd" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "fmd.wizzdom.xyz"
  }

  group "fmd" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "fmd"
      port = "http"

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.fmd.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=tools",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "fmd" {
      driver = "docker"

      config {
        image = "registry.gitlab.com/fmd-foss/fmd-server:0.15.0-alpine"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/db:/var/lib/fmd-server/db",
          "local/config.yml:/etc/fmd-server/config.yml:ro",
        ]
      }

      template {
        destination = "local/config.yml"
        change_mode = "restart"
        data        = <<EOH
DatabaseDir: "/var/lib/fmd-server/db/"

PortInsecure: {{ env "NOMAD_PORT_http" }}

# The length for the user IDs that are generated
UserIdLength: 5

# How many location points or pictures FMD Server should save per account
MaxSavedLoc: 500
MaxSavedPic: 10

RegistrationToken: "{{ key "fmd/registration/token" }}"

RemoteIpHeader: "X-Real-IP"

# Custom OpenStreetMap tile server
# https://wiki.openstreetmap.org/wiki/Tile_servers
TileServerUrl: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"

# Address and port to run Prometheus metrics exporter on.
MetricsAddrPort: "[::1]:9100"
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
