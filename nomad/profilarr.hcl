job "profilarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "profilarr.wizzdom.xyz"
  }

  group "web" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "profilarr"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.profilarr.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=false",
        "gatus.group=media",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "ghcr.io/dictionarry-hub/profilarr:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}:/config",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOF
HOST=0.0.0.0
PORT={{env "NOMAD_PORT_http"}}
ORIGIN=https://{{ env "NOMAD_META_domain" }}

# OIDC_CLIENT_SECRET
# OIDC_CLIENT_ID
# OIDC_DISCOVERY_URL

# PARSER_HOST={{ .Address }}
# PARSER_PORT={{ .Port }}
EOF
      }

      env {
        PUID  = "1000"
        PGID  = "1000"
        UMASK = "022"
        TZ    = "Europe/Dublin"
      }

      resources {
        cpu    = 300
        memory = 1024
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
      }
    }
  }

}
